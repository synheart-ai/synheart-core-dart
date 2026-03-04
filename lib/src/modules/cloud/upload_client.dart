import 'dart:convert';
import 'package:http/http.dart' as http;
import 'hmac_signer.dart';
import '../consent/consent_token.dart';
import 'upload_models.dart';
import 'cloud_exceptions.dart';

class UploadClient {
  final String baseUrl;
  final http.Client _httpClient;

  UploadClient({required this.baseUrl, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  Future<UploadResponse> upload({
    required UploadRequest payload,
    required HMACSigner signer,
    required String apiKey,
    ConsentToken? consentToken,
  }) async {
    const method = 'POST';
    const path = '/v2/hsi/ingest';

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
    );
  }

  Future<UploadResponse> _uploadWithRetry({
    required String method,
    required String path,
    required String bodyJson,
    required HMACSigner signer,
    required String apiKey,
    required int maxAttempts,
    ConsentToken? consentToken,
  }) async {
    int attempts = 0;
    int baseDelay = 1000; // 1 second

    while (attempts < maxAttempts) {
      attempts++;

      try {
        // Generate nonce and timestamp for each attempt
        final nonce = signer.generateNonce();
        final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final timestampStr = timestamp.toString();

        // Compute HMAC signature (simple: timestamp + payload)
        final signature = signer.computeSignature(
          timestamp: timestampStr,
          bodyJson: bodyJson,
        );

        // Build fresh request for each attempt
        final uri = Uri.parse('$baseUrl$path');
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
          'X-Synheart-Signature': signature,
          'X-Synheart-Timestamp': timestampStr,
          'X-Synheart-Nonce': nonce,
        };

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

        // Parse error response (API may return { "error": { "code", "message", "details?" } })
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
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
