import '../interfaces/feature_providers.dart';

/// Collected features from all modules
class CollectedFeatures {
  final WearWindowFeatures? wear;
  final PhoneWindowFeatures? phone;
  final BehaviorWindowFeatures? behavior;

  const CollectedFeatures({
    this.wear,
    this.phone,
    this.behavior,
  });

  /// Check if we have any features
  bool get hasAnyFeatures => wear != null || phone != null || behavior != null;
}

/// Collects features from all data modules
class ChannelCollector {
  final WearFeatureProvider? _wear;
  final PhoneFeatureProvider? _phone;
  final BehaviorFeatureProvider? _behavior;

  ChannelCollector({
    WearFeatureProvider? wear,
    PhoneFeatureProvider? phone,
    BehaviorFeatureProvider? behavior,
  })  : _wear = wear,
        _phone = phone,
        _behavior = behavior;

  /// Collect features for a specific window
  CollectedFeatures collect(WindowType window) {
    return CollectedFeatures(
      wear: _wear?.features(window),
      phone: _phone?.features(window),
      behavior: _behavior?.features(window),
    );
  }
}
