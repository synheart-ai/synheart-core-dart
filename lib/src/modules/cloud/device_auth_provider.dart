import 'dart:typed_data';
import 'package:synheart_auth/synheart_auth.dart';
import '../../core/logger.dart';
import '../interfaces/auth_provider.dart';

/// [AuthProvider] backed by SynheartAuth device-identity signing.
///
/// Wraps [SynheartAuth.signRequest] to produce the signed header set
/// (X-App-ID, X-Device-ID, X-Synheart-Signature, etc.) for every
/// outgoing request to cloud and platform ingest services.
class DeviceAuthProvider implements AuthProvider {
  final SynheartAuth _auth;
  final String _appId;

  DeviceAuthProvider({
    required String appId,
    SynheartAuth? auth,
  })  : _appId = appId,
        _auth = auth ?? SynheartAuth.instance;

  @override
  Future<Map<String, String>> signRequest({
    required String method,
    required String path,
    required Uint8List bodyBytes,
  }) async {
    final signed = await _auth.signRequest(
      appId: _appId,
      method: method,
      path: path,
      bodyBytes: bodyBytes,
    );
    return signed.toMap();
  }

  @override
  Future<bool> onAuthError({
    required int statusCode,
    required Map<String, String> responseHeaders,
  }) async {
    // Handle clock skew — server sends its timestamp so we can correct drift.
    final serverTs = responseHeaders['x-server-timestamp'];
    if (serverTs != null) {
      final ts = double.tryParse(serverTs);
      if (ts != null) {
        await _auth.correctClockSkew(ts);
        SynheartLogger.log('[DeviceAuth] Clock skew corrected, retrying');
        return true;
      }
    }

    // Handle key invalidation — rotate and retry.
    final errorCode = responseHeaders['x-synheart-error'];
    if (errorCode == 'KEY_INVALIDATED') {
      try {
        final result = await _auth.rotateKey(_appId);
        if (result.status == RotationStatus.success) {
          SynheartLogger.log('[DeviceAuth] Key rotated, retrying');
          return true;
        }
      } catch (e) {
        SynheartLogger.log('[DeviceAuth] Key rotation failed: $e', error: e);
      }
    }

    return false;
  }
}
