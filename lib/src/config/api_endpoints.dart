/// Central registry of all Synheart API endpoints and default base URLs.
///
/// API paths are constants — they follow the server's versioned routes.
/// Base URLs have sensible production defaults but can be overridden
/// via [CloudConfig] / [ConsentConfig].
abstract final class ApiEndpoints {
  // ── Base URLs (defaults) ──────────────────────────────────────────
  static const String defaultCloudBaseUrl = 'https://api.synheart.ai';
  static const String defaultConsentBaseUrl = 'https://consent.synheart.ai';

  // ── Cloud Ingest ──────────────────────────────────────────────────
  static const String ingestPath = '/v1/ingest/hsi';

  // ── Platform Ingest ──────────────────────────────────────────────
  static const String defaultPlatformIngestBaseUrl =
      'https://ingest-service-temp-dev.synheart.io';
  static const String platformSessionIngestPath =
      '/v1/platform/session/ingest';
  static const String platformMetadataIngestPath =
      '/v1/platform/metadata/ingest';

  // ── Consent Service ───────────────────────────────────────────────
  static String consentProfilesPath(String appId) =>
      '/api/v1/apps/$appId/consent-profiles';
  static const String consentTokenPath = '/api/v1/sdk/consent-token';
  static const String consentRevokePath = '/api/v1/sdk/consent-revoke';
}
