/// High-level Dart wrapper around the native breathing compliance detector.
///
/// All RR samples pushed via [`CoreRuntimeBridge.pushRr`] (i.e. Tier-1 BLE
/// chest-strap data) automatically feed the breathing detector. This module
/// configures the target rate / population profile and reads back the
/// current verdict. See RFC-Breathing-001 for the algorithm.
library;

import '../../core_runtime/core_runtime_bridge.dart';
import 'breathing_compliance_result.dart';

class BreathingModule {
  final CoreRuntimeBridge _bridge;

  BreathingModule(this._bridge);

  /// Set the target breathing rate in breaths per minute (e.g. `6.0` for
  /// resonance breathing).
  void setTargetBpm(double bpm) => _bridge.breathingSetTargetBpm(bpm);

  /// Set the rolling-window length in seconds. Native side clamps to `[30, 120]`.
  void setWindowSecs(int secs) => _bridge.breathingSetWindowSecs(secs);

  /// Choose threshold profile (defaults to [BreathingPopulation.beginner]).
  void setPopulation(BreathingPopulation profile) =>
      _bridge.breathingSetPopulation(profile.index);

  /// Compute compliance for the current RR window.
  /// Returns [BreathingInsufficient] if there isn't enough Tier-1 data yet.
  BreathingComplianceResult evaluate() {
    final json = _bridge.breathingEvaluateJson();
    if (json == null) {
      return const BreathingInsufficient(
        reason: NotEnoughBeats(have: 0, need: 50),
      );
    }
    return BreathingComplianceResult.fromJson(json);
  }

  /// Clear the RR ring buffer. Call when starting a new breathing exercise.
  void reset() => _bridge.breathingReset();
}
