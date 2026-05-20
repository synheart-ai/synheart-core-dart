import 'package:synheart_behavior/synheart_behavior.dart' as sb;

/// Results from a behavior session
///
/// Provides simplified access to key metrics from a behavior session.
class BehaviorSessionResults {
  /// Session ID
  final String sessionId;

  /// Duration in milliseconds
  final int durationMs;

  /// Tap rate (normalized 0.0-1.0)
  final double tapRate;

  /// Keystroke rate (normalized 0.0-1.0)
  final double keystrokeRate;

  /// Focus hint (0.0-1.0, higher = more focused)
  final double focusHint;

  /// Interaction intensity (0.0-1.0)
  final double interactionIntensity;

  /// Burstiness (0.0-1.0, higher = more bursty)
  final double burstiness;

  /// Total events in session
  final int totalEvents;

  /// Full session summary (for advanced use)
  final sb.BehaviorSessionSummary summary;

  BehaviorSessionResults({
    required this.sessionId,
    required this.durationMs,
    required this.tapRate,
    required this.keystrokeRate,
    required this.focusHint,
    required this.interactionIntensity,
    required this.burstiness,
    required this.totalEvents,
    required this.summary,
  });

  /// Create from BehaviorSessionSummary.
  ///
  /// The behavior SDK emits events and raw counts; per-session behavioral
  /// metrics (`focusHint`, `interactionIntensity`, `burstiness`, the
  /// `typingSessionSummary` aggregates) are computed by the native runtime
  /// from the event stream. Until a consumer has populated them on
  /// `summary.behavioralMetrics` / `summary.typingSessionSummary`, this
  /// factory defaults them to 0.
  factory BehaviorSessionResults.fromSummary(
    sb.BehaviorSessionSummary summary,
  ) {
    final durationSec = summary.durationMs / 1000.0;
    final tapRate = durationSec > 0
        ? summary.activitySummary.totalEvents / durationSec
        : 0.0;

    final keystrokeRate =
        summary.typingSessionSummary?.averageTypingSpeed ?? 0.0;
    // Declared nullable on purpose: behavior SDK >=0.3.x may emit a
    // summary with no behavioralMetrics. Pinning the type keeps the
    // null-aware access below valid regardless of the resolved SDK.
    final sb.BehavioralMetrics? metrics = summary.behavioralMetrics;

    return BehaviorSessionResults(
      sessionId: summary.sessionId,
      durationMs: summary.durationMs,
      tapRate: tapRate,
      keystrokeRate: keystrokeRate,
      focusHint: metrics?.focusHint ?? 0.0,
      interactionIntensity: metrics?.interactionIntensity ?? 0.0,
      burstiness: metrics?.burstiness ?? 0.0,
      totalEvents: summary.activitySummary.totalEvents,
      summary: summary,
    );
  }
}
