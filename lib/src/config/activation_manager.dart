import 'synheart_config.dart';
import 'synheart_feature.dart';

/// Internal manager that tracks which features the developer has activated.
///
/// Part of the four-authority activation model:
/// ```
/// FeatureOperational = Activation AND Consent AND Capability AND SessionActive
/// ```
///
/// This class manages the **Activation** authority — the developer's explicit
/// intent to use a feature.
class ActivationManager {
  final Set<SynheartFeature> _activated = {};

  /// Activate a feature (add to set).
  void activate(SynheartFeature feature) {
    _activated.add(feature);
  }

  /// Deactivate a feature (remove from set).
  void deactivate(SynheartFeature feature) {
    _activated.remove(feature);
  }

  /// Check if a feature is activated.
  bool isActivated(SynheartFeature feature) {
    return _activated.contains(feature);
  }

  /// Return a copy of all activated features.
  Set<SynheartFeature> activatedFeatures() {
    return Set.unmodifiable(_activated);
  }

  /// Bulk-activate features based on [SynheartConfig] flags.
  ///
  /// Maps config presence to the corresponding feature activations:
  /// - `wearConfig != null` -> `SynheartFeature.wear`
  /// - `phoneConfig != null` -> `SynheartFeature.phoneContext`
  /// - `behaviorConfig != null` -> `SynheartFeature.behavior`
  /// - `cloudConfig != null` -> `SynheartFeature.cloud`
  void activateFromConfig(SynheartConfig config) {
    if (config.wearConfig != null) _activated.add(SynheartFeature.wear);
    if (config.phoneConfig != null)
      _activated.add(SynheartFeature.phoneContext);
    if (config.behaviorConfig != null) _activated.add(SynheartFeature.behavior);
    if (config.cloudConfig != null) _activated.add(SynheartFeature.cloud);
  }
}
