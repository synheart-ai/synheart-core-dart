import 'api_endpoints.dart';

/// Configuration for the Platform Ingest module.
///
/// Used to send custom session and metadata payloads to the
/// Synheart platform ingestion service.
class PlatformIngestConfig {
  /// Base URL for the platform ingestion service.
  final String baseUrl;

  /// API key for authentication (X-API-Key header).
  final String apiKey;

  /// HMAC secret for request signing.
  final String hmacSecret;

  /// HTTP request timeout.
  final Duration timeout;

  /// Maximum retry attempts for failed requests.
  final int maxRetries;

  /// When true, automatically build and ingest a session payload after
  /// [Synheart.stopSession]. Defaults to false (manual ingestion).
  final bool autoIngest;

  const PlatformIngestConfig({
    this.baseUrl = ApiEndpoints.defaultPlatformIngestBaseUrl,
    required this.apiKey,
    required this.hmacSecret,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.autoIngest = false,
  });
}
