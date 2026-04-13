import 'dart:typed_data';
import '../../core/logger.dart';
import '../../core_runtime/core_runtime_bridge.dart';
import '../interfaces/auth_provider.dart';

/// [AuthProvider] backed by core-runtime proof generation.
///
/// Runtime-only policy: this provider must not call platform SDK/API code
/// for outbound auth. It only asks core-runtime to build `X-Synheart-Proof`.
class DeviceAuthProvider implements AuthProvider {
  final CoreRuntimeBridge _coreRuntime;
  final String _baseUrl;

  DeviceAuthProvider({
    required CoreRuntimeBridge coreRuntime,
    required String baseUrl,
  })  : _coreRuntime = coreRuntime,
        _baseUrl = baseUrl;

  @override
  Future<Map<String, String>> signRequest({
    required String method,
    required String path,
    required Uint8List bodyBytes,
  }) async {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final absoluteUrl = '${_baseUrl.replaceAll(RegExp(r'/+$'), '')}$normalizedPath';
    final proof = _coreRuntime.buildProofHeader(method.toUpperCase(), absoluteUrl);
    if (proof == null || proof.isEmpty) {
      SynheartLogger.log(
        '[DeviceAuth] Failed to build runtime proof header for $method $normalizedPath',
      );
      return <String, String>{};
    }
    return <String, String>{'X-Synheart-Proof': proof};
  }

  @override
  Future<bool> onAuthError({
    required int statusCode,
    required Map<String, String> responseHeaders,
  }) async {
    // Runtime-only auth path: the runtime does not currently expose clock-skew
    // correction or key-rotation APIs through the proof-header FFI, so neither
    // class of 401 is recoverable from the SDK side. Surface the known signals
    // in logs so the gap is visible, then propagate the error.
    //
    // TODO(runtime): wire synheart_core_sdk_apply_server_ts and
    //   synheart_core_sdk_rotate_key so we can return true and retry here.
    final serverTs = responseHeaders['x-server-timestamp'];
    if (serverTs != null) {
      SynheartLogger.log(
        '[DeviceAuth] 401 with x-server-timestamp=$serverTs — '
        'runtime proof uses device clock; skew correction not yet exposed.',
      );
    }
    final errCode = responseHeaders['x-synheart-error'];
    if (errCode == 'KEY_INVALIDATED') {
      SynheartLogger.log(
        '[DeviceAuth] 401 KEY_INVALIDATED — '
        'runtime key rotation not yet implemented; re-registration required.',
      );
    }
    return false;
  }
}
