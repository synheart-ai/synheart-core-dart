// SPDX-License-Identifier: Apache-2.0
//
// Multi-day HRV-CV resilience score — Flutter binding.
//
// Stateless: hand a window of HRV samples and the sleep intervals
// they were collected over, get back a 0–100 score with provenance
// fields. The native function ships in newer runtime builds;
// older runtimes return `null` from the FFI lookup and
// `compute()` reports `ResilienceUnavailable`.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../core_runtime/ffi_bindings.dart';

/// What [HrvSample.rmssdMs] actually represents — see the runtime's
/// `synheart_resilience::HrvSampleKind` enum for full math
/// implications.
///
/// - [rawRr] — beat-to-beat RR interval (ms). Engine treats the
///   sequence as raw RR and computes RMSSD/SDNN from successive
///   differences. Sources: Polar H10, Garmin BBI persisted streams.
///   Floor: typically thousands of samples per resilience window.
/// - [epochRmssd] — RMSSD over a 5-minute (or similar) epoch.
///   Engine computes CV across the per-epoch values. Sources:
///   HealthKit `HKHeartRateVariabilitySDNN`, Whoop sleep epochs.
///   Floor: ~30 across 5+ nights.
/// - [nightlyRmssd] — one RMSSD per sleep session. Engine computes
///   CV across nights; per-night SDNN is reported as `null` (it
///   would require RMSSD-of-RMSSDs which is meaningless). Sources:
///   Whoop recovery, Garmin daily, Apple Health nightly aggregates.
///   Floor: matches `min_days_required` (5 by default).
enum HrvSampleKind {
  rawRr('raw_rr'),
  epochRmssd('epoch_rmssd'),
  nightlyRmssd('nightly_rmssd');

  const HrvSampleKind(this.wire);
  final String wire;
}

/// One HRV sample at a point in time. Mirrors the runtime's
/// `HrvSample` struct.
///
/// `kind` declares the aggregation level so the engine can apply
/// the right math. Defaults to [HrvSampleKind.nightlyRmssd] — the
/// dominant host modality. Raw-RR callers MUST set
/// [HrvSampleKind.rawRr] explicitly.
class HrvSample {
  const HrvSample({
    required this.tsMs,
    required this.rmssdMs,
    this.kind = HrvSampleKind.nightlyRmssd,
  });
  final int tsMs;
  final double rmssdMs;
  final HrvSampleKind kind;

  Map<String, dynamic> toJson() => {
    'ts_ms': tsMs,
    'rmssd_ms': rmssdMs,
    'kind': kind.wire,
  };
}

/// Half-open `[startMs, endMs)` interval representing a sleep
/// window. The runtime filters HRV samples to those inside any
/// supplied window before computing CV.
class SleepWindow {
  const SleepWindow({required this.startMs, required this.endMs});
  final int startMs;
  final int endMs;

  Map<String, dynamic> toJson() => {'start_ms': startMs, 'end_ms': endMs};
}

/// Tunable parameters. Defaults match the runtime's defaults.
///
/// The runtime selects a sample-count floor based on the dominant
/// [HrvSampleKind] in the input — `minRawRrSamples` for raw beat-
/// to-beat streams, `minEpochSamples` for 5-minute epoch RMSSD,
/// `minNightlySamples` for one-RMSSD-per-night aggregates.
/// `minRrSamples` is a legacy fallback used only when the engine
/// can't tell the kinds apart (mixed input or empty); new callers
/// don't need to touch it.
class ResilienceConfig {
  const ResilienceConfig({
    this.lookbackDays = 7,
    this.minDaysRequired = 5,
    this.minRawRrSamples = 1800,
    this.minEpochSamples = 30,
    this.minNightlySamples = 5,
    this.minRrSamples = 20,
    this.cvCeilingPct = 7.0,
    this.cvFloorPct = 40.0,
  });

  final int lookbackDays;
  final int minDaysRequired;
  final int minRawRrSamples;
  final int minEpochSamples;
  final int minNightlySamples;
  final int minRrSamples;
  final double cvCeilingPct;
  final double cvFloorPct;

  Map<String, dynamic> toJson() => {
    'lookback_days': lookbackDays,
    'min_days_required': minDaysRequired,
    'min_raw_rr_samples': minRawRrSamples,
    'min_epoch_samples': minEpochSamples,
    'min_nightly_samples': minNightlySamples,
    'min_rr_samples': minRrSamples,
    'cv_ceiling_pct': cvCeilingPct,
    'cv_floor_pct': cvFloorPct,
  };
}

/// Why a resilience score might not be available.
enum ResilienceReason {
  insufficientDays,
  noSleepWindows,
  insufficientSamples,
  noValidSamples,
  zeroMeanHrv;

