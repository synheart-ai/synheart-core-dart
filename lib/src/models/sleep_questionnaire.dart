// Self-reported sleep questionnaire — Phase-2 input lane for the
// batch sleep scorer. Converts a small set of
// subjective answers into the same `AggregatedNight` shape vendor
// payloads produce, so the engine can score without special-casing.
//
// The engine accepts null deep/REM on the aggregated path and falls
// back to duration/continuity components — that's deliberate. Don't
// invent stage durations from subjective signals; surface subjective
// quality / rested-feeling in the UI alongside the score instead.

/// Subjective sleep quality, 1–5 stars.
enum SleepFeltRested {
  no('no'),
  somewhat('somewhat'),
  yes('yes');

  final String wire;
  const SleepFeltRested(this.wire);
}

/// One night of self-reported sleep. All fields are optional except
/// [bedtime] and [wakeTime] — without them we can't bound TIB.
class SleepQuestionnaireAnswers {
  /// When the user got into bed (local DateTime; we only use the
  /// wall-clock difference with [wakeTime]).
  final DateTime bedtime;

  /// When the user got out of bed.
  final DateTime wakeTime;

  /// Self-estimated sleep latency in minutes (time-to-fall-asleep).
  /// Default 15 — a population-mean fallback when the user skips.
  final int sleepLatencyMinutes;

  /// Number of remembered awakenings during the night.
  final int awakenings;

  /// Subjective quality, 1 (worst) – 5 (best). Optional; UI-only.
  final int? subjectiveQuality;

  /// "Did you wake up feeling rested?" Optional; UI-only.
  final SleepFeltRested? feltRested;

  const SleepQuestionnaireAnswers({
    required this.bedtime,
    required this.wakeTime,
    this.sleepLatencyMinutes = 15,
    this.awakenings = 0,
    this.subjectiveQuality,
    this.feltRested,
  });

  /// Time-in-bed in minutes (wake − bedtime, never negative).
  double get timeInBedMinutes {
    final diff = wakeTime.difference(bedtime).inMinutes.toDouble();
    return diff < 0 ? 0 : diff;
  }

  /// Heuristic awake minutes: latency + 5 min per awakening (a
  /// reasonable lower-bound; the user typically remembers fewer
  /// awakenings than actually occurred, but we'd rather under-count
  /// than fabricate).
  double get awakeMinutes {
    return (sleepLatencyMinutes + awakenings * 5).toDouble();
  }

  /// Estimated total asleep minutes.
  double get totalSleepMinutes {
    final tib = timeInBedMinutes;
    final asleep = tib - awakeMinutes;
    return asleep < 0 ? 0 : asleep;
  }

  /// Wire-shape payload for the SDK's `Baselines.ingestVendorSleep`
  /// call. Engine treats `kind: aggregated` with null deep/rem as the
  /// honest "we know totals, not stages" path.
  Map<String, dynamic> toIngestPayload() {
    return {
      // Carry the timestamp so calendar-date math lands on the
      // morning the user is reporting about.
      'timestamp': wakeTime.toUtc().toIso8601String(),
      // The engine reads `self_report_data` for the aggregated path.
      'self_report_data': {
        'time_in_bed_minutes': timeInBedMinutes,
        'total_sleep_minutes': totalSleepMinutes,
        'awake_minutes': awakeMinutes,
        'awakenings': awakenings,
        'session_start_ms': bedtime.millisecondsSinceEpoch,
        'session_end_ms': wakeTime.millisecondsSinceEpoch,
      },
      // UI-only; not consumed by the scorer.
      if (subjectiveQuality != null) 'subjective_quality': subjectiveQuality,
      if (feltRested != null) 'felt_rested': feltRested!.wire,
    };
  }
}
