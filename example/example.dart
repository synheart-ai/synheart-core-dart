// ignore_for_file: avoid_print
import 'package:synheart_core/synheart_core.dart';

/// Minimal Synheart Core usage — the smallest thing that produces HSI.
///
/// This is the snippet pub.dev shows on the package page. The runnable Flutter
/// app lives in `example/lib/`, which walks the same lifecycle across four
/// screens: setup, consent, session, diagnostics.
///
/// Local-only: no cloud credentials, nothing leaves the device.
Future<void> main() async {
  // 1. Configure and load the native runtime.
  //
  //    `appId` and `subjectId` are both REQUIRED — validate() rejects an empty
  //    value before any native work happens. `subjectId` must be STABLE across
  //    restarts: the runtime scopes storage, baselines, and device identity to
  //    it, so a value that changes per launch looks like a new person every
  //    time and baselines never mature. Use your own account id.
  //
  //    Note that passing `userId:` to initialize() does NOT populate
  //    `config.subjectId`; set it on the config.
  try {
    await Synheart.initialize(
      config: SynheartConfig(
        appId: 'com.example.my_app',
        subjectId: 'usr_stable_identifier',
        // Development only. Production gates capabilities on a verified
        // consent token instead.
        allowUnsignedCapabilities: true,
        // Declaring a module config activates that feature.
        wearConfig: const WearConfig(),
        // Required for the runtime consent-form flow below.
        consentConfig: ConsentConfig(
          deviceId: 'dev_stable_identifier',
          platform: 'flutter',
          userId: 'usr_stable_identifier',
        ),
      ),
    );
  } on SynheartError catch (e) {
    // The message names the offending field and how to fix it.
    print('Configuration rejected — ${e.code}: ${e.message}');
    return;
  }

  // 2. Consent, via the runtime's editable-form flow.
  //
  //    The runtime persists the choice offline-first and, when cloud is
  //    enabled, reconciles it against the cloud default profile. Read the form,
  //    edit it, submit it.
  final form = Synheart.consentGetEditableFormTyped();
  if (form != null) {
    await Synheart.consentSubmitFormTyped(
      form: form.copyWith(biosignals: true, allowCloud: false),
    );
  }

  // The runtime may grant less than was asked for. Gate features on the
  // EFFECTIVE state, never on the submitted form.
  final effective = Synheart.consentEffectiveStateTyped();
  if (effective?.biosignals != true) {
    print('Biosignals not granted — HSI would be dropped. Stopping.');
    await Synheart.dispose();
    return;
  }

  // 3. Subscribe before starting, so the first completed window is not missed.
  final subscription = Synheart.onStateUpdate.listen((state) {
    if (state.hasParseError) {
      print('HSI parse failed: ${state.parseError}');
      return;
    }
    print('focus=${state.hsi.focus?.value} stress=${state.hsi.stress?.value}');
  });

  // 4. Collection starts here — initialize() alone collects nothing.
  await Synheart.startSession();

  // Signal comes from the modules the config activated — the wear module reads
  // HealthKit / Health Connect / a paired strap and pushes into the runtime
  // itself. Observe what arrives:
  final samples = Synheart.wearSampleStream.listen((sample) {
    print('hr=${sample.hr} rmssd=${sample.hrvRmssd}');
  });

  // If you own a source the SDK does not adapt, push ITS REAL READINGS. Never
  // placeholder values: pushed samples feed the runtime's longitudinal
  // baselines, so fabricated beats corrupt the user's actual reference ranges.
  //
  // When one sensor notification carries several RR intervals, prefer
  // pushRrBatch over looping pushRr — the runtime reconstructs a distinct
  // timestamp per beat instead of collapsing them onto the shared arrival
  // time, so no beat is lost to HRV.
  //
  //   myStrap.onPacket.listen((packet) {
  //     Synheart.pushRrBatch(
  //       packet.arrivalMs,
  //       packet.rrIntervalsMs,
  //       provider: 'ble_hrm',
  //     );
  //   });

  await Future<void>.delayed(const Duration(seconds: 30));

  // 5. Clean shutdown.
  await Synheart.stopSession();
  await subscription.cancel();
  await samples.cancel();
  await Synheart.dispose();
}
