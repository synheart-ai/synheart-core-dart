/// Capability levels for module features
enum CapabilityLevel {
  /// No access
  none,

  /// Core features only
  core,

  /// Extended features
  extended,

  /// Research-level features (internal only)
  research,
}

/// Module identifiers
enum Module { wear, phone, behavior, hsi, cloud }

/// Feature flags for fine-grained control
enum FeatureFlag {
  // Wear features
  wearDerivedMetrics,
  wearHighFrequencyHrv,
  wearRawRrIntervals,

  // Phone features
  phoneMotionAndScreen,
  phoneHashedAppSwitching,
  phoneDetailedAppContext,
  phoneRawNotificationStructure,

  // Behavior features
  behaviorBasicMetrics,
  behaviorExtendedPatterns,
  behaviorFullTimingStream,

  // HSI features
  hsiEmotionFocus,
  hsiFullEmbedding,
  hsiFusionVectorAccess,

  // Cloud features
  cloudBasicIngest,
  cloudExtendedEndpoints,
  cloudResearchEndpoints,
}

/// Provider interface for capability checking
abstract class CapabilityProvider {
  /// Get the capability level for a specific module
  CapabilityLevel capability(Module module);

  /// Check if a specific feature is enabled
  bool isFeatureEnabled(FeatureFlag feature);

  /// Check if a module can access a specific feature
  bool canAccessFeature(String moduleId, String featureId);

  /// Get all capabilities as a map
  Map<Module, CapabilityLevel> getAllCapabilities();
}
