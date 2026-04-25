import 'dart:async';

import '../../core/logger.dart';
import '../../models/sleep_questionnaire.dart';
import '../../models/sleep_score.dart';
import '../../synheart.dart';
import 'baselines_snapshot.dart';

/// Host-facing facade over the RFC-SLEEP-SCORE-PIPELINE-0001 baseline
/// surface.
///
/// Wraps the three primitives already exposed on [Synheart]:
/// `computeSleepScore`, `attachSleepScore`, `wearableReference` — and
/// adds:
///   • vendor-payload → `NightRaw` normalization (WHOOP + Garmin),
///   • an in-memory cache of the most recent [SleepScoreResult] and
///     [WearableReferenceView],
///   • a broadcast [Stream] of [BaselinesSnapshot] that fires on every
///     successful ingest.
///
/// Any consumer app (pulse-focus, future SDK hosts) can drive a
/// "Baselines" / SRM page by calling [ingestVendorSleep] from its
/// vendor-event plumbing and reading [snapshot] / [updates] from the
/// UI layer. The facade deliberately holds no configuration state of
/// its own — `Synheart.initialize(...)` is the single initialization
/// point; [Baselines] is safe to use as soon as the runtime is up.
class Baselines {
  Baselines._();

  static final StreamController<BaselinesSnapshot> _ctrl =
      StreamController<BaselinesSnapshot>.broadcast();

  static SleepScoreResult? _latestScore;
  static WearableReferenceView? _latestReference;
  static String? _lastSource;

  /// In-memory dedupe: maps `(wake_calendar_date, provider)` to the
  /// score we already attached for that key in this process. Same
  /// vendor pushing the same night again is silently no-op'd; a
  /// different source for the same night is allowed through (the
  /// signals are not interchangeable, the Path-B ring should reflect
  /// both observations).
  static final Map<String, int> _attachedKeys = <String, int>{};

  /// Days-since-epoch anchor used by the engine's `wake_calendar_date`
  /// field. Keeps the absolute value in an i32-safe range regardless
  /// of what year the device clock reports.
  static final int _wakeDayAnchor =
      DateTime.utc(2025, 1, 1).millisecondsSinceEpoch ~/ 86400000;

  /// Broadcast stream of baseline snapshots; emits after every
  /// successful [ingestVendorSleep] call.
  static Stream<BaselinesSnapshot> get updates => _ctrl.stream;

  /// The most recent [SleepScoreResult], or null if none has been
  /// ingested in this process.
  static SleepScoreResult? get latestSleepScore => _latestScore;

  /// The most recent [WearableReferenceView], or null if the engine
  /// has not yet produced one.
  static WearableReferenceView? get reference => _latestReference;

  /// Provider id of the source that produced [latestSleepScore].
  /// Possible values include `whoop`, `garmin`, `apple_health`,
  /// `health_connect`, `self_report`, or null when no score has been
  /// ingested in this process.
  static String? get lastSource => _lastSource;

