import 'dart:typed_data';

/// Interface for pluggable request authentication.
///
/// Implementations sign outgoing HTTP requests with custom auth schemes
/// (e.g., ECDSA device-identity signing from synheart-auth).
///
/// The SDK ships with HMAC-SHA256 as the default. When an [AuthProvider]
/// is set on [CloudConfig], it takes precedence over the HMAC path.
abstract class AuthProvider {
  /// Sign an outgoing request and return headers to attach.
  ///
  /// The returned map is merged into the HTTP request headers.
  /// Typical headers: `Authorization`, `X-Device-Signature`, etc.
  ///
  /// - [method]: HTTP method (e.g., "POST")
  /// - [path]: Request path (e.g., "/v2/hsi/ingest")
  /// - [bodyBytes]: Serialized request body
  Future<Map<String, String>> signRequest({
    required String method,
    required String path,
    required Uint8List bodyBytes,
  });

  /// Called when the server returns a 401 for a request signed by this provider.
  ///
  /// Return `true` if the error was handled (e.g., key rotation completed)
  /// and the request should be retried. Return `false` to propagate the error.
  ///
  /// - [statusCode]: HTTP status code (always 401)
  /// - [responseHeaders]: Response headers from the server
  Future<bool> onAuthError({
    required int statusCode,
    required Map<String, String> responseHeaders,
  });
}
