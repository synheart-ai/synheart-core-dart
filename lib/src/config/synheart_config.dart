import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../modules/capabilities/capability_token.dart';
import '../modules/interfaces/auth_provider.dart';
import 'api_endpoints.dart';
import 'synheart_mode.dart';
import 'synheart_errors.dart';

String _defaultPlatformId() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    default:
      return 'flutter';
  }
}

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

  /// The app's package / bundle id, used to bind device registration to the app.
  /// Optional; leave empty if not applicable.
  final String packageName;

  /// **Development only.** Register the device even when the platform produces
  /// no attestation material (Play Integrity / App Attest unavailable — an
  /// emulator, a de-Googled ROM, a sideloaded debug build).
  ///
  /// With this `false` (the default), such a device skips registration and runs
  /// local-only. With it `true`, the runtime submits the registration with
  /// `attestation.format = "none"` and an empty blob, and the **server** decides.
  ///
  /// This is **not** a security bypass. It only stops the client giving up
  /// early. Acceptance still requires development mode on this app's record in
  /// the Synheart dashboard; with that off, registration is refused server-side.
  /// Never enable it on a production app id — use a separate development app id.
  final bool allowUnattestedDevRegistration;

  const DeviceAuthConfig({
    required this.authBaseUrl,
    this.capabilityBaseUrl,
    this.packageName = '',
    this.allowUnattestedDevRegistration = false,
  });

  String get resolvedCapabilityBaseUrl => capabilityBaseUrl ?? authBaseUrl;
}

/// Storage sub-configuration.
class StorageConfig {
  final bool enabled;
  final int? retentionDays;

  const StorageConfig({this.enabled = true, this.retentionDays});
}

/// Sync sub-configuration.
class SyncConfig {
  final bool enabled;
  final String baseUrl;

  const SyncConfig({
    this.enabled = false,
    this.baseUrl = ApiEndpoints.defaultAuthBaseUrl,
  });
}

/// Privacy sub-configuration.
class PrivacyConfig {
  final bool allowResearch;

  const PrivacyConfig({this.allowResearch = false});
}

/// Configuration for Synheart Core SDK
class SynheartConfig {
  // ── Core fields ────────────────────────────────────────────────────────

  /// Developer-provided app identifier.
  final String appId;

  /// Stable user identity. Developer-provided.
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

  /// Sync configuration.
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

  /// Server-signed capability token for feature gating.
  @Deprecated(
    'Bundle-shipped capability tokens were removed from the native runtime as '
    'a security fix; capability gating is fail-closed and driven by a verified '
    'consent JWT. This field is no longer forwarded to the runtime. Use '
    'deviceAuthConfig instead. Will be removed in 0.12.0.',
  )
  final CapabilityToken? capabilityToken;

