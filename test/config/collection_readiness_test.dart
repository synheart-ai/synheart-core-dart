import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/config/activation_manager.dart';
import 'package:synheart_core/src/config/synheart_config.dart';
import 'package:synheart_core/src/config/synheart_feature.dart';
import 'package:synheart_core/src/modules/consent/consent_effective_state.dart';

/// A session needs BOTH halves of a pair: the feature enabled in
/// `SynheartConfig`, AND its matching consent granted.
///
/// Checking consent alone lets a mismatched setup through — wear enabled while
/// only behavior is consented means wear is activated but not permitted, and
/// behavior is permitted but not activated. Nothing collects, yet the session
/// starts and reports `collecting`.
///
/// This exercises the pairing rule `Synheart._hasAtLeastOneCollectionConsent`
/// implements, over the same `ActivationManager` the SDK uses.
void main() {
  /// The features that actually acquire sensor data. Mirrors
  /// `Synheart._collectionFeatures` — cloud / synsync / syni are excluded
  /// because they govern what happens to data, not whether any is gathered.
  const collectionFeatures = [
    SynheartFeature.wear,
    SynheartFeature.behavior,
    SynheartFeature.phoneContext,
  ];

  ConsentEffectiveState consent({
    bool biosignals = false,
    bool behavior = false,
    bool phoneContext = false,
    bool cloudUpload = false,
    bool vendorSync = false,
    bool research = false,
    bool syni = false,
  }) => ConsentEffectiveState(
    biosignals: biosignals,
    phoneContext: phoneContext,
    behavior: behavior,
    cloudUpload: cloudUpload,
    syni: syni,
    vendorSync: vendorSync,
    research: research,
    timestampMs: 0,
    version: '1.0.0',
  );

  bool consentFor(ConsentEffectiveState c, SynheartFeature f) => switch (f) {
    SynheartFeature.wear => c.biosignals,
    SynheartFeature.behavior => c.behavior,
    SynheartFeature.phoneContext => c.phoneContext,
    _ => false,
  };

  bool canCollect(ActivationManager a, ConsentEffectiveState c) =>
      collectionFeatures.any((f) => a.isActivated(f) && consentFor(c, f));

  ActivationManager managerFor(SynheartConfig config) =>
      ActivationManager()..activateFromConfig(config);

  group('mismatched feature and consent', () {
    test('wear enabled, only behavior consented — rejected', () {
      // The case the review named. Neither side of a pair is satisfied.
      final a = managerFor(SynheartConfig(wearConfig: const WearConfig()));
      expect(canCollect(a, consent(behavior: true)), isFalse);
    });

    test('behavior enabled, only biosignals consented — rejected', () {
      final a = managerFor(
        SynheartConfig(behaviorConfig: const BehaviorConfig()),
      );
      expect(canCollect(a, consent(biosignals: true)), isFalse);
    });

    test('phone enabled, only behavior consented — rejected', () {
      final a = managerFor(SynheartConfig(phoneConfig: const PhoneConfig()));
      expect(canCollect(a, consent(behavior: true)), isFalse);
    });
  });

  group('matched pairs', () {
    test('wear enabled and biosignals consented — allowed', () {
      final a = managerFor(SynheartConfig(wearConfig: const WearConfig()));
      expect(canCollect(a, consent(biosignals: true)), isTrue);
    });

    test('one matching pair is enough among several enabled features', () {
      final a = managerFor(
        SynheartConfig(
          wearConfig: const WearConfig(),
          phoneConfig: const PhoneConfig(),
          behaviorConfig: const BehaviorConfig(),
        ),
      );
      expect(canCollect(a, consent(phoneContext: true)), isTrue);
    });
  });

  group('non-collection consents never qualify', () {
    test('cloud, vendor sync, research and syni alone are rejected', () {
      // These govern what happens to data once gathered; none makes a sensor
      // readable, so a session granted only these would collect nothing.
      final a = managerFor(
        SynheartConfig(
          wearConfig: const WearConfig(),
          behaviorConfig: const BehaviorConfig(),
          phoneConfig: const PhoneConfig(),
        ),
      );
      expect(
        canCollect(
          a,
          consent(
            cloudUpload: true,
            vendorSync: true,
            research: true,
            syni: true,
          ),
        ),
        isFalse,
      );
    });

    test('cloudConfig alone does not enable collection', () {
      final a = managerFor(
        SynheartConfig(
          cloudConfig: CloudConfig(subjectId: 's', instanceId: 'i'),
        ),
      );
      expect(a.isActivated(SynheartFeature.cloud), isTrue);
      expect(canCollect(a, consent(biosignals: true)), isFalse);
    });
  });

  group('empty configurations', () {
    test('nothing enabled is rejected even with full consent', () {
      final a = managerFor(SynheartConfig());
      expect(
        canCollect(
          a,
          consent(biosignals: true, behavior: true, phoneContext: true),
        ),
        isFalse,
      );
    });

    test('everything enabled with no consent is rejected', () {
      final a = managerFor(
        SynheartConfig(
          wearConfig: const WearConfig(),
          behaviorConfig: const BehaviorConfig(),
          phoneConfig: const PhoneConfig(),
        ),
      );
      expect(canCollect(a, consent()), isFalse);
    });
  });
}
