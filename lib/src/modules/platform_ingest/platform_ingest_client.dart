import 'dart:convert';
import 'package:http/http.dart' as http;
import '../cloud/hmac_signer.dart';
import '../../config/api_endpoints.dart';

/// Response from platform ingestion API calls.
class PlatformIngestResponse {
  final bool success;
  final int statusCode;
  final Map<String, dynamic>? body;
  final String? errorMessage;

  const PlatformIngestResponse({
    required this.success,
    required this.statusCode,
    this.body,
    this.errorMessage,
  });

  @override
  String toString() =>
      'PlatformIngestResponse(success=$success, statusCode=$statusCode'
      '${errorMessage != null ? ', error=$errorMessage' : ''})';
}

/// Stateless HTTP client for platform session and metadata ingestion.
///
/// Can be used standalone (without full SDK init) — e.g. from a
/// WorkManager background task — by providing [HMACSigner], apiKey,
/// and consent token directly.
class PlatformIngestClient {
  final String baseUrl;
  final Duration timeout;
  final int maxRetries;
  final http.Client _httpClient;

  PlatformIngestClient({
    this.baseUrl = ApiEndpoints.defaultPlatformIngestBaseUrl,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// POST a session payload to `/v1/platform/session/ingest`.
  Future<PlatformIngestResponse> ingestSession({
    required Map<String, dynamic> payload,
    required HMACSigner signer,
    required String apiKey,
    String? consentToken,
  }) {
    return _post(
      path: ApiEndpoints.platformSessionIngestPath,
      payload: payload,
      signer: signer,
      apiKey: apiKey,
      consentToken: consentToken,
    );
  }

  /// POST a metadata payload to `/v1/platform/metadata/ingest`.
  Future<PlatformIngestResponse> ingestMetadata({
    required Map<String, dynamic> payload,
    required HMACSigner signer,
    required String apiKey,
    String? consentToken,
  }) {
    return _post(
      path: ApiEndpoints.platformMetadataIngestPath,
      payload: payload,
      signer: signer,
      apiKey: apiKey,
      consentToken: consentToken,
    );
  }

  Future<PlatformIngestResponse> _post({
    required String path,
    required Map<String, dynamic> payload,
    required HMACSigner signer,
    required String apiKey,
    String? consentToken,
  }) async {
    final bodyJson = jsonEncode(payload);
    int attempts = 0;

    while (attempts < maxRetries) {
      attempts++;
      try {
        final uri = Uri.parse('$baseUrl$path');

        final nonce = signer.generateNonce();
        final timestamp =
            (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
        final signature = signer.computeSignature(
          timestamp: timestamp,
          bodyJson: bodyJson,
        );

        final headers = <String, String>{
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
          'X-Synheart-Signature': signature,
          'X-Synheart-Timestamp': timestamp,
          'X-Synheart-Nonce': nonce,
        };

        if (consentToken != null && consentToken.isNotEmpty) {
          headers['X-Consent-Token'] = consentToken;
        }

        final response = await _httpClient
            .post(uri, headers: headers, body: bodyJson)
            .timeout(timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          Map<String, dynamic>? responseBody;
          try {
            responseBody =
                jsonDecode(response.body) as Map<String, dynamic>;
          } catch (_) {}
          return PlatformIngestResponse(
            success: true,
            statusCode: response.statusCode,
            body: responseBody,
          );
        }

        // 4xx — don't retry client errors
        if (response.statusCode >= 400 && response.statusCode < 500) {
          return PlatformIngestResponse(
            success: false,
            statusCode: response.statusCode,
            errorMessage:
                'Client error: HTTP ${response.statusCode}',
            body: _tryParseJson(response.body),
          );
        }

        // 5xx — retry with exponential backoff
        if (attempts < maxRetries) {
          await Future.delayed(Duration(seconds: 1 << attempts));
          continue;
        }

        return PlatformIngestResponse(
          success: false,
          statusCode: response.statusCode,
          errorMessage: 'Server error: HTTP ${response.statusCode}',
          body: _tryParseJson(response.body),
        );
      } catch (e) {
        if (attempts >= maxRetries) {
          return PlatformIngestResponse(
            success: false,
            statusCode: 0,
            errorMessage: 'Request failed after $maxRetries attempts: $e',
          );
        }
        await Future.delayed(Duration(seconds: 1 << attempts));
      }
    }

    return const PlatformIngestResponse(
      success: false,
      statusCode: 0,
      errorMessage: 'Request failed: max retries exceeded',
    );
  }

  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
