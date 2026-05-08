// SPDX-License-Identifier: Apache-2.0
//
// Health Connect (Android) historical-read backfill.
//
// Android's "Apple Health export.zip" doesn't exist — Health Connect
// is an API-only system database with no user-facing export gesture.
// What it DOES offer is a permission-gated `getHealthDataFromTypes`
// read with a `(start, end)` window, which lets us pull as far back
// as the system retained the data for that record type.
//
// Retention is per-record-type and outside our control. As of 2026:
//   - Heart rate samples: typically 30 days of high-resolution data
//   - Sleep sessions: 1–2 years
//   - Steps / activity: years
//
// So an Android user gets less historical context than an iOS user
// importing a years-old `export.zip`. There's no platform fix for
// that — we just pull what's there.
//
// On iOS this class is a no-op fast-return: HealthKit historical
// data lives behind the Apple Health export.zip path
// (`AppleHealthRuntimeSink`), and the cross-platform `HealthAdapter`
// reads only return the same window we'd already get live. Calling
// here on iOS is harmless but pointless.
//
// ## Usage
//
// ```dart
// final sink = HealthConnectRuntimeSink();
// final result = await sink.backfill(daysBack: 365);
// // result.daysIngested = number of (day, dimension) tuples pushed
// ```

import 'dart:async';
import 'dart:io';

import 'package:synheart_wear/synheart_wear.dart';

import '../synheart.dart' show Synheart;
import 'apple_health_runtime_sink.dart'
    show PushDailyCallback, TriggerRecomputeCallback;

/// Outcome of a Health Connect historical pull.
class HealthConnectBackfillResult {
  const HealthConnectBackfillResult({
    required this.requestedDaysBack,
    required this.daysIngested,
    required this.dimensionsPushed,
    required this.skipped,
    required this.skipReason,
    required this.durationMs,
  });

  /// Days of history we asked the platform for.
  final int requestedDaysBack;

  /// Distinct days that produced at least one push (i.e. days where
  /// either sleep or overnight HR/HRV came back from the read).
  /// Always 0 on iOS / when no permissions / when no data found.
  final int daysIngested;

  /// Total `srmPushWearableDaily` calls fired across all days. Each
  /// day can contribute up to 5 (resting_hr, hrv_rmssd, sleep_need,
  /// deep_sleep_min, rem_sleep_min) depending on what the platform
  /// returned.
  final int dimensionsPushed;

  /// True when the call short-circuited (wrong platform, no
  /// permissions, no SDK available). [skipReason] explains why.
  final bool skipped;
  final String? skipReason;

  /// Wall-clock time the read + replay took. Health Connect can be
  /// slow (10s+ for a year of HR samples on cold cache) — surface
  /// this so callers can decide between blocking UI vs. background.
  final int durationMs;
}

/// High-level "bring your Health Connect history" call. Mirrors the
/// shape of [AppleHealthRuntimeSink] (Apple zip import) so the two
/// platforms have parallel public APIs even though the underlying
/// data sources are different.
///
/// Aggregations match the Apple Health path:
/// - `hrv_rmssd` from [HealthAdapter.fetchOvernightPhysiology] (which
///   already normalises Android RMSSD ↔ iOS SDNN-as-RMSSD).
/// - `resting_hr` from the same overnight summary.
/// - `sleep_need` (seconds) / `deep_sleep_min` / `rem_sleep_min` from
///   [HealthAdapter.fetchSleepNights].
///
/// All values land via `Synheart.srmPushWearableDaily`, which feeds
/// the longitudinal SRM directly and the live SRM via the Synheart
/// Runtime's wearable-daily ingest path.
class HealthConnectRuntimeSink {
  HealthConnectRuntimeSink({
    PushDailyCallback? pushDaily,
    TriggerRecomputeCallback? triggerRecompute,
  }) : _pushDaily = pushDaily ?? _defaultPushDaily,
       _triggerRecompute = triggerRecompute ?? _defaultTriggerRecompute;

  final PushDailyCallback _pushDaily;
  final TriggerRecomputeCallback _triggerRecompute;

