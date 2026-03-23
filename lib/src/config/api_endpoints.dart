/// Central registry of all Synheart API endpoints and default base URLs.
///
/// API paths are constants — they follow the server's versioned routes.
/// Base URLs have sensible production defaults but can be overridden
/// via [CloudConfig] / [ConsentConfig].
abstract final class ApiEndpoints {
  // ── Base URLs (defaults) ──────────────────────────────────────────
  /// Cloud ingest base URL.
  ///
  /// Configure with `--dart-define SYNHEART_CLOUD_BASE_URL=...`
  /// or `--dart-define-from-file` to avoid committing real endpoints.
  static const String defaultCloudBaseUrl = String.fromEnvironment(
    'SYNHEART_CLOUD_BASE_URL',
    defaultValue: 'https://example.invalid',
  );

  /// Consent service base URL.
  ///
  /// Configure with `--dart-define SYNHEART_CONSENT_BASE_URL=...`.
  static const String defaultConsentBaseUrl = String.fromEnvironment(
    'SYNHEART_CONSENT_BASE_URL',
    defaultValue: 'https://example.invalid',
  );

  // ── Cloud Ingest ──────────────────────────────────────────────────
  /// HSI ingest path (v1).
  static const String ingestPath = '/v1/hsi/ingest';

  // ── Platform Ingest ──────────────────────────────────────────────
  /// Platform ingest base URL.
  ///
  /// Configure with `--dart-define SYNHEART_PLATFORM_INGEST_BASE_URL=...`.
  static const String defaultPlatformIngestBaseUrl = String.fromEnvironment(
    'SYNHEART_PLATFORM_INGEST_BASE_URL',
    defaultValue: 'https://example.invalid',
  );

  /// Default auth/account API base URL.
  ///
  /// Configure with `--dart-define SYNHEART_AUTH_BASE_URL=...`.
  static const String defaultAuthBaseUrl = String.fromEnvironment(
    'SYNHEART_AUTH_BASE_URL',
    defaultValue: 'https://example.invalid',
  );

  static const String platformSessionIngestPath =
      '/v1/platform/session/ingest';
  static const String platformMetadataIngestPath =
      '/v1/platform/metadata/ingest';

  // ── Auth / Account ────────────────────────────────────────────────
  static const String authExchangePath = '/v1/auth/exchange';
  static const String authRefreshPath = '/v1/auth/refresh';
  static const String accountDeletePath = '/v1/account/delete';
  static const String accountDeleteCancelPath = '/v1/account/delete/cancel';

  // ── Consent Service ───────────────────────────────────────────────
  static String consentProfilesPath(String appId) =>
      '/api/v1/apps/$appId/consent-profiles';
  static const String consentTokenPath = '/api/v1/sdk/consent-token';
  static const String consentRevokePath = '/api/v1/sdk/consent-revoke';
}
