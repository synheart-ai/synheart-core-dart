import '../modules/capabilities/capability_token.dart';
import '../modules/interfaces/auth_provider.dart';

/// Configuration for Synheart Core SDK
class SynheartConfig {
  /// Enable cloud sync (HSI snapshots only, no raw data)
  final bool enableCloudSync;

  /// Enable Syni hooks for LLM conditioning
  final bool enableSyniHooks;

  /// HSI update interval (default: 30 seconds)
  final Duration updateInterval;

  /// Log level for SDK logs
  final LogLevel logLevel;

  /// Module-specific configurations
  final WearConfig? wearConfig;
  final PhoneConfig? phoneConfig;
  final BehaviorConfig? behaviorConfig;

  /// Cloud connector configuration
  final CloudConfig? cloudConfig;

  /// Consent service configuration
  final ConsentConfig? consentConfig;

  /// Server-signed capability token for feature gating
  final CapabilityToken? capabilityToken;

  /// HMAC secret for verifying the capability token signature
  final String? capabilitySecret;

  /// When true, allows SDK to run with default capabilities and no signed token (debug only)
  final bool allowUnsignedCapabilities;

  const SynheartConfig({
    this.enableCloudSync = false,
    this.enableSyniHooks = false,
    this.updateInterval = const Duration(seconds: 30),
    this.logLevel = LogLevel.info,
    this.wearConfig,
    this.phoneConfig,
    this.behaviorConfig,
    this.cloudConfig,
    this.consentConfig,
    this.capabilityToken,
    this.capabilitySecret,
    this.allowUnsignedCapabilities = false,
  });

  /// Create default configuration
  factory SynheartConfig.defaults() {
    return const SynheartConfig();
  }
}

/// Log level for SDK logging
enum LogLevel { debug, info, warn, error }

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

  const BehaviorConfig({
    this.enableGestureTracking = true,
    this.enableTypingTracking = true,
    this.minIdleGapSeconds = 1.0,
  });
}

/// Cloud connector configuration
class CloudConfig {
  /// Base URL for Synheart Platform
  final String baseUrl;

  /// Tenant ID (from app registration) - kept for backward compatibility
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
    this.baseUrl = 'https://api.synheart.com',
    this.subjectType = 'pseudonymous_user',
    this.maxQueueSize = 100,
    this.batchSize = 10,
    this.uploadInterval = const Duration(minutes: 5),
    this.maxRetries = 3,
    this.enableBacklog = true,
  }) : assert(
         hmacSecret != null || authProvider != null,
         'CloudConfig requires either hmacSecret or authProvider',
       );
}

/// Consent service configuration
class ConsentConfig {
  /// Base URL for consent service (defaults to dev environment)
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

  const ConsentConfig({
    this.consentServiceUrl = 'https://consent-service-dev.synheart.io',
    this.appId,
    this.appApiKey,
    this.deviceId,
    this.platform = 'flutter',
    this.userId,
    this.region,
  });

  /// Check if consent service is configured
  bool get isConfigured => appId != null && appApiKey != null;
}
