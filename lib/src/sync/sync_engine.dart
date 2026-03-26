import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../crypto/urk.dart';
import '../storage/storage_manager.dart';
import 'artifact_envelope.dart';

/// Core sync engine — handles push/pull with E2EE (RFC-CORE-0005).
class SyncEngine {
  final StorageManager _storage;
  final String _baseUrl;
  String? _accessToken;

  SyncEngine({
    required StorageManager storage,
    required String baseUrl,
  })  : _storage = storage,
        _baseUrl = baseUrl;

  void updateAccessToken(String? token) {
    _accessToken = token;
  }

  /// Encrypt a local artifact for sync upload.
  Future<ArtifactEnvelope> encryptForSync({
    required Uint8List urk,
    required Map<String, dynamic> artifactRecord,
    required Uint8List payload,
  }) async {
    final artifactId = artifactRecord['artifact_id'] as String;

    // Derive per-artifact key
    final artKey = await URK.deriveArtifactKey(urk: urk, artifactId: artifactId);

    // SHA-256 of plaintext payload
    final digest = hash.sha256.convert(payload);
    final sha256Hex = digest.toString();

    // Encrypt with XChaCha20-Poly1305
    final cipher = Xchacha20.poly1305Aead();
    final key = SecretKey(artKey);
    final box = await cipher.encrypt(payload, secretKey: key);

    final ctWithMac = Uint8List.fromList(box.cipherText + box.mac.bytes);

    return ArtifactEnvelope(
      artifactId: artifactId,
      subjectId: artifactRecord['subject_id'] as String,
      sessionId: artifactRecord['session_id'] as String?,
      type: artifactRecord['type'] as String,
      startMs: artifactRecord['start_ms'] as int,
      endMs: artifactRecord['end_ms'] as int,
      seq: artifactRecord['seq'] as int?,
      schemaName: artifactRecord['schema_name'] as String,
      schemaVersion: artifactRecord['schema_version'] as String,
      nonceB64: base64Encode(Uint8List.fromList(box.nonce)),
      payloadSha256: sha256Hex,
      ciphertextB64: base64Encode(ctWithMac),
    );
  }

  /// Push unsynced artifacts to the server.
  Future<int> push({required Uint8List urk}) async {
    if (_accessToken == null) return 0;

    final artifacts = await _storage.getUnsyncedArtifacts(limit: 50);
    if (artifacts.isEmpty) return 0;

    final envelopes = <Map<String, dynamic>>[];
    for (final art in artifacts) {
      final envelope = await encryptForSync(
        urk: urk,
        artifactRecord: art,
        payload: art['payload'] as Uint8List,
      );
      envelopes.add(envelope.toJson());
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/sync/v1/push'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_accessToken',
      },
      body: jsonEncode({'envelopes': envelopes}),
    );

    if (response.statusCode == 200) {
      for (final art in artifacts) {
        await _storage.markSynced(art['artifact_id'] as String);
      }
      return artifacts.length;
    }

    return 0;
  }

  /// Pull new artifacts from the server.
  Future<int> pull({
    required Uint8List urk,
    required Uint8List smkBytes,
    required String subjectId,
    String? cursor,
  }) async {
    if (_accessToken == null) return 0;

    int totalPulled = 0;
    String? currentCursor = cursor;

    while (true) {
      final queryParams = {
        'subject_id': subjectId,
        'limit': '100',
        if (currentCursor != null) 'cursor': currentCursor,
      };

      final uri = Uri.parse('$_baseUrl/sync/v1/pull').replace(queryParameters: queryParams);
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode != 200) break;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final envelopes = (body['envelopes'] as List)
          .map((e) => ArtifactEnvelope.fromJson(e as Map<String, dynamic>))
          .toList();

      for (final env in envelopes) {
        // Skip tombstoned or existing
        if (await _storage.isDeleted(env.artifactId)) continue;
        if (await _storage.getArtifact(env.artifactId) != null) continue;

        // Decrypt
        final artKey = await URK.deriveArtifactKey(urk: urk, artifactId: env.artifactId);
        final ctAndMac = base64Decode(env.ciphertextB64);
        final nonce = base64Decode(env.nonceB64);

        const macLen = 16;
        final ct = ctAndMac.sublist(0, ctAndMac.length - macLen);
        final mac = ctAndMac.sublist(ctAndMac.length - macLen);

        final cipher = Xchacha20.poly1305Aead();
        final key = SecretKey(artKey);
        final box = SecretBox(ct, nonce: nonce, mac: Mac(mac));

        List<int> plaintext;
        try {
          plaintext = await cipher.decrypt(box, secretKey: key);
        } catch (_) {
          continue;
        }

        // Verify integrity
        final digest = hash.sha256.convert(plaintext);
        if (digest.toString() != env.payloadSha256) continue;

        // Merge conflict check (RFC-CORE-0006): skip if a better existing
        // artifact with the same merge key already exists.
        if (await _hasBetterExisting(env)) continue;

        // Re-encrypt with SMK and store locally
        await _storage.insertSyncedArtifact(
          artifactId: env.artifactId,
          subjectId: env.subjectId,
          sessionId: env.sessionId,
          type: env.type,
          schemaName: env.schemaName,
          schemaVersion: env.schemaVersion,
          startMs: env.startMs,
          endMs: env.endMs,
          seq: env.seq,
          payload: Uint8List.fromList(plaintext),
          payloadSha256: env.payloadSha256,
          smkBytes: smkBytes,
        );
        totalPulled++;
      }

      currentCursor = body['next_cursor'] as String?;
      final hasMore = body['has_more'] as bool? ?? false;
      if (!hasMore) break;
    }

    if (currentCursor != null) {
      await _storage.setSyncState('cursor', currentCursor);
    }

    return totalPulled;
  }

  /// Check if an artifact with the same merge key already exists and has a
  /// lexicographically smaller artifact_id (i.e. "wins" the conflict).
  ///
  /// Merge key: (session_id, type, start_ms, schema_version).
  /// Per RFC-CORE-0006, the smallest artifact_id wins.
  Future<bool> _hasBetterExisting(ArtifactEnvelope env) async {
    final existingId = await _storage.findSmallestArtifactIdByMergeKey(
      sessionId: env.sessionId,
      type: env.type,
      startMs: env.startMs,
      schemaVersion: env.schemaVersion,
    );
    if (existingId == null) return false;
    // If the existing artifact_id is lexicographically smaller or equal,
    // the incoming one loses — skip it.
    return existingId.compareTo(env.artifactId) <= 0;
  }
}
