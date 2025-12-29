import 'package:rxdart/rxdart.dart';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import 'capability_token.dart';
import 'capability_verifier.dart';

/// Capabilities Module
///
/// Manages SDK capabilities based on authentication tokens.
/// Determines which features each module can use based on capability tiers.
class CapabilityModule extends BaseSynheartModule
    implements CapabilityProvider {
  @override
  String get moduleId => 'capabilities';

  SDKCapabilities? _capabilities;
  CapabilityToken? _token;
  final CapabilityVerifier _verifier = CapabilityVerifier();
  final BehaviorSubject<SDKCapabilities?> _capabilitiesStream =
      BehaviorSubject<SDKCapabilities?>();

  /// Stream of capability updates
  Stream<SDKCapabilities?> get capabilitiesStream => _capabilitiesStream.stream;

  /// The last successfully verified token (if any)
  CapabilityToken? get token => _token;

  /// Load capabilities from token
  Future<void> loadFromToken(CapabilityToken token, String secret) async {
    if (!_verifier.isValid(token, secret)) {
      throw CapabilityException('Invalid capability token');
    }

    _token = token;
    _capabilities = _verifier.parse(token);
    _capabilitiesStream.add(_capabilities);
  }

  /// Load default capabilities (for development/testing)
  Future<void> loadDefaults() async {
    _capabilities = SDKCapabilities.defaultCapabilities();
    _capabilitiesStream.add(_capabilities);
  }

  @override
  CapabilityLevel capability(Module module) {
    if (_capabilities == null) {
      return CapabilityLevel.none;
    }
    return _capabilities!.getLevel(module);
  }

  @override
  bool isFeatureEnabled(FeatureFlag feature) {
    if (_capabilities == null) {
      return false;
    }

    return _isFeatureEnabled(feature, _capabilities!);
  }

  @override
  bool canAccessFeature(String moduleId, String featureId) {
    // TODO: Implement fine-grained feature access control
    return true;
  }

  @override
  Map<Module, CapabilityLevel> getAllCapabilities() {
    if (_capabilities == null) {
      return {};
    }

    return {
      Module.behavior: _capabilities!.behavior,
      Module.wear: _capabilities!.wear,
      Module.phone: _capabilities!.phone,
      Module.hsi: _capabilities!.hsi,
      Module.cloud: _capabilities!.cloud,
    };
  }

  /// Check if a feature is enabled based on capability levels
  bool _isFeatureEnabled(FeatureFlag feature, SDKCapabilities capabilities) {
    switch (feature) {
      // Wear features
      case FeatureFlag.wearDerivedMetrics:
        return capabilities.wear.index >= CapabilityLevel.core.index;
      case FeatureFlag.wearHighFrequencyHrv:
        return capabilities.wear.index >= CapabilityLevel.extended.index;
      case FeatureFlag.wearRawRrIntervals:
        return capabilities.wear.index >= CapabilityLevel.research.index;

      // Phone features
      case FeatureFlag.phoneMotionAndScreen:
        return capabilities.phone.index >= CapabilityLevel.core.index;
      case FeatureFlag.phoneHashedAppSwitching:
        return capabilities.phone.index >= CapabilityLevel.core.index;
      case FeatureFlag.phoneDetailedAppContext:
        return capabilities.phone.index >= CapabilityLevel.extended.index;
      case FeatureFlag.phoneRawNotificationStructure:
        return capabilities.phone.index >= CapabilityLevel.extended.index;

      // Behavior features
      case FeatureFlag.behaviorBasicMetrics:
        return capabilities.behavior.index >= CapabilityLevel.core.index;
      case FeatureFlag.behaviorExtendedPatterns:
        return capabilities.behavior.index >= CapabilityLevel.extended.index;
      case FeatureFlag.behaviorFullTimingStream:
        return capabilities.behavior.index >= CapabilityLevel.research.index;

      // HSI features
      case FeatureFlag.hsiEmotionFocus:
        return capabilities.hsi.index >= CapabilityLevel.core.index;
      case FeatureFlag.hsiFullEmbedding:
        return capabilities.hsi.index >= CapabilityLevel.extended.index;
      case FeatureFlag.hsiFusionVectorAccess:
        return capabilities.hsi.index >= CapabilityLevel.research.index;

      // Cloud features
      case FeatureFlag.cloudBasicIngest:
        return capabilities.cloud.index >= CapabilityLevel.core.index;
      case FeatureFlag.cloudExtendedEndpoints:
        return capabilities.cloud.index >= CapabilityLevel.extended.index;
      case FeatureFlag.cloudResearchEndpoints:
        return capabilities.cloud.index >= CapabilityLevel.research.index;
    }
  }

  @override
  Future<void> onInitialize() async {
    // Nothing to initialize
  }

  @override
  Future<void> onStart() async {
    // Nothing to start
  }

  @override
  Future<void> onStop() async {
    // Nothing to stop
  }

  @override
  Future<void> onDispose() async {
    await _capabilitiesStream.close();
    _capabilities = null;
    _token = null;
  }
}
