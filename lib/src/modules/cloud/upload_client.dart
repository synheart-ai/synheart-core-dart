import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../interfaces/auth_provider.dart';
import 'hmac_signer.dart';
import '../consent/consent_token.dart';
import 'upload_models.dart';
import 'cloud_exceptions.dart';
import '../../config/api_endpoints.dart';

class UploadClient {
  final String baseUrl;
  final http.Client _httpClient;

  UploadClient({required this.baseUrl, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  Future<UploadResponse> upload({
    required UploadRequest payload,
    HMACSigner? signer,
    String? apiKey,
    ConsentToken? consentToken,
    AuthProvider? authProvider,
  }) async {
    const method = 'POST';
    const path = ApiEndpoints.ingestPath;

    // Serialize payload once
    final bodyJson = jsonEncode(payload.toJson());

    // Send request with retry logic
    return await _uploadWithRetry(
      method: method,
      path: path,
      bodyJson: bodyJson,
      signer: signer,
      apiKey: apiKey,
      maxAttempts: 3,
      consentToken: consentToken,
      authProvider: authProvider,
    );
  }

  Future<UploadResponse> _uploadWithRetry({
    required String method,
    required String path,
    required String bodyJson,
    HMACSigner? signer,
    String? apiKey,
    required int maxAttempts,
    ConsentToken? consentToken,
    AuthProvider? authProvider,
  }) async {
    int attempts = 0;
    int baseDelay = 1000; // 1 second

    while (attempts < maxAttempts) {
      attempts++;

      try {
        final uri = Uri.parse('$baseUrl$path');
        final bodyBytes = Uint8List.fromList(utf8.encode(bodyJson));
        final headers = <String, String>{};

        if (authProvider != null) {
          // AuthProvider path — provider controls all auth headers
          final authHeaders = await authProvider.signRequest(
            method: method,
            path: path,
            bodyBytes: bodyBytes,
          );
          headers.addAll(authHeaders);
          headers['Content-Type'] = 'application/json';
        } else {
          // Existing HMAC path (unchanged)
          final nonce = signer!.generateNonce();
          final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final timestampStr = timestamp.toString();

          final signature = signer.computeSignature(
            timestamp: timestampStr,
            bodyJson: bodyJson,
          );

          headers['Content-Type'] = 'application/json';
          headers['X-API-Key'] = apiKey!;
          headers['X-Synheart-Signature'] = signature;
          headers['X-Synheart-Timestamp'] = timestampStr;
          headers['X-Synheart-Nonce'] = nonce;
        }

        // Add consent token if provided (direct JWT, not Bearer format)
        if (consentToken != null && consentToken.isValid) {
          headers['X-Consent-Token'] = consentToken.token;
        }

        final request = http.Request(method, uri)
          ..headers.addAll(headers)
          ..body = bodyJson;

        final streamedResponse = await _httpClient.send(request);
        final response = await http.Response.fromStream(streamedResponse);

        // Success: 200 (legacy) or 202 Accepted (async processing per API guide)
        if (response.statusCode == 200 || response.statusCode == 202) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          return UploadResponse.fromJson(body);
        }

        // Log every non-2xx response so the HSI upload error is visible in logcat
        print(
          '[CloudConnector] HSI upload error: status=${response.statusCode} body=${response.body}',
        );

        // Parse error response (API may return JSON or plain text e.g. "404 page not found")
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

        // Handle 401 with AuthProvider retry (before specific error handling)
        if (response.statusCode == 401 && authProvider != null) {
          final handled = await authProvider.onAuthError(
            statusCode: 401,
            responseHeaders: response.headers,
          );
          if (handled && attempts < maxAttempts) {
            continue; // Retry with corrected auth
          }
        }

        // Handle specific errors (backend uses INVALID_SIGNATURE etc.; support snake_case too)
        if (response.statusCode == 401) {
          if (code == 'invalid_signature' || code == 'invalid_api_key') {
            throw InvalidSignatureError();
          } else if (code == 'invalid_token' || code == 'token_expired') {
            throw TokenExpiredError('Consent token expired or invalid');
          } else {
            throw InvalidSignatureError();
          }
        } else if (response.statusCode == 403) {
          if (code == 'invalid_tenant' || code == 'invalid_signature') {
            throw code == 'invalid_signature'
                ? InvalidSignatureError()
                : InvalidTenantError();
          }
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

        // Generic error - retry
        if (attempts >= maxAttempts) {
          throw CloudConnectorException('Upload failed: $message');
        }
      } catch (e) {
        if (e is CloudConnectorException) {
          rethrow; // Don't retry on known exceptions
        }

        if (attempts >= maxAttempts) {
          throw NetworkError('Upload failed after $maxAttempts attempts: $e');
        }
      }

      // Exponential backoff: 1s, 2s, 4s
      final delay = baseDelay * (1 << (attempts - 1));
      await Future.delayed(Duration(milliseconds: delay));
    }

    throw NetworkError('Upload failed after $maxAttempts attempts');
  }

  void dispose() {
    _httpClient.close();
  }
}
