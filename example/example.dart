// ignore_for_file: avoid_print
import 'package:synheart_core/synheart_core.dart';

/// Simple example demonstrating minimal Synheart Core SDK usage.
///
/// The absolute minimum to get HSI data flowing.
/// For a full-featured example, see the Flutter app in example/lib/main.dart.
Future<void> main() async {
  // Initialize with wearable data collection
  await Synheart.initialize(
    userId: 'user_123',
    config: SynheartConfig(
      allowUnsignedCapabilities: true,
      wearConfig: WearConfig(),
    ),
  );

  // Grant consent for biosignal collection
  await Synheart.grantConsent(
    biosignals: true,
    behavior: false,
    phoneContext: false,
    cloudUpload: false,
  );

  // Subscribe to HSI updates
  Synheart.onHSIUpdate.listen((hsi) {
    print('HSI v${hsi.hsiVersion} at ${hsi.observedAtUtc}');
    final physiologicalReadings = hsi.axes?.physiological?.readings ?? [];
    for (final r in physiologicalReadings) {
      print('  ${r.axis}: ${r.score}');
    }
  });

  // Start session — data collection begins
  await Synheart.startSession();
  print('Session started');

  // Run for 30 seconds
  await Future.delayed(Duration(seconds: 30));

  // Clean up
  await Synheart.stopSession();
  await Synheart.dispose();
}
