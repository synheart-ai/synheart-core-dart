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
  static const String ingestPath = '/ingest/v1/hsi';

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
      '/platform/v1/session/ingest';
  static const String platformMetadataIngestPath =
      '/platform/v1/metadata/ingest';

  // ── Device Capabilities ─────────────────────────────────────────
  /// Path for fetching device capability tokens (device-signed).
  static const String deviceCapabilitiesPath = '/account/v1/device/capabilities';

  // ── Auth / Account ────────────────────────────────────────────────
  static const String authExchangePath = '/auth/v1/exchange';
  static const String authRefreshPath = '/auth/v1/refresh';
  static const String accountDeletePath = '/account/v1/delete';
  static const String accountDeleteCancelPath = '/account/v1/delete/cancel';

  // ── Consent Service ───────────────────────────────────────────────
  static String consentProfilesPath(String appId) =>
      '/consent/v1/apps/$appId/consent-profiles';
  static const String consentTokenPath = '/consent/v1/sdk/consent-token';
  static const String consentRevokePath = '/consent/v1/sdk/consent-revoke';

  /// Throws [ArgumentError] if [url] is still the placeholder value.
  /// Call at module init to fail fast instead of silent 404s at runtime.
  static void assertConfigured(String url, String name) {
    if (url == 'https://example.invalid' || url.isEmpty) {
      throw ArgumentError(
        '$name is not configured. '
        'Set it via --dart-define or --dart-define-from-file. '
        'See README for details.',
      );
    }
  }
}
