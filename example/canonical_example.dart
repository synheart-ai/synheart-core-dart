// ignore_for_file: avoid_print
import 'package:synheart_core/synheart_core.dart';

/// Canonical example demonstrating the full Synheart Core SDK surface.
///
/// This example covers:
/// 1. Initialization with full module configuration
/// 2. Consent management for all data types
/// 3. HSI streaming (core state representation)
/// 4. Activating optional features (Focus, Emotion)
/// 5. Feature activation/deactivation
/// 6. Error handling
/// 7. Clean shutdown
///
/// For a minimal example, see example.dart.
/// For a full Flutter app example, see lib/main.dart.
Future<void> main() async {
  // 1. Initialize SDK with all modules enabled
  //    In production, replace allowUnsignedCapabilities with
  //    capabilityToken + capabilitySecret from your server.
  try {
    await Synheart.initialize(
      userId: 'example_user_123',
      config: SynheartConfig(
        allowUnsignedCapabilities: true,
        wearConfig: WearConfig(),
        phoneConfig: PhoneConfig(),
        behaviorConfig: BehaviorConfig(),
      ),
    );
    print('[Synheart] SDK initialized');
  } on StateError catch (e) {
    print('[Synheart] Initialization failed: ${e.message}');
    return;
  }

  // 2. Grant consent for all data collection types
  await Synheart.grantConsent(
    biosignals: true,
    behavior: true,
    phoneContext: true,
    cloudUpload: false,
  );
  print('[Synheart] Consent granted for biosignals, behavior, phoneContext');

  // 3. Subscribe to HSI updates (core state representation)
  Synheart.onHSIUpdate.listen((hsi) {
    print('[HSI] v${hsi.hsiVersion} at ${hsi.observedAtUtc}');
    final affectReadings = hsi.axes?.affect?.readings ?? [];
    for (final r in affectReadings) {
      print('[HSI]   ${r.axis}: ${r.score}');
    }
  });

  // 4. Activate optional features (four-authority model)
  //    Features become operational when: Activated AND Consent AND Capability AND SessionActive
  Synheart.activate(SynheartFeature.focus);
  Synheart.onFocusUpdate.listen((focus) {
    print('[Focus] Score: ${focus.score}');
  });

  Synheart.activate(SynheartFeature.emotion);
  Synheart.onEmotionUpdate.listen((emotion) {
    print('[Emotion] Stress: ${emotion.stress}');
  });

  // 5. Start session — data collection begins, activated features become operational
  await Synheart.startSession();
  print('[Synheart] Session started');
  print('[Synheart] Active features: ${Synheart.activatedFeatures()}');

  // Run for 30 seconds as a demo
  await Future.delayed(Duration(seconds: 30));

  // 6. Features can be deactivated mid-session
  Synheart.deactivate(SynheartFeature.emotion);
  print('[Synheart] Emotion deactivated');

  // 7. Consent can be revoked mid-session — affected features stop automatically
  // await Synheart.revokeConsent('behavior');

  // 8. Clean shutdown
  await Synheart.stopSession();
  await Synheart.dispose();
  print('[Synheart] SDK disposed');
}
