import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../modules/consent/consent_module.dart';
import '../crypto/smk.dart';
import '../crypto/urk.dart';
import '../storage/storage_manager.dart';
import 'artifact_envelope.dart';
import 'sync_engine.dart';

/// High-level sync orchestrator (RFC-CORE-0005).
///
/// Uses ConsentModule for access tokens (scoped JWT from consent-service).
/// session_secret and subjectId are provided directly by the Synheart entry point.
class SyncModule {
  final ConsentModule _consent;
  final StorageManager _storage;
  final SyncEngine _engine;
  final String _baseUrl;
  final String? _subjectId;
  final String? _sessionSecret;
  bool _enabled = false;
  bool _syncReady = false;
  URK? _urk;
  SMK? _smk;

  SyncModule({
    required ConsentModule consent,
    required StorageManager storage,
    required String baseUrl,
    SMK? smk,
    String? subjectId,
    String? sessionSecret,
  })  : _consent = consent,
        _storage = storage,
        _baseUrl = baseUrl,
        _smk = smk,
        _subjectId = subjectId,
        _sessionSecret = sessionSecret,
        _engine = SyncEngine(storage: storage, baseUrl: baseUrl);

  bool get enabled => _enabled;
  bool get syncReady => _syncReady;

  /// Get the current access token from ConsentModule.
  String? get _accessToken => _consent.getCurrentToken()?.token;

  /// Check if we have a valid consent token.
  bool get _hasValidToken => _consent.getCurrentToken() != null;

  /// Enable or disable sync.
  Future<void> setSyncEnabled(bool enabled) async {
    _enabled = enabled;
    if (enabled) {
      await _storage.setSyncState('sync_enabled', 'true');
      if (_urk == null && _hasValidToken) {
        await _provisionURK();
      }
    } else {
      await _storage.setSyncState('sync_enabled', 'false');
    }
  }

  /// Execute a sync cycle (push + pull) with retry and exponential backoff.
  Future<SyncResult> syncNow() async {
    if (!_enabled || !_hasValidToken) {
      return const SyncResult();
    }

    _engine.updateAccessToken(_accessToken);

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

      _engine.updateAccessToken(_accessToken);

      try {
        pushed = await _engine.push(urk: _urk!.bytes);
      } catch (e) {
        final is401 = e.toString().contains('401');
        if (is401 && attempt < 2) {
          try {
            await _consent.refreshTokenIfNeeded();
            _engine.updateAccessToken(_accessToken);
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
          subjectId: _subjectId ?? '',
          cursor: cursor,
        );
      } catch (e) {
        final is401 = e.toString().contains('401');
        if (is401 && attempt < 2) {
          try {
            await _consent.refreshTokenIfNeeded();
            _engine.updateAccessToken(_accessToken);
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
    if (_sessionSecret == null || _subjectId == null) return;

    // Try to fetch existing URK bundle from server
    try {
      final getResponse = await http.get(
        Uri.parse('$_baseUrl/sync/v1/urk-bundle'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );

      if (getResponse.statusCode == 200) {
        final bundle = jsonDecode(getResponse.body) as Map<String, dynamic>;
        final urk = await URK.decryptBundle(
          bundle: bundle,
          sessionSecret: _sessionSecret!,
          subjectId: _subjectId!,
        );
        await urk.wrapAndStore();
        _urk = urk;
        _syncReady = true;
        return;
      }
    } catch (_) {
      // Fall through to generate new URK
    }

    // Generate new URK, encrypt bundle, and upload
    final urk = URK.generate();

    try {
      final bundle = await URK.encryptBundle(
        urk: urk.bytes,
        sessionSecret: _sessionSecret!,
        subjectId: _subjectId!,
      );

      await http.put(
        Uri.parse('$_baseUrl/sync/v1/urk-bundle'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode(bundle),
      );
    } catch (_) {
      // Bundle upload failed — URK still usable locally
    }

    await urk.wrapAndStore();
    _urk = urk;
    _syncReady = true;
  }

  /// Clean up URK from memory.
  void dispose() {
    _urk = null;
    _enabled = false;
  }
}
