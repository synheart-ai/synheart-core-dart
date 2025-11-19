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

  const SynheartConfig({
    this.enableCloudSync = false,
    this.enableSyniHooks = false,
    this.updateInterval = const Duration(seconds: 30),
    this.logLevel = LogLevel.info,
    this.wearConfig,
    this.phoneConfig,
    this.behaviorConfig,
    this.cloudConfig,
  });

  /// Create default configuration
  factory SynheartConfig.defaults() {
    return const SynheartConfig();
  }
}

/// Log level for SDK logging
enum LogLevel {
  debug,
  info,
  warn,
  error,
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

  const BehaviorConfig({
    this.enableGestureTracking = true,
    this.enableTypingTracking = true,
    this.minIdleGapSeconds = 1.0,
  });
}

/// Cloud connector configuration
class CloudConfig {
  /// Base URL for cloud API
  final String baseUrl;

  /// Batch size for uploads
  final int batchSize;

  /// Upload interval (minimum time between uploads)
  final Duration uploadInterval;

  /// Max retry attempts
  final int maxRetries;

  /// Enable offline backlog
  final bool enableBacklog;

  const CloudConfig({
    this.baseUrl = 'https://api.synheart.com',
    this.batchSize = 10,
    this.uploadInterval = const Duration(minutes: 5),
    this.maxRetries = 3,
    this.enableBacklog = true,
  });
}