  /// Point-in-time snapshot of the current baseline state. Cheap —
  /// does not round-trip through FFI.
  static BaselinesSnapshot get snapshot => BaselinesSnapshot(
        reference: _latestReference,
        latestSleepScore: _latestScore,
        capturedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  /// Ingest a vendor sleep event payload, run the batch scorer, and
  /// attach the result so the next HSI window carries the
  /// `sleep_score` axis and the Path-B 7-night ring is updated.
  ///
  /// `provider` — vendor id (`"whoop"`, `"garmin"`, etc.).
  ///
  /// `payload` — the same map passed to
  /// [Synheart.processVendorEvent]; typically the vendor's merged
  /// metrics + meta. May carry the raw vendor item under
  /// `whoop_data` / `garmin_data`.
  ///
  /// Returns the computed [SleepScoreResult], or `null` if the
  /// payload carried nothing scorable.
  static Future<SleepScoreResult?> ingestVendorSleep({
    required String provider,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final night = _buildNightRaw(provider: provider, payload: payload);
      if (night == null) {
        SynheartLogger.stream(
            'Baselines: no scorable sleep data in $provider payload');
        return null;
      }

      final input = SleepScoreInput(
        tonight: night,
        priorsNewestFirst: const [],
      );
      final result = Synheart.computeSleepScore(input);
      if (result == null) {
        SynheartLogger.stream(
            'Baselines: engine returned null for $provider');
        return null;
      }

      final dedupeKey = '$provider:${night.wakeCalendarDate}';
      if (_attachedKeys.containsKey(dedupeKey)) {
        SynheartLogger.stream(
            'Baselines: dedupe hit for $dedupeKey, skipping attach');
        // Still surface the latest computed result so UI sees fresh
        // numbers, but don't re-push into the Path-B ring.
        _latestScore = result;
        _latestReference = Synheart.wearableReference;
        _lastSource = provider;
        if (!_ctrl.isClosed) _ctrl.add(snapshot);
        return result;
      }

      final rc = Synheart.attachSleepScore(result);
      if (rc != 0) {
        SynheartLogger.stream('Baselines: attachSleepScore rc=$rc');
      } else {
        _attachedKeys[dedupeKey] = result.score ?? 0;
      }

      _latestScore = result;
      _latestReference = Synheart.wearableReference;
      _lastSource = provider;

      if (!_ctrl.isClosed) _ctrl.add(snapshot);

      SynheartLogger.stream(
          'Baselines: $provider → score=${result.score} '
          'path=${result.path.wire} mode=${result.mode.wire}');
      return result;
    } catch (e, st) {
      SynheartLogger.stream('Baselines ingest failed: $e',
          error: e, stackTrace: st);
      return null;
    }
  }

  /// Ingest a self-reported sleep questionnaire, derive aggregated
  /// totals, and route through [ingestVendorSleep] under the
  /// `self_report` provider. Returns the computed result.
  ///
  /// Subjective quality / felt-rested fields are passed through the
  /// payload for UI display but the scorer ignores them — we don't
  /// fabricate stage durations from subjective signals.
  static Future<SleepScoreResult?> ingestSelfReportedSleep(
      SleepQuestionnaireAnswers answers) {
    return ingestVendorSleep(
      provider: 'self_report',
      payload: answers.toIngestPayload(),
    );
  }

  /// Force-refresh the cached [reference] by re-reading it from the
  /// runtime and emit a new snapshot. Useful after the host persists
  /// a longitudinal snapshot and reloads it.
  static BaselinesSnapshot refreshReference() {
    _latestReference = Synheart.wearableReference;
    final s = snapshot;
    if (!_ctrl.isClosed) _ctrl.add(s);
    return s;
  }

  // ── Vendor → NightRaw normalization ─────────────────────────────

  static NightRaw? _buildNightRaw({
    required String provider,
    required Map<String, dynamic> payload,
  }) {
    final timestampMs = _extractTimestampMs(payload);
    final wakeDay = _calendarDayFromMs(timestampMs);

    final raw = switch (provider) {
      'whoop' => payload['whoop_data'] as Map<String, dynamic>?,
      'garmin' => payload['garmin_data'] as Map<String, dynamic>?,
      'self_report' => payload['self_report_data'] as Map<String, dynamic>?,
      'apple_health' =>
        payload['apple_health_data'] as Map<String, dynamic>?,
      'health_connect' =>
        payload['health_connect_data'] as Map<String, dynamic>?,
      _ => null,
    };

    final aggregated = _buildAggregated(provider, raw);
    if (aggregated != null) {
      return NightRaw(
        wakeCalendarDate: wakeDay,
        detail: aggregated,
        avgHrBpm:
            _numDouble(payload['avg_hr_bpm']) ?? _numDouble(payload['hr']),
      );
    }

    final score = _extractVendorScore(provider, raw, payload);
    if (score != null) {
      return NightRaw(
        wakeCalendarDate: wakeDay,
        detail: VendorScoreNight(score: score),
        avgHrBpm:
            _numDouble(payload['avg_hr_bpm']) ?? _numDouble(payload['hr']),
      );
    }

    return null;
  }

  static AggregatedNight? _buildAggregated(
      String provider, Map<String, dynamic>? raw) {
    if (raw == null) return null;

    switch (provider) {
      case 'whoop':
        final score = raw['score'];
        if (score is! Map) return null;
        final stage = score['stage_summary'];
        if (stage is! Map) return null;
        final totalMs = _num(stage['total_sleep_time_milli']);
        if (totalMs == null || totalMs <= 0) return null;
        final deepMs = _num(stage['total_slow_wave_sleep_time_milli']) ?? 0;
        final remMs = _num(stage['total_rem_sleep_time_milli']) ?? 0;
        final awakeMs = _num(stage['total_awake_time_milli']) ?? 0;
        final awakenings = _num(stage['disturbance_count'])?.toInt() ?? 0;
        final tibMs = totalMs + awakeMs;
        final sessionStart =
            _num(raw['start'])?.toInt() ?? _parseIsoMs(raw['start']);
        final sessionEnd =
            _num(raw['end'])?.toInt() ?? _parseIsoMs(raw['end']);
        return AggregatedNight(
          sessionStartMs: sessionStart,
          sessionEndMs: sessionEnd,
          totals: AggregatedTotals(
            totalSleepMinutes: totalMs / 60000.0,
            deepSleepMinutes: deepMs / 60000.0,
            remSleepMinutes: remMs / 60000.0,
            awakeMinutes: awakeMs / 60000.0,
            awakenings: awakenings,
            timeInBedMinutes: tibMs / 60000.0,
          ),
        );

      case 'self_report':
      case 'apple_health':
      case 'health_connect':
        // All three carry the same flat-totals shape on the SDK side.
        // Apple Health / Health Connect can populate deep/REM when
        // the host pulled the per-stage types; otherwise zeros are
        // returned and the engine scores on duration/continuity
        // alone (same honest fallback as self-report).
        final totalSleep = _num(raw['total_sleep_minutes']);
        if (totalSleep == null || totalSleep <= 0) return null;
        return AggregatedNight(
          sessionStartMs: _num(raw['session_start_ms'])?.toInt(),
          sessionEndMs: _num(raw['session_end_ms'])?.toInt(),
          totals: AggregatedTotals(
            totalSleepMinutes: totalSleep.toDouble(),
            deepSleepMinutes: (_num(raw['deep_sleep_minutes']) ?? 0).toDouble(),
            remSleepMinutes: (_num(raw['rem_sleep_minutes']) ?? 0).toDouble(),
            awakeMinutes: (_num(raw['awake_minutes']) ?? 0).toDouble(),
            awakenings: _num(raw['awakenings'])?.toInt() ?? 0,
            timeInBedMinutes:
                (_num(raw['time_in_bed_minutes']) ?? totalSleep).toDouble(),
          ),
        );

      case 'garmin':
        final totalS = _num(raw['durationInSeconds']);
        if (totalS == null || totalS <= 0) return null;
        final deepS = _num(raw['deepSleepDurationInSeconds']) ?? 0;
        final remS = _num(raw['remSleepInSeconds']) ?? 0;
        final awakeS = _num(raw['awakeDurationInSeconds']) ?? 0;
        final totalSleepS = (totalS - awakeS).clamp(0.0, totalS.toDouble());
        final sessionStart = _num(raw['startTimeInSeconds'])?.toInt();
        final sessionEnd =
            sessionStart != null ? sessionStart + totalS.toInt() : null;
        return AggregatedNight(
          sessionStartMs: sessionStart != null ? sessionStart * 1000 : null,
          sessionEndMs: sessionEnd != null ? sessionEnd * 1000 : null,
          totals: AggregatedTotals(
            totalSleepMinutes: totalSleepS / 60.0,
            deepSleepMinutes: deepS / 60.0,
            remSleepMinutes: remS / 60.0,
            awakeMinutes: awakeS / 60.0,
            awakenings: 0,
            timeInBedMinutes: totalS / 60.0,
          ),
        );
    }
    return null;
  }

  static int? _extractVendorScore(
    String provider,
    Map<String, dynamic>? raw,
    Map<String, dynamic> payload,
  ) {
    final direct = _num(payload['sleep_score']);
    if (direct != null) return direct.round().clamp(0, 100);

    switch (provider) {
      case 'whoop':
        final score = raw?['score'];
        if (score is Map) {
          final perf = _num(score['sleep_performance_percentage']);
          if (perf != null) return perf.round().clamp(0, 100);
        }
      case 'garmin':
        final q = _num(raw?['overallSleepScore'] ??
            (raw?['sleepScores'] as Map?)?['overall']?['value']);
        if (q != null) return q.round().clamp(0, 100);
    }
    return null;
  }

  static int _calendarDayFromMs(int ms) {
    final day = ms ~/ 86400000;
    return day - _wakeDayAnchor + 20100;
  }

  static int _extractTimestampMs(Map<String, dynamic> payload) {
    final ts = payload['timestamp'];
    if (ts is String) {
      final parsed = DateTime.tryParse(ts);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    if (ts is int) return ts;
    final ms = _num(payload['observed_at_ms']);
    if (ms != null) return ms.toInt();
    return DateTime.now().millisecondsSinceEpoch;
  }

  static int? _parseIsoMs(Object? v) {
    if (v is! String) return null;
    return DateTime.tryParse(v)?.millisecondsSinceEpoch;
  }

  static num? _num(Object? v) {
    if (v == null) return null;
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static double? _numDouble(Object? v) => _num(v)?.toDouble();
}
