import '../../models/readiness_score.dart';
import '../../models/recovery_score.dart';
import '../../models/sleep_score.dart';

/// A typed aggregate of the host-visible baseline state at a point in
/// time.
///
/// Produced by the SDK's [Baselines] facade whenever a new sleep score
/// is ingested or the wearable reference refreshes. Consumers read this
/// to render a "your normal" / SRM overview without having to touch
/// FFI or parse raw JSON.
class BaselinesSnapshot {
  /// Longitudinal-SRM reference view (status, per-dimension medians,
  /// Path-B `recent_sleep_score_median`). Null before the first
  /// reference is produced — an HSI window has to close before the
  /// engine flushes the ring → reference.
  final WearableReferenceView? reference;

  /// The most recently computed batch `SleepScoreResult`, or null if
  /// no sleep event has been ingested this session (or via persisted
  /// history — the score itself is not persisted, the Path-B ring is).
  final SleepScoreResult? latestSleepScore;

  /// The most recent daily Recovery Score per RFC-RECOVERY-SCORE-0001,
  /// computed alongside the sleep ingest when overnight HR or HRV is
  /// available in the same payload. Null when the user has only sleep
  /// data (sleep-only recovery is forbidden by design) or the runtime
  /// hasn't computed one yet this session.
  final RecoveryScoreResult? latestRecoveryScore;

  /// The most recent daily Readiness Score per RFC-READINESS-SCORE-0001,
  /// computed automatically each time a Recovery Score lands. Layers
  /// fatigue (sleep debt + recovery slope) and history (consecutive
  /// overload) on top of the Recovery anchor. Null until at least one
  /// Recovery Score has been computed this session.
  final ReadinessScoreResult? latestReadinessScore;

  /// Path-B 7-night rolling-window scores in attach order
  /// (oldest → newest), read directly from the longitudinal snapshot.
  /// Updates the moment a score is attached, so consumers can show
  /// "N/7 nights logged" + median without waiting for an HSI window
  /// to close. Empty until first ingest.
  final List<int> recentSleepScores;

  /// Millisecond timestamp when this snapshot was assembled.
  final int capturedAtMs;

  const BaselinesSnapshot({
    required this.reference,
    required this.latestSleepScore,
    this.latestRecoveryScore,
    this.latestReadinessScore,
    this.recentSleepScores = const [],
    required this.capturedAtMs,
  });

  /// True when nothing has been ingested and the engine hasn't
  /// produced a reference — useful for rendering an empty/warming
  /// state in UI.
  bool get isEmpty =>
      reference == null &&
      latestSleepScore == null &&
      recentSleepScores.isEmpty;

  /// True when the reference is present and reports `Stable` status.
  bool get isStable => (reference?.status ?? '').toLowerCase() == 'stable';

  /// Number of prior nights behind the live score, when available.
  int? get priorNightCount => latestSleepScore?.priorNightCount;

  /// Number of nights captured in the Path-B ring this session
  /// (capped at 7). This is the right "nights logged" surface for
  /// the user — `priorNightCount` reflects what the scorer saw, not
  /// the cumulative count of attaches.
  int get nightsLoggedCount => recentSleepScores.length;

  /// Median of the recent ring; available immediately after the
  /// 3rd attach, regardless of HSI window state. Falls back to the
  /// reference's median when the ring isn't populated locally.
  int? get recentMedian {
    if (recentSleepScores.isEmpty) {
      return reference?.recentSleepScoreMedian;
    }
    final sorted = [...recentSleepScores]..sort();
    return sorted[sorted.length ~/ 2];
  }
}
