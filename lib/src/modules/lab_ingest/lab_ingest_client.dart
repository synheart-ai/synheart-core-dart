import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/api_endpoints.dart';
import '../../core/logger.dart';

/// Response from lab ingestion API calls.
class LabIngestResponse {
  final bool success;
  final int statusCode;
  final Map<String, dynamic>? body;
  final String? errorMessage;

  const LabIngestResponse({
    required this.success,
    required this.statusCode,
    this.body,
    this.errorMessage,
  });

  @override
  String toString() =>
      'LabIngestResponse(success=$success, statusCode=$statusCode'
      '${errorMessage != null ? ', error=$errorMessage' : ''})';
}

/// Stateless HTTP client for platform session and metadata ingestion.
///
/// Auth model (post security rewrite):
///   Authorization: Bearer {consentToken}   — standard JWT from ConsentModule
///   + device signature headers              — defense-in-depth (optional)
///
/// HMAC signing removed — device attestation at token issuance replaces it.
class LabIngestClient {
  final String baseUrl;
  final Duration timeout;
  final int maxRetries;
  final http.Client _httpClient;

  LabIngestClient({
    this.baseUrl = ApiEndpoints.defaultLabIngestBaseUrl,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// POST a session payload to `/v1/lab/session/ingest`.
  Future<LabIngestResponse> ingestSession({
    required Map<String, dynamic> payload,
    String? consentToken,
    Map<String, String>? deviceHeaders,
  }) {
    return _post(
      path: ApiEndpoints.labSessionIngestPath,
      payload: payload,
      consentToken: consentToken,
      deviceHeaders: deviceHeaders,
    );
  }

  /// POST a metadata payload to `/v1/lab/metadata/ingest`.
  Future<LabIngestResponse> ingestMetadata({
    required Map<String, dynamic> payload,
    String? consentToken,
    Map<String, String>? deviceHeaders,
  }) {
    return _post(
      path: ApiEndpoints.labMetadataIngestPath,
      payload: payload,
      consentToken: consentToken,
      deviceHeaders: deviceHeaders,
    );
  }

  Future<LabIngestResponse> _post({
    required String path,
    required Map<String, dynamic> payload,
    String? consentToken,
    Map<String, String>? deviceHeaders,
  }) async {
    ApiEndpoints.assertConfigured(baseUrl, 'LabIngestConfig.baseUrl');
    final bodyJson = jsonEncode(payload);
    final bodyBytes = utf8.encode(bodyJson).length;
    int attempts = 0;

    while (attempts < maxRetries) {
      attempts++;
      try {
        final uri = Uri.parse('$baseUrl$path');

        final headers = <String, String>{
          'Content-Type': 'application/json',
        };

        // Bearer token from consent module (standard auth)
        if (consentToken != null && consentToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $consentToken';
        }

        // Device signature headers (defense-in-depth, optional)
        if (deviceHeaders != null) {
          headers.addAll(deviceHeaders);
        }

        final safeHeaders = headers.map(
          (k, v) => MapEntry(k, _maskHeaderValue(k, v)),
        );
        SynheartLogger.log(
          '[LabIngest] request attempt=$attempts method=POST url=$uri body_bytes=$bodyBytes',
        );
        SynheartLogger.log(
          '[LabIngest] request headers=${jsonEncode(safeHeaders)}',
        );
        SynheartLogger.log(
          '[LabIngest] request body=${_truncate(bodyJson)}',
        );

        final response = await _httpClient
            .post(uri, headers: headers, body: bodyJson)
            .timeout(timeout);

        SynheartLogger.log(
          '[LabIngest] response attempt=$attempts status=${response.statusCode}',
        );
        SynheartLogger.log(
          '[LabIngest] response body=${_truncate(response.body)}',
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          Map<String, dynamic>? responseBody;
          try {
            responseBody =
                jsonDecode(response.body) as Map<String, dynamic>;
          } catch (_) {}
          return LabIngestResponse(
            success: true,
            statusCode: response.statusCode,
            body: responseBody,
          );
        }

        // 4xx — don't retry client errors
        if (response.statusCode >= 400 && response.statusCode < 500) {
          return LabIngestResponse(
            success: false,
            statusCode: response.statusCode,
            errorMessage:
                'Client error: HTTP ${response.statusCode}',
            body: _tryParseJson(response.body),
          );
        }

        // 5xx — retry with exponential backoff
        if (attempts < maxRetries) {
          SynheartLogger.log(
            '[LabIngest] server error status=${response.statusCode}; retrying (attempt ${attempts + 1}/$maxRetries)',
          );
          await Future.delayed(Duration(seconds: 1 << attempts));
          continue;
        }

        return LabIngestResponse(
          success: false,
          statusCode: response.statusCode,
          errorMessage: 'Server error: HTTP ${response.statusCode}',
          body: _tryParseJson(response.body),
        );
      } catch (e) {
        SynheartLogger.log(
          '[LabIngest] request exception on attempt=$attempts: $e',
          error: e,
        );
        if (attempts >= maxRetries) {
          return LabIngestResponse(
            success: false,
            statusCode: 0,
            errorMessage: 'Request failed after $maxRetries attempts: $e',
          );
        }
        await Future.delayed(Duration(seconds: 1 << attempts));
      }
    }

    return const LabIngestResponse(
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

  String _maskHeaderValue(String key, String value) {
    final lower = key.toLowerCase();
    if (lower.contains('signature') ||
        lower.contains('token') ||
        lower.contains('key') ||
        lower.contains('authorization')) {
      final visible = value.length > 6 ? 6 : value.length;
      return '${value.substring(0, visible)}...REDACTED';
    }
    return value;
  }

  String _truncate(String value, {int maxChars = 3000}) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}... [truncated ${value.length - maxChars} chars]';
  }
}
