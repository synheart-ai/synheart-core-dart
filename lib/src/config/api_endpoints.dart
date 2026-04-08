/// Central registry of all Synheart API endpoints and default base URLs.
///
/// 3 services behind the API gateway:
///   api.synheart.ai/auth/v1/...     — auth, device attestation, account
///   api.synheart.ai/consent/v1/...  — consent profiles, tokens
///   api.synheart.ai/ingest/v1/...   — HSI, platform/lab, wear, SWIP
///
/// Dev gateway: api-dev.synheart.io (same paths)
abstract final class ApiEndpoints {
  // ── Base URL ────────────────────────────────────────────────────────
  static const String defaultBaseUrl = String.fromEnvironment(
    'SYNHEART_BASE_URL',
    defaultValue: 'https://api.synheart.ai',
  );

  // ── Gateway prefixes (3 services) ─────────────────────────────────
  static const String _authGateway = '/auth';
  static const String _consentGateway = '/consent';
  static const String _ingestGateway = '/ingest';

  // ── Per-service base URL overrides (optional, for legacy/dev) ─────
  static const String _authOverride = String.fromEnvironment(
    'SYNHEART_AUTH_BASE_URL', defaultValue: '',
  );
  static const String _consentOverride = String.fromEnvironment(
    'SYNHEART_CONSENT_BASE_URL', defaultValue: '',
  );
  static const String _ingestOverride = String.fromEnvironment(
    'SYNHEART_INGEST_BASE_URL', defaultValue: '',
  );

  // ── Compile-time const aliases (for default parameter values) ────
  // These read from dart-defines and are used where a const is required.
  // For runtime resolution (with fallback to BASE_URL), use the resolved* getters.
  static const String defaultAuthBaseUrl = _authOverride;
  static const String defaultConsentBaseUrl = _consentOverride;
  static const String defaultIngestBaseUrl = _ingestOverride;
  static const String defaultCloudBaseUrl = _ingestOverride;
  static const String defaultLabIngestBaseUrl = _ingestOverride;

  // ── Resolved base URLs ────────────────────────────────────────────
  static String _resolve(String override, String gatewayPrefix) {
    if (override.isNotEmpty) return override;
    return '$defaultBaseUrl$gatewayPrefix';
  }

  /// Auth: api.synheart.ai/auth
  static String get resolvedAuthBaseUrl =>
      _resolve(_authOverride, _authGateway);

  /// Consent: api.synheart.ai/consent
  static String get resolvedConsentBaseUrl =>
      _resolve(_consentOverride, _consentGateway);

  /// Ingest (HSI + platform + wear): api.synheart.ai/ingest
  static String get resolvedIngestBaseUrl =>
      _resolve(_ingestOverride, _ingestGateway);

  // Cloud and lab ingest both go to the ingest service
  static String get resolvedCloudBaseUrl => resolvedIngestBaseUrl;
  static String get resolvedLabIngestBaseUrl => resolvedIngestBaseUrl;

  // ── Ingest service paths ──────────────────────────────────────────
  static const String ingestPath = '/v1/hsi/ingest';
  static const String labSessionIngestPath = '/v1/lab/session/ingest';
  static const String labMetadataIngestPath = '/v1/lab/metadata/ingest';

  // ── Auth service paths ────────────────────────────────────────────
  static const String deviceCapabilitiesPath = '/v1/device/capabilities';
  static const String accountDeletePath = '/v1/delete';
  static const String accountDeleteCancelPath = '/v1/delete/cancel';

  // ── Consent service paths ─────────────────────────────────────────
  static String consentProfilesPath(String appId) =>
      '/v1/apps/$appId/consent-profiles';
  static const String consentTokenPath = '/v1/sdk/consent-token';
  static const String consentRevokePath = '/v1/sdk/consent-revoke';

  /// Throws [ArgumentError] if [url] is still the placeholder value.
  static void assertConfigured(String url, String name) {
    if (url.isEmpty) {
      throw ArgumentError(
        '$name is not configured. '
        'Set SYNHEART_BASE_URL via --dart-define or --dart-define-from-file.',
      );
    }
  }
}
