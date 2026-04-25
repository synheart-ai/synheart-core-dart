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
  /// reference is produced.
  final WearableReferenceView? reference;

  /// The most recently computed batch `SleepScoreResult`, or null if
  /// no sleep event has been ingested this session (or via persisted
  /// history — the score itself is not persisted, the Path-B ring is).
  final SleepScoreResult? latestSleepScore;

  /// Millisecond timestamp when this snapshot was assembled.
  final int capturedAtMs;

  const BaselinesSnapshot({
    required this.reference,
    required this.latestSleepScore,
    required this.capturedAtMs,
  });

  /// True when neither a reference nor a sleep score has been observed
  /// yet — useful for rendering an empty/warming state in UI.
  bool get isEmpty => reference == null && latestSleepScore == null;

  /// True when the reference is present and reports `Stable` status.
  bool get isStable =>
      (reference?.status ?? '').toLowerCase() == 'stable';

  /// Number of prior nights behind the live score, when available.
  int? get priorNightCount => latestSleepScore?.priorNightCount;
}
