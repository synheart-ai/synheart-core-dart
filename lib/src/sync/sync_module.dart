import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/auth_module.dart';
import '../crypto/smk.dart';
import '../crypto/urk.dart';
import '../storage/storage_manager.dart';
import 'artifact_envelope.dart';
import 'sync_engine.dart';

/// High-level sync orchestrator (RFC-CORE-0005).
///
/// Bridges AuthModule, URK, StorageManager, and SyncEngine.
class SyncModule {
  final AuthModule _auth;
  final StorageManager _storage;
  final SyncEngine _engine;
  final String _baseUrl;
  bool _enabled = false;
  URK? _urk;
  SMK? _smk;

  SyncModule({
    required AuthModule auth,
    required StorageManager storage,
    required String baseUrl,
    SMK? smk,
  })  : _auth = auth,
        _storage = storage,
        _baseUrl = baseUrl,
        _smk = smk,
        _engine = SyncEngine(storage: storage, baseUrl: baseUrl);

  bool get enabled => _enabled;

  /// Enable or disable sync.
  Future<void> setSyncEnabled(bool enabled) async {
    _enabled = enabled;
    if (enabled) {
      await _storage.setSyncState('sync_enabled', 'true');
      // Provision URK if needed
      if (_urk == null && _auth.isAuthenticated) {
        await _provisionURK();
      }
    } else {
      await _storage.setSyncState('sync_enabled', 'false');
    }
  }

  /// Execute a sync cycle (push + pull) with retry and exponential backoff.
  Future<SyncResult> syncNow() async {
    if (!_enabled || !_auth.isAuthenticated) {
      return const SyncResult();
    }

    _engine.updateAccessToken(_auth.accessToken);

    // Ensure URK is available
    if (_urk == null) {
      _urk = await URK.unwrap();
      if (_urk == null) {
        await _provisionURK();
      }
    }

    if (_urk == null) {
      return const SyncResult(errors: ['URK unavailable']);
    }

    if (_smk == null) {
      return const SyncResult(errors: ['SMK unavailable']);
    }

    final errors = <String>[];
    int pushed = 0;
    int pulled = 0;
    final rng = Random();

    // Retry loop with exponential backoff
    for (var attempt = 0; attempt < 3; attempt++) {
      errors.clear();
      pushed = 0;
      pulled = 0;

      _engine.updateAccessToken(_auth.accessToken);

      try {
        pushed = await _engine.push(urk: _urk!.bytes);
      } catch (e) {
        final is401 = e.toString().contains('401');
        if (is401 && attempt < 2) {
          try {
            await _auth.refreshToken();
            final backoffMs = (1000 * (1 << attempt)) + rng.nextInt(500);
            await Future<void>.delayed(Duration(milliseconds: backoffMs));
            continue;
          } catch (_) {
            errors.add('Push failed: $e');
            break;
          }
        }
        errors.add('Push failed: $e');
      }

      try {
        final cursor = await _storage.getSyncState('cursor');
        pulled = await _engine.pull(
          urk: _urk!.bytes,
          smkBytes: _smk!.bytes,
          subjectId: _auth.subjectId ?? '',
          cursor: cursor,
        );
      } catch (e) {
        final is401 = e.toString().contains('401');
        if (is401 && attempt < 2) {
          try {
            await _auth.refreshToken();
            final backoffMs = (1000 * (1 << attempt)) + rng.nextInt(500);
            await Future<void>.delayed(Duration(milliseconds: backoffMs));
            continue;
          } catch (_) {
            errors.add('Pull failed: $e');
            break;
          }
        }
        errors.add('Pull failed: $e');
      }

      // If we got here without continuing, we're done
      break;
    }

    if (errors.isEmpty) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await _storage.setSyncState('last_sync_ms', nowMs.toString());
    }

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      errors: errors,
    );
  }

  /// Get current sync status.
  Future<SyncStatus> getStatus() async {
    final cursor = await _storage.getSyncState('cursor');
    final lastSyncStr = await _storage.getSyncState('last_sync_ms');
    final pendingCount = await _storage.getUnsyncedCount();

    return SyncStatus(
      enabled: _enabled,
      lastSuccessMs: lastSyncStr != null ? int.tryParse(lastSyncStr) : null,
      pendingUploadCount: pendingCount,
      cursor: cursor,
    );
  }

  Future<void> _provisionURK() async {
    final sessionSecret = _auth.sessionSecret;
    final subjectId = _auth.subjectId;
    if (sessionSecret == null || subjectId == null) return;

    // Try to fetch existing URK bundle from server
    try {
      final getResponse = await http.get(
        Uri.parse('$_baseUrl/sync/v1/urk-bundle'),
        headers: {
          'Authorization': 'Bearer ${_auth.accessToken}',
        },
      );

      if (getResponse.statusCode == 200) {
        // Decrypt existing bundle
        final bundle = jsonDecode(getResponse.body) as Map<String, dynamic>;
        final urk = await URK.decryptBundle(
          bundle: bundle,
          sessionSecret: sessionSecret,
          subjectId: subjectId,
        );
        await urk.wrapAndStore();
        _urk = urk;
        _auth.markSyncReady();
        return;
      }
    } catch (_) {
      // Fall through to generate new URK
    }

    // Generate new URK, encrypt bundle, and upload to server
    final urk = URK.generate();

    try {
      final bundle = await URK.encryptBundle(
        urk: urk.bytes,
        sessionSecret: sessionSecret,
        subjectId: subjectId,
      );

      await http.put(
        Uri.parse('$_baseUrl/sync/v1/urk-bundle'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_auth.accessToken}',
        },
        body: jsonEncode(bundle),
      );
    } catch (_) {
      // Bundle upload failed — URK still usable locally
    }

    await urk.wrapAndStore();
    _urk = urk;
    _auth.markSyncReady();
  }

  /// Clean up URK from memory.
  void dispose() {
    _urk = null;
    _enabled = false;
  }
}