  static ResilienceReason? fromWire(String? raw) {
    if (raw == null) return null;
    switch (raw) {
      case 'InsufficientDays':
        return ResilienceReason.insufficientDays;
      case 'NoSleepWindows':
        return ResilienceReason.noSleepWindows;
      case 'InsufficientSamples':
        return ResilienceReason.insufficientSamples;
      case 'NoValidSamples':
        return ResilienceReason.noValidSamples;
      case 'ZeroMeanHrv':
        return ResilienceReason.zeroMeanHrv;
      default:
        return null;
    }
  }
}

/// Result returned by `compute()`. Mirrors the runtime's
/// `ResilienceScoreResult`.
class ResilienceResult {
  const ResilienceResult({
    required this.score,
    required this.rmssdOwMs,
    required this.sdnnOwMs,
    required this.hrvCvPct,
    required this.daysUsed,
    required this.samplesUsed,
    required this.confidence,
    required this.reason,
    required this.modelId,
    required this.pipelineVersion,
    required this.constantsHash,
  });

  /// 0..=100 when computable, `null` when [reason] explains why not.
  final int? score;
  final double? rmssdOwMs;
  final double? sdnnOwMs;
  final double? hrvCvPct;
  final int daysUsed;
  final int samplesUsed;
  final double confidence;
  final ResilienceReason? reason;
  final String modelId;
  final String pipelineVersion;
  final String constantsHash;

  factory ResilienceResult.fromJson(Map<String, dynamic> j) {
    return ResilienceResult(
      score: j['score'] == null ? null : (j['score'] as num).toInt(),
      rmssdOwMs: (j['rmssd_ow_ms'] as num?)?.toDouble(),
      sdnnOwMs: (j['sdnn_ow_ms'] as num?)?.toDouble(),
      hrvCvPct: (j['hrv_cv_pct'] as num?)?.toDouble(),
      daysUsed: (j['days_used'] as num).toInt(),
      samplesUsed: (j['samples_used'] as num).toInt(),
      confidence: (j['confidence'] as num).toDouble(),
      reason: ResilienceReason.fromWire(j['reason'] as String?),
      modelId: j['model_id'] as String? ?? '',
      pipelineVersion: j['pipeline_version'] as String? ?? '',
      constantsHash: j['constants_hash'] as String? ?? '',
    );
  }
}

/// Errors thrown by the wrapper.
sealed class ResilienceError implements Exception {
  const ResilienceError(this.message);
  final String message;

  @override
  String toString() => 'ResilienceError: $message';
}

class ResilienceUnavailable extends ResilienceError {
  const ResilienceUnavailable()
    : super(
        'runtime resilience FFI not present (need '
        'update the native runtime with `synheart install runtime`)',
      );
}

class ResilienceComputeFailed extends ResilienceError {
  const ResilienceComputeFailed(super.message);
}

/// High-level Flutter binding. Construct once per app — the class is
/// stateless under the hood, so reuse is trivially safe.
class SynheartResilience {
  /// Pass `null` for `ffi` to force the not-available path (used by
  /// unit tests and apps developed against older runtimes).
  SynheartResilience({SynheartCoreFFI? ffi}) : _ffi = ffi;

  final SynheartCoreFFI? _ffi;

  /// Whether the loaded runtime exposes the resilience symbol.
  bool get isAvailable => _ffi?.resilienceComputeV1 != null;

  /// Compute a resilience score over the given samples + sleep
  /// windows. Throws [ResilienceUnavailable] when the runtime
  /// doesn't expose the FFI symbol; throws [ResilienceComputeFailed]
  /// when the runtime returns NULL or unparseable JSON.
  ResilienceResult compute({
    required List<HrvSample> samples,
    required List<SleepWindow> sleepWindows,
    ResilienceConfig config = const ResilienceConfig(),
  }) {
    final ffi = _ffi;
    if (ffi == null || ffi.resilienceComputeV1 == null) {
      throw const ResilienceUnavailable();
    }

    final samplesPtr = jsonEncode(
      samples.map((s) => s.toJson()).toList(),
    ).toNativeUtf8();
    final windowsPtr = jsonEncode(
      sleepWindows.map((w) => w.toJson()).toList(),
    ).toNativeUtf8();
    final configPtr = jsonEncode(config.toJson()).toNativeUtf8();
    Pointer<Utf8> resultPtr = nullptr;
    try {
      resultPtr = ffi.resilienceComputeV1!(samplesPtr, windowsPtr, configPtr);
      if (resultPtr == nullptr) {
        throw const ResilienceComputeFailed(
          'runtime returned NULL — likely malformed input',
        );
      }
      final raw = resultPtr.toDartString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return ResilienceResult.fromJson(decoded);
    } finally {
      malloc.free(samplesPtr);
      malloc.free(windowsPtr);
      malloc.free(configPtr);
      if (resultPtr != nullptr) {
        ffi.coreFreeString(resultPtr);
      }
    }
  }
}