  /// Pull `daysBack` days of historical sleep + overnight physiology
  /// from Health Connect (Android) and push them into the runtime
  /// SRM. Default is 365 days; the actual window is bounded by
  /// platform retention (30 days for HR, longer for sleep).
  ///
  /// On iOS this is a no-op (call [AppleHealthRuntimeSink] for the
  /// `export.zip` path instead). Returns a result with
  /// `skipped: true` and a reason so callers can surface a sensible
  /// message.
  Future<HealthConnectBackfillResult> backfill({int daysBack = 365}) async {
    final stopwatch = Stopwatch()..start();

    if (!Platform.isAndroid) {
      return HealthConnectBackfillResult(
        requestedDaysBack: daysBack,
        daysIngested: 0,
        dimensionsPushed: 0,
        skipped: true,
        skipReason:
            'Health Connect import is Android-only. '
            'Use AppleHealthRuntimeSink with export.zip on iOS.',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    if (daysBack <= 0) {
      return HealthConnectBackfillResult(
        requestedDaysBack: daysBack,
        daysIngested: 0,
        dimensionsPushed: 0,
        skipped: true,
        skipReason: 'daysBack must be positive',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    final available = await HealthAdapter.isAvailable();
    if (!available) {
      return HealthConnectBackfillResult(
        requestedDaysBack: daysBack,
        daysIngested: 0,
        dimensionsPushed: 0,
        skipped: true,
        skipReason: 'Health Connect not available on this device',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // Align the window to local-day boundaries so the bucketing
    // inside HealthAdapter (which uses local-day keys) matches what
    // we ask for. The end is "right now" — Health Connect tolerates
    // mid-day end times and just returns whatever's available.
    final now = DateTime.now();
    final end = now;
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: daysBack));

    // Two parallel reads — different record types, no shared state.
    // Health Connect's read is rate-limited per-process so running
    // them in parallel is fine and saves wall time.
    final futures = await Future.wait<Object>([
      HealthAdapter.fetchSleepNights(
        start: start,
        end: end,
        bypassThrottle: true,
      ),
      HealthAdapter.fetchOvernightPhysiology(
        start: start,
        end: end,
        bypassThrottle: true,
      ),
    ]);
    final sleep = futures[0] as Map<DateTime, SleepNightSummary>;
    final overnight = futures[1] as Map<DateTime, OvernightPhysiologySummary>;

    // Union of distinct days seen in either stream. Some days will
    // have only sleep, others only overnight HR/HRV (e.g. user wore
    // the watch but the sleep classifier didn't fire).
    final allDays = <DateTime>{...sleep.keys, ...overnight.keys};

    var dimensionsPushed = 0;
    var daysIngested = 0;
    for (final day in allDays) {
      final dayIndex = _epochDay(day);
      var dayDidPush = false;

      final sleepNight = sleep[day];
      if (sleepNight != null && sleepNight.totalAsleepMinutes > 0) {
        // sleep_need is in seconds (per the physiology spec).
        _pushDaily(
          dimension: 'sleep_need',
          dayIndex: dayIndex,
          value: sleepNight.totalAsleepMinutes * 60.0,
          confidence: 0.85,
          fidelity: 1,
        );
        dimensionsPushed += 1;
        dayDidPush = true;

        if (sleepNight.deepMinutes != null && sleepNight.deepMinutes! > 0) {
          _pushDaily(
            dimension: 'deep_sleep_min',
            dayIndex: dayIndex,
            value: sleepNight.deepMinutes!,
            confidence: 0.85,
            fidelity: 1,
          );
          dimensionsPushed += 1;
        }
        if (sleepNight.remMinutes != null && sleepNight.remMinutes! > 0) {
          _pushDaily(
            dimension: 'rem_sleep_min',
            dayIndex: dayIndex,
            value: sleepNight.remMinutes!,
            confidence: 0.85,
            fidelity: 1,
          );
          dimensionsPushed += 1;
        }
      }

      final overnightSummary = overnight[day];
      if (overnightSummary != null) {
        if (overnightSummary.hrvRmssdMs != null &&
            overnightSummary.hrvRmssdMs! > 0) {
          _pushDaily(
            dimension: 'hrv_rmssd',
            dayIndex: dayIndex,
            value: overnightSummary.hrvRmssdMs!,
            confidence: 0.85,
            fidelity: 1,
          );
          dimensionsPushed += 1;
          dayDidPush = true;
        }
        if (overnightSummary.restingHrBpm != null &&
            overnightSummary.restingHrBpm! > 0) {
          _pushDaily(
            dimension: 'resting_hr',
            dayIndex: dayIndex,
            value: overnightSummary.restingHrBpm!,
            confidence: 0.85,
            fidelity: 1,
          );
          dimensionsPushed += 1;
          dayDidPush = true;
        }
      }

      if (dayDidPush) daysIngested += 1;
    }

    if (dimensionsPushed > 0) {
      _triggerRecompute();
    }

    stopwatch.stop();
    return HealthConnectBackfillResult(
      requestedDaysBack: daysBack,
      daysIngested: daysIngested,
      dimensionsPushed: dimensionsPushed,
      skipped: false,
      skipReason: null,
      durationMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Convert a local-time wake date (as returned by
  /// `HealthAdapter.fetchSleepNights`) to the unix-epoch day index
  /// the SRM uses. Always operates in UTC so the day boundary is
  /// stable across timezone changes — matches the semantics of
  /// `Synheart.epochDayFor`.
  static int _epochDay(DateTime localDay) {
    final utcMidnight = DateTime.utc(
      localDay.year,
      localDay.month,
      localDay.day,
    );
    return utcMidnight.millisecondsSinceEpoch ~/ 86_400_000;
  }

  static void _defaultPushDaily({
    required String dimension,
    required int dayIndex,
    required double value,
    double confidence = 0.85,
    int fidelity = 1,
  }) {
    Synheart.srmPushWearableDaily(
      dimension: dimension,
      dayIndex: dayIndex,
      value: value,
      confidence: confidence,
      fidelity: fidelity,
    );
  }

  static void _defaultTriggerRecompute() {
    Synheart.srmTriggerWearableRecompute();
  }
}
