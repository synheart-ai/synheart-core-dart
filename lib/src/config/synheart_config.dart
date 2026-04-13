import '../modules/capabilities/capability_token.dart';
import '../modules/interfaces/auth_provider.dart';
import 'api_endpoints.dart';
import 'synheart_mode.dart';
import 'synheart_errors.dart';

/// Device authentication configuration.
///
/// When provided, the SDK will automatically:
/// 1. Register the device via core-runtime (idempotent)
/// 3. Fetch capability tokens from the server using device-signed requests
/// 4. Use [DeviceAuthProvider] (runtime proof) for cloud/lab ingest signing
///
/// Runtime-only policy: SDK layers must not perform outbound auth API calls directly.
class DeviceAuthConfig {
  /// Base URL for the device auth service.
  final String authBaseUrl;

  /// Base URL for the capability token service.
  /// Defaults to [authBaseUrl] if not set.
  final String? capabilityBaseUrl;

  const DeviceAuthConfig({
    required this.authBaseUrl,
    this.capabilityBaseUrl,
  });

  String get resolvedCapabilityBaseUrl => capabilityBaseUrl ?? authBaseUrl;
}

/// Storage sub-configuration (RFC-CORE-0004).
class StorageConfig {
  final bool enabled;
  final int? retentionDays;

  const StorageConfig({this.enabled = true, this.retentionDays});
}

/// Sync sub-configuration (RFC-CORE-0005).
class SyncConfig {
  final bool enabled;
  final String baseUrl;

  const SyncConfig({
    this.enabled = false,
    this.baseUrl = ApiEndpoints.defaultAuthBaseUrl,
  });
}

/// Privacy sub-configuration (RFC-CORE-0003).
class PrivacyConfig {
  final bool allowResearch;

  const PrivacyConfig({this.allowResearch = false});
}

/// Configuration for Synheart Core SDK
class SynheartConfig {
  // ── RFC-CORE-0007 fields ───────────────────────────────────────────────

  /// Developer-provided app identifier.
  final String appId;

  /// Stable user identity. Server-provisioned in Phase 3; developer-provided for now.
  final String subjectId;

  /// Operational mode (default: personal).
  final SynheartMode mode;

  /// App version string (used in session records).
  final String appVersion;

  /// Human-readable app name (used in lab metadata).
  final String appName;

  /// App category (e.g. "Game", "Health", "Productivity").
  final String category;

  /// Developer name or organization.
  final String developer;

  /// Additional app-level metadata for lab ingestion.
  final Map<String, dynamic> additionalAppMetadata;

  /// Device identifier (auto-generated if not provided).
  final String deviceId;

  /// Platform string (ios | android | desktop).
  final String platform;

  /// Storage configuration.
  final StorageConfig storage;

  /// Sync configuration (Phase 3).
  final SyncConfig sync;

  /// Privacy configuration.
  final PrivacyConfig privacy;

  /// Module-specific configurations
  final WearConfig? wearConfig;
  final PhoneConfig? phoneConfig;
  final BehaviorConfig? behaviorConfig;

  /// Cloud connector configuration
  final CloudConfig? cloudConfig;

  /// Consent service configuration
  final ConsentConfig? consentConfig;

  /// Device authentication configuration.
  /// When set, enables automatic device registration, capability token
  /// fetching, and device-signed request authentication.
  final DeviceAuthConfig? deviceAuthConfig;

  /// Server-signed capability token for feature gating
  final CapabilityToken? capabilityToken;

  /// HMAC secret for verifying the capability token signature
  final String? capabilitySecret;

  /// When true, allows SDK to run with default capabilities and no signed token (debug only)
  final bool allowUnsignedCapabilities;

  /// When true, the runtime buffers wear and behavior events during the session
  /// and runs a single batch ingest (plus drain) when the session stops, instead of
  /// streaming events and ticking every second. HSI is then only produced after stop.
  final bool batchIngestOnStop;

  /// Optional `tracing` `EnvFilter` for `synheart_core_init_logging` (SDK §1b).
  /// When non-empty, overrides the bridge default filter during SDK initialization.
  final String? runtimeLogEnvFilter;

  SynheartConfig({
    this.appId = '',
    this.subjectId = '',
    this.mode = SynheartMode.personal,
    this.appVersion = '0.0.0',
    this.appName = '',
    this.category = '',
    this.developer = '',
    this.additionalAppMetadata = const {},
    this.deviceId = '',
    this.platform = 'flutter',
    this.storage = const StorageConfig(),
    this.sync = const SyncConfig(),
    this.privacy = const PrivacyConfig(),
    this.wearConfig,
    this.phoneConfig,
    this.behaviorConfig,
    this.cloudConfig,
    this.consentConfig,
    this.deviceAuthConfig,
    this.capabilityToken,
    this.capabilitySecret,
    this.allowUnsignedCapabilities = false,
    this.batchIngestOnStop = false,
    this.runtimeLogEnvFilter,
  });

  /// Create default configuration
  factory SynheartConfig.defaults() {
    return SynheartConfig();
  }

