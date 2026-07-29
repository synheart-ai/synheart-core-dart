// ignore_for_file: avoid_print
import 'package:synheart_core/synheart_core.dart';

/// Canonical example demonstrating the full Synheart Core SDK surface.
///
/// This example covers:
/// 1. Configuration with SynheartConfig
/// 2. Consent management for all data types
/// 3. Typed state streaming via onStateUpdate
/// 4. Start session and preprocessed diagnostics
/// 5. Sync API
/// 6. Error handling and clean shutdown
///
/// For a full Flutter app example, see lib/main.dart.
Future<void> main() async {
  // 1. Configure SDK with all modules enabled
  //    In production, replace allowUnsignedCapabilities with
  //    capabilityToken + capabilitySecret from your server.
  try {
    await Synheart.initialize(
      config: SynheartConfig(
        appId: 'ai.synheart.example',
        subjectId: 'example_user_123',
        allowUnsignedCapabilities: true,
        wearConfig: const WearConfig(),
        phoneConfig: const PhoneConfig(),
        behaviorConfig: const BehaviorConfig(),
      ),
    );
    print('[Synheart] SDK configured');
  } on SynheartError catch (e) {
    print('[Synheart] Configuration failed: ${e.code}: ${e.message}');
    return;
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

  // 3. Subscribe to typed state updates
  Synheart.onStateUpdate.listen((state) {
    print('[State] $state');
  });

  // 4. Start session — data collection begins, activated features become operational
  await Synheart.startSession();
  print('[Synheart] Session started');
  print('[Synheart] Active features: ${Synheart.activatedFeatures()}');

  // Run for 30 seconds as a demo
  await Future.delayed(Duration(seconds: 30));

  // 5. Sync is optional. Enable SyncConfig and cloud consent before calling
  // Synheart.syncNow(); this local example intentionally stays on-device.

  // 6. Consent can be revoked mid-session — affected features stop automatically
  // await Synheart.revokeConsentType('behavior');

  // 7. Clean shutdown
  await Synheart.stopSession();
  await Synheart.dispose();
  print('[Synheart] SDK disposed');
}
