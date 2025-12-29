import 'dart:convert';
import 'package:http/http.dart' as http;
import 'hmac_signer.dart';
import 'upload_models.dart';
import 'cloud_exceptions.dart';

class UploadClient {
  final String baseUrl;
  final http.Client _httpClient;

  UploadClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  Future<UploadResponse> upload({
    required UploadRequest payload,
    required HMACSigner signer,
    required String tenantId,
  }) async {
    const method = 'POST';
    const path = '/v1/ingest/hsi';

    // Serialize payload once
    final bodyJson = jsonEncode(payload.toJson());

    // Send request with retry logic
    return await _uploadWithRetry(
      method: method,
      path: path,
      bodyJson: bodyJson,
      signer: signer,
      tenantId: tenantId,
      maxAttempts: 3,
    );
  }

  Future<UploadResponse> _uploadWithRetry({
    required String method,
    required String path,
    required String bodyJson,
    required HMACSigner signer,
    required String tenantId,
    required int maxAttempts,
  }) async {
    int attempts = 0;
    int baseDelay = 1000; // 1 second

    while (attempts < maxAttempts) {
      attempts++;

      try {
        // Generate nonce and timestamp for each attempt
        final nonce = signer.generateNonce();
        final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // Compute HMAC signature
        final signature = signer.computeSignature(
          method: method,
          path: path,
          tenantId: tenantId,
          timestamp: timestamp,
          nonce: nonce,
          bodyJson: bodyJson,
        );

        // Build fresh request for each attempt
        final uri = Uri.parse('$baseUrl$path');
        final request = http.Request(method, uri)
          ..headers.addAll({
            'Content-Type': 'application/json',
            'X-Synheart-Tenant': tenantId,
            'X-Synheart-Signature': signature,
            'X-Synheart-Nonce': nonce,
            'X-Synheart-Timestamp': timestamp.toString(),
            'X-Synheart-SDK-Version': '1.0.0',
          })
          ..body = bodyJson;

        final streamedResponse = await _httpClient.send(request);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          return UploadResponse.fromJson(jsonDecode(response.body));
        }

        // Parse error response
        final errorBody = jsonDecode(response.body);
        final error = UploadErrorResponse.fromJson(errorBody);

        // Handle specific errors
        if (response.statusCode == 401 && error.code == 'invalid_signature') {
          throw InvalidSignatureError();
        } else if (response.statusCode == 403 &&
            error.code == 'invalid_tenant') {
          throw InvalidTenantError();
        } else if (response.statusCode == 400 &&
            error.code == 'schema_validation_failed') {
          throw SchemaValidationError();
        } else if (response.statusCode == 429) {
          throw RateLimitExceededError(error.retryAfter ?? 60);
        }

        // Generic error - retry
        if (attempts >= maxAttempts) {
          throw CloudConnectorException('Upload failed: ${error.message}');
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
