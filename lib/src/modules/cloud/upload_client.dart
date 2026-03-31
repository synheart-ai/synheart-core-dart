import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../interfaces/auth_provider.dart';
import '../consent/consent_token.dart';
import 'upload_models.dart';
import 'cloud_exceptions.dart';
import '../../config/api_endpoints.dart';

/// Cloud upload client for HSI data ingestion.
///
/// Auth model (post security rewrite):
///   Authorization: Bearer {consentToken}   — standard JWT from ConsentModule
///   + X-Synheart-* device headers          — defense-in-depth (optional)
///
/// HMAC signing removed — device attestation at token issuance replaces it.
class UploadClient {
  final String baseUrl;
  final http.Client _httpClient;

  UploadClient({required this.baseUrl, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  Future<UploadResponse> upload({
    required UploadRequest payload,
    ConsentToken? consentToken,
    AuthProvider? deviceAuth,
  }) async {
    const method = 'POST';
    const path = ApiEndpoints.ingestPath;

    final bodyJson = jsonEncode(payload.toJson());

    return await _uploadWithRetry(
      method: method,
      path: path,
      bodyJson: bodyJson,
      maxAttempts: 3,
      consentToken: consentToken,
      deviceAuth: deviceAuth,
    );
  }

  Future<UploadResponse> _uploadWithRetry({
    required String method,
    required String path,
    required String bodyJson,
    required int maxAttempts,
    ConsentToken? consentToken,
    AuthProvider? deviceAuth,
  }) async {
    int attempts = 0;
    int baseDelay = 1000;

    while (attempts < maxAttempts) {
      attempts++;

      try {
        final uri = Uri.parse('$baseUrl$path');
        final bodyBytes = Uint8List.fromList(utf8.encode(bodyJson));
        final headers = <String, String>{
          'Content-Type': 'application/json',
        };

        // Bearer token from consent module (standard auth)
        if (consentToken != null && consentToken.isValid) {
          headers['Authorization'] = 'Bearer ${consentToken.token}';
        }

        // Device signature headers (defense-in-depth, optional)
        if (deviceAuth != null) {
          final deviceHeaders = await deviceAuth.signRequest(
            method: method,
            path: path,
            bodyBytes: bodyBytes,
          );
          headers.addAll(deviceHeaders);
        }

        final request = http.Request(method, uri)
          ..headers.addAll(headers)
          ..body = bodyJson;

        final streamedResponse = await _httpClient.send(request);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 || response.statusCode == 202) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          return UploadResponse.fromJson(body);
        }

        Map<String, dynamic>? errorBody;
        try {
          errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
        } catch (_) {
          throw CloudConnectorException(
            'Upload failed: ${response.statusCode} ${response.body}',
          );
        }
        if (errorBody == null) {
          throw CloudConnectorException(
            'Upload failed: ${response.statusCode} ${response.body}',
          );
        }

        UploadErrorResponse error;
        try {
          error = UploadErrorResponse.fromJson(errorBody);
        } catch (_) {
          throw CloudConnectorException(
            'Upload failed: ${response.statusCode} ${response.body}',
          );
        }

        final code = error.errorCode.toLowerCase();
        final message = error.errorMessage;

        // Handle 401 with device auth retry
        if (response.statusCode == 401 && deviceAuth != null) {
          final handled = await deviceAuth.onAuthError(
            statusCode: 401,
            responseHeaders: response.headers,
          );
          if (handled && attempts < maxAttempts) {
            continue;
          }
        }

        if (response.statusCode == 401) {
          if (code == 'token_expired' || code == 'invalid_token') {
            throw TokenExpiredError('Consent token expired or invalid');
          }
          throw InvalidSignatureError();
        } else if (response.statusCode == 403) {
          throw InvalidSignatureError();
        } else if (response.statusCode == 400) {
          if (code == 'schema_validation_failed' ||
              code == 'validation_error' ||
              code == 'hsi_schema_validation_failed') {
            throw SchemaValidationError();
          }
          throw CloudConnectorException('Upload failed: $message');
        } else if (response.statusCode == 429) {
          throw RateLimitExceededError(error.retryAfter ?? 60);
        }

        if (attempts >= maxAttempts) {
          throw CloudConnectorException('Upload failed: $message');
        }
      } catch (e) {
        if (e is CloudConnectorException) rethrow;

        if (attempts >= maxAttempts) {
          throw NetworkError('Upload failed after $maxAttempts attempts: $e');
        }
      }

      final delay = baseDelay * (1 << (attempts - 1));
      await Future.delayed(Duration(milliseconds: delay));
    }

    throw NetworkError('Upload failed after $maxAttempts attempts');
  }

  void dispose() {
    _httpClient.close();
  }
}