  /// HMAC secret for verifying the capability token signature.
  @Deprecated(
    'A signing secret must never ship inside an app bundle — it is readable by '
    'anyone who downloads the app. The native runtime no longer accepts one. '
    'Use deviceAuthConfig instead. Will be removed in 0.12.0.',
  )
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
    String? platform,
    this.storage = const StorageConfig(),
    this.sync = const SyncConfig(),
    this.privacy = const PrivacyConfig(),
    this.wearConfig,
    this.phoneConfig,
    this.behaviorConfig,
    this.cloudConfig,
    this.consentConfig,
    this.deviceAuthConfig,
    // ignore: deprecated_member_use_from_same_package
    @Deprecated(
      'Not forwarded to the runtime; use deviceAuthConfig. '
      'Will be removed in 0.12.0.',
    )
    this.capabilityToken,
    // ignore: deprecated_member_use_from_same_package
    @Deprecated(
      'A signing secret must never ship in an app bundle; use '
      'deviceAuthConfig. Will be removed in 0.12.0.',
    )
    this.capabilitySecret,
    this.allowUnsignedCapabilities = false,
    this.batchIngestOnStop = false,
    this.runtimeLogEnvFilter,
  }) : platform = platform ?? _defaultPlatformId();

  /// Create default configuration
  factory SynheartConfig.defaults() {
    return SynheartConfig();
  }

  /// Validate config and throw [SynheartError] on violations.
  ///
  /// Called by [Synheart.initialize] before any native work happens, so a
  /// misconfiguration fails fast with an actionable message rather than
  /// surfacing later as an unexplained empty `org_id` on ingest rows or a
  /// device registration bound to the wrong subject.
  void validate() {
    if (mode == SynheartMode.research && !privacy.allowResearch) {
      throw SynheartError.researchNotAllowed;
    }
    if (appId.isEmpty) {
      throw const SynheartError(
        'ERR_NOT_CONFIGURED',
        'SynheartConfig.appId is empty. Set it to your application '
            'identifier — the reverse-DNS bundle/package id is a good default '
            '(e.g. appId: "com.example.my_app"), or the app id issued at '
            'platform.synheart.ai if you have one. It identifies your app on '
            'every session record and ingest row.\n'
            '  await Synheart.initialize(\n'
            '    config: SynheartConfig(appId: ..., subjectId: ...),\n'
            '  );',
      );
    }
    if (subjectId.isEmpty) {
      throw const SynheartError(
        'ERR_NOT_CONFIGURED',
        'SynheartConfig.subjectId is empty. Set it to a stable identifier for '
            'the signed-in or pseudonymous user — it must survive app '
            'restarts, or the runtime treats every launch as a new person and '
            'baselines never mature. Passing `userId:` to initialize() does '
            'NOT populate it; set it on the config.\n'
            '  await Synheart.initialize(\n'
            '    config: SynheartConfig(appId: ..., subjectId: ...),\n'
            '  );',
      );
    }
    if (subjectId.contains('|')) {
      throw SynheartError(
        'ERR_INVALID_MODE',
        'SynheartConfig.subjectId must not contain the "|" character '
            '(got: "$subjectId"). The pipe is the field separator in the '
            'runtime\'s subject-scoped storage keys, so it would corrupt the '
            'key namespace. Strip or replace it before passing the value in.',
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

  /// Forward raw 50 Hz accelerometer samples from synheart_behavior into the
  /// engine runtime so the Synheart Runtime derives motion features and
  /// the on-device motion classifier classifies posture.
  ///
  /// Independent of [enableMotionLite] — the legacy on-device classifier and
  /// the runtime classifier can run side-by-side during the Phase-3 migration.
  final bool emitRawMotionSamples;

  const BehaviorConfig({
    this.enableGestureTracking = true,
    this.enableTypingTracking = true,
    this.minIdleGapSeconds = 1.0,
    this.enableMotionLite = false,
    this.emitRawMotionSamples = false,
  });
}

/// Cloud connector configuration
class CloudConfig {
  /// Base URL for Synheart Platform
  final String baseUrl;

  /// Auth provider for request signing. The runtime signs every ingest
  /// request with the device's hardware-backed ECDSA P-256 key; this
  /// `authProvider` exposes the same surface to host code that needs to
  /// override or stub it (e.g. in tests).
  final AuthProvider? authProvider;

  /// Subject ID (pseudonymous user identifier) - becomes user_id in payload
  final String subjectId;

  /// Subject type (default: "pseudonymous_user")
  final String subjectType;

  /// Instance ID (UUID for this SDK instance)
  final String instanceId;

  /// API key for the `X-API-Key` header.
  @Deprecated(
    'An API key must never ship inside an app bundle — it is readable by '
    'anyone who downloads the app. The native runtime removed bundle-secret '
    'config (cloud.api_key) as a security fix and this value is not forwarded. '
    'Requests are signed with the hardware-backed device identity instead; see '
    'DeviceAuthConfig. Will be removed in 0.12.0.',
  )
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
    this.authProvider,
    required this.subjectId,
    required this.instanceId,
    // ignore: deprecated_member_use_from_same_package
    @Deprecated(
      'An API key must never ship in an app bundle; requests are '
      'signed with the device identity. Will be removed in 0.12.0.',
    )
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

  /// App API key for consent service authentication.
  @Deprecated(
    'An API key must never ship inside an app bundle. The native runtime '
    'removed bundle-secret config (app_api_key) as a security fix and this '
    'value is not forwarded; consent calls are signed with the device '
    'identity. Will be removed in 0.12.0.',
  )
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
    // ignore: deprecated_member_use_from_same_package
    @Deprecated(
      'An API key must never ship in an app bundle; consent calls '
      'are signed with the device identity. Will be removed in 0.12.0.',
    )
    this.appApiKey,
    this.deviceId,
    String? platform,
    this.userId,
    this.region,
  }) : platform = platform ?? _defaultPlatformId(),
       consentServiceUrl =
           (consentServiceUrl != null && consentServiceUrl.isNotEmpty)
           ? consentServiceUrl
           : ApiEndpoints.resolvedConsentBaseUrl;

  /// Check if consent service is configured
  bool get isConfigured => appId != null;
}