  /// Validate config and throw [SynheartError] on violations.
  void validate() {
    if (mode == SynheartMode.research && !privacy.allowResearch) {
      throw SynheartError.researchNotAllowed;
    }
    if (appId.isEmpty) {
      throw const SynheartError(
        'ERR_NOT_CONFIGURED',
        'appId must not be empty',
      );
    }
    if (subjectId.isEmpty) {
      throw const SynheartError(
        'ERR_NOT_CONFIGURED',
        'subjectId must not be empty',
      );
    }
    if (subjectId.contains('|')) {
      throw const SynheartError(
        'ERR_INVALID_MODE',
        'subjectId must not contain pipe character',
      );
    }
  }
}

/// Wear module configuration
class WearConfig {
  /// Enable high-frequency HRV sampling (requires extended capability)
  final bool enableHighFrequencyHrv;

  /// Enable offline caching
  final bool enableCaching;

  /// Sample rate in Hz
  final double sampleRateHz;

  const WearConfig({
    this.enableHighFrequencyHrv = false,
    this.enableCaching = true,
    this.sampleRateHz = 1.0,
  });
}

/// Phone module configuration
class PhoneConfig {
  /// Enable motion tracking
  final bool enableMotion;

  /// Enable screen state tracking
  final bool enableScreenState;

  /// Enable app switching tracking (hashed)
  final bool enableAppTracking;

  /// Motion sensitivity (0.0 - 1.0)
  final double motionSensitivity;

  const PhoneConfig({
    this.enableMotion = true,
    this.enableScreenState = true,
    this.enableAppTracking = false,
    this.motionSensitivity = 0.5,
  });
}

/// Behavior module configuration
class BehaviorConfig {
  /// Enable gesture tracking
  final bool enableGestureTracking;

  /// Enable typing pattern tracking
  final bool enableTypingTracking;

  /// Minimum idle gap to record (in seconds)
  final double minIdleGapSeconds;

  /// Enable on-device motion-state inference in synheart_behavior.
  ///
  /// When enabled, the behavior pipeline uses high-rate motion sensors and
  /// the embedded model to infer `motion_state`.
  final bool enableMotionLite;

  const BehaviorConfig({
    this.enableGestureTracking = true,
    this.enableTypingTracking = true,
    this.minIdleGapSeconds = 1.0,
    this.enableMotionLite = false,
  });
}

/// Cloud connector configuration
class CloudConfig {
  /// Base URL for Synheart Platform
  final String baseUrl;

  /// Tenant ID (from app registration)
  final String tenantId;

  /// HMAC secret for signing requests (nullable when authProvider is used)
  final String? hmacSecret;

  /// Custom auth provider for request signing (e.g., ECDSA device-identity).
  /// When set, takes precedence over the HMAC path.
  final AuthProvider? authProvider;

  /// Subject ID (pseudonymous user identifier) - becomes user_id in payload
  final String subjectId;

  /// Subject type (default: "pseudonymous_user")
  final String subjectType;

  /// Instance ID (UUID for this SDK instance)
  final String instanceId;

  /// API Key for X-API-Key header (nullable when authProvider is used)
  final String? apiKey;

  /// Organization ID (optional) - for metadata.org_id
  final String? orgId;

  /// Max upload queue size (default: 100)
  final int maxQueueSize;

  /// Batch size for uploads
  final int batchSize;

  /// Upload interval (minimum time between uploads)
  final Duration uploadInterval;

  /// Max retry attempts
  final int maxRetries;

  /// Enable offline backlog
  final bool enableBacklog;

  CloudConfig({
    required this.tenantId,
    this.hmacSecret,
    this.authProvider,
    required this.subjectId,
    required this.instanceId,
    this.apiKey,
    this.orgId,
    this.baseUrl = ApiEndpoints.defaultCloudBaseUrl,
    this.subjectType = 'pseudonymous_user',
    this.maxQueueSize = 100,
    this.batchSize = 10,
    this.uploadInterval = const Duration(minutes: 5),
    this.maxRetries = 3,
    this.enableBacklog = true,
  });
}

/// Consent service configuration
class ConsentConfig {
  /// Base URL for consent service
  final String consentServiceUrl;

  /// App ID for consent service
  final String? appId;

  /// App API key for consent service authentication
  final String? appApiKey;

  /// Device ID (UUID for this device, auto-generated if not provided)
  final String? deviceId;

  /// Platform identifier ('ios', 'android', 'flutter')
  final String platform;

  /// User ID (optional, for pseudonymous identification)
  final String? userId;

  /// Region code (e.g., 'US', 'EU')
  final String? region;

  ConsentConfig({
    String? consentServiceUrl,
    this.appId,
    this.appApiKey,
    this.deviceId,
    this.platform = 'flutter',
    this.userId,
    this.region,
  }) : consentServiceUrl = (consentServiceUrl != null && consentServiceUrl.isNotEmpty)
           ? consentServiceUrl
           : ApiEndpoints.resolvedConsentBaseUrl;

  /// Check if consent service is configured
  bool get isConfigured => appId != null;
}
