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

  /// Create from BehaviorSessionSummary
  factory BehaviorSessionResults.fromSummary(sb.BehaviorSessionSummary summary) {
    // Extract tap rate from activity summary
    // Normalize based on typical values (assume max 10 taps/sec = 1.0)
    final tapRate = (summary.activitySummary.totalEvents / 
        (summary.durationMs / 1000.0) / 10.0).clamp(0.0, 1.0);

    // Extract keystroke rate from typing summary if available
    double keystrokeRate = 0.0;
    if (summary.typingSessionSummary != null) {
      final typing = summary.typingSessionSummary!;
      // Normalize based on typical typing speed (assume max 10 keystrokes/sec = 1.0)
      keystrokeRate = (typing.averageTypingSpeed / 10.0).clamp(0.0, 1.0);
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

