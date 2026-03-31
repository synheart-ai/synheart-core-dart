import 'api_endpoints.dart';
import '../modules/interfaces/auth_provider.dart';

/// Configuration for the Platform Ingest module.
///
/// Used to send custom session and metadata payloads to the
/// Synheart lab ingestion service.
class LabIngestConfig {
  /// Base URL for the lab ingestion service.
  /// Resolved from SYNHEART_BASE_URL + /platform/v1 if not set explicitly.
  final String baseUrl;

  /// API key for authentication (X-API-Key header).
  /// Optional when device auth is configured (DeviceAuthProvider signs requests).
  final String? apiKey;

  /// HMAC secret for request signing.
  /// Optional when device auth is configured (DeviceAuthProvider signs requests).
  final String? hmacSecret;

  /// Custom auth provider for request signing (e.g., ECDSA device-identity).
  /// When set, takes precedence over HMAC signing.
  final AuthProvider? authProvider;

  /// HTTP request timeout.
  final Duration timeout;

  /// Maximum retry attempts for failed requests.
  final int maxRetries;

  /// When true, automatically build and ingest a session payload after
  /// [Synheart.stopSession]. Defaults to false (manual ingestion).
  final bool autoIngest;

  LabIngestConfig({
    String? baseUrl,
    this.apiKey,
    this.hmacSecret,
    this.authProvider,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.autoIngest = false,
  }) : baseUrl = (baseUrl != null && baseUrl.isNotEmpty)
           ? baseUrl
           : ApiEndpoints.resolvedLabIngestBaseUrl;
}
