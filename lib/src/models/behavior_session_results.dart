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
  /// Raw rates are passed through without normalization. The native runtime
  /// is the authoritative source for normalized behavioral metrics.
  factory BehaviorSessionResults.fromSummary(
    sb.BehaviorSessionSummary summary,
  ) {
    final durationSec = summary.durationMs / 1000.0;
    final tapRate = durationSec > 0
        ? summary.activitySummary.totalEvents / durationSec
        : 0.0;

    double keystrokeRate = 0.0;
    if (summary.typingSessionSummary != null) {
      keystrokeRate = summary.typingSessionSummary!.averageTypingSpeed;
    }

    return BehaviorSessionResults(
      sessionId: summary.sessionId,
      durationMs: summary.durationMs,
      tapRate: tapRate,
      keystrokeRate: keystrokeRate,
      focusHint: summary.behavioralMetrics.focusHint,
      interactionIntensity: summary.behavioralMetrics.interactionIntensity,
      burstiness: summary.behavioralMetrics.burstiness,
      totalEvents: summary.activitySummary.totalEvents,
      summary: summary,
    );
  }
}
