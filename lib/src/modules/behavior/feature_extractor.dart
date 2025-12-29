import 'dart:math';
import '../interfaces/feature_providers.dart';
import 'behavior_events.dart';

/// Extracts behavioral features from events
class BehaviorFeatureExtractor {
  /// Extract features from a list of events
  BehaviorWindowFeatures extract(List<BehaviorEvent> events) {
    if (events.isEmpty) {
      return const BehaviorWindowFeatures(
        tapRateNorm: 0.0,
        keystrokeRateNorm: 0.0,
        scrollVelocityNorm: 0.0,
        idleRatio: 1.0,
        switchRateNorm: 0.0,
        burstiness: 0.0,
        sessionFragmentation: 0.0,
        notificationLoad: 0.0,
        distractionScore: 0.0,
        focusHint: 1.0,
      );
    }

    final tapRate = _calculateTapRate(events);
    final keystrokeRate = _calculateKeystrokeRate(events);
    final scrollVelocity = _calculateScrollVelocity(events);
    final idleRatio = _calculateIdleRatio(events);
    final switchRate = _calculateSwitchRate(events);
    final burstiness = _calculateBurstiness(events);
    final fragmentation = _calculateFragmentation(events);
    final notificationLoad = _calculateNotificationLoad(events);

    // Simple heuristic for distraction/focus (will be replaced by MLP)
    final distractionScore = _estimateDistraction(
      switchRate: switchRate,
      burstiness: burstiness,
      fragmentation: fragmentation,
      notificationLoad: notificationLoad,
    );
    final focusHint = 1.0 - distractionScore;

    return BehaviorWindowFeatures(
      tapRateNorm: tapRate,
      keystrokeRateNorm: keystrokeRate,
      scrollVelocityNorm: scrollVelocity,
      idleRatio: idleRatio,
      switchRateNorm: switchRate,
      burstiness: burstiness,
      sessionFragmentation: fragmentation,
      notificationLoad: notificationLoad,
      distractionScore: distractionScore,
      focusHint: focusHint,
    );
  }

  double _calculateTapRate(List<BehaviorEvent> events) {
    final taps = events.where((e) => e.type == BehaviorEventType.tap).length;
    final duration = _getDuration(events);
    if (duration == 0) return 0.0;
    return (taps / duration).clamp(0.0, 1.0);
  }

  double _calculateKeystrokeRate(List<BehaviorEvent> events) {
    final keystrokes = events
        .where((e) =>
            e.type == BehaviorEventType.keyDown ||
            e.type == BehaviorEventType.keyUp)
        .length;
    final duration = _getDuration(events);
    if (duration == 0) return 0.0;
    return (keystrokes / duration / 2)
        .clamp(0.0, 1.0); // Normalize to reasonable rate
  }

  double _calculateScrollVelocity(List<BehaviorEvent> events) {
    final scrollEvents =
        events.where((e) => e.type == BehaviorEventType.scroll);
    if (scrollEvents.isEmpty) return 0.0;

    final totalDelta = scrollEvents
        .map((e) => (e.metadata?['delta'] as double?) ?? 0.0)
        .reduce((a, b) => a + b.abs());

    final duration = _getDuration(events);
    if (duration == 0) return 0.0;

    return (totalDelta / duration / 100).clamp(0.0, 1.0); // Normalize
  }

  double _calculateIdleRatio(List<BehaviorEvent> events) {
    if (events.length < 2) return 1.0;

    final gaps = <double>[];
    for (int i = 1; i < events.length; i++) {
      final gap = events[i]
          .timestamp
          .difference(events[i - 1].timestamp)
          .inSeconds
          .toDouble();
      gaps.add(gap);
    }

    final longGaps = gaps.where((g) => g > 5.0).length; // Gaps > 5 seconds
    return (longGaps / gaps.length).clamp(0.0, 1.0);
  }

  double _calculateSwitchRate(List<BehaviorEvent> events) {
    final switches =
        events.where((e) => e.type == BehaviorEventType.appSwitch).length;
    final duration = _getDuration(events);
    if (duration == 0) return 0.0;
    return (switches / duration).clamp(0.0, 1.0);
  }

  double _calculateBurstiness(List<BehaviorEvent> events) {
    if (events.length < 2) return 0.0;

    // Calculate inter-event intervals
    final intervals = <double>[];
    for (int i = 1; i < events.length; i++) {
      intervals.add(events[i]
              .timestamp
              .difference(events[i - 1].timestamp)
              .inMilliseconds /
          1000.0);
    }

    if (intervals.isEmpty) return 0.0;

    // Burstiness: variance / mean
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    final variance =
        intervals.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
            intervals.length;

    return (variance / (mean + 0.001)).clamp(0.0, 1.0);
  }

  double _calculateFragmentation(List<BehaviorEvent> events) {
    if (events.isEmpty) return 0.0;

    // Count distinct "sessions" (clusters of events with < 30s gaps)
    int sessions = 1;
    for (int i = 1; i < events.length; i++) {
      final gap =
          events[i].timestamp.difference(events[i - 1].timestamp).inSeconds;
      if (gap > 30) sessions++;
    }

    // More sessions = more fragmentation
    return (sessions / max(events.length / 10, 1)).clamp(0.0, 1.0);
  }

  double _calculateNotificationLoad(List<BehaviorEvent> events) {
    final notifications = events
        .where((e) =>
            e.type == BehaviorEventType.notificationReceived ||
            e.type == BehaviorEventType.notificationOpened)
        .length;

    final duration = _getDuration(events);
    if (duration == 0) return 0.0;

    return (notifications / duration).clamp(0.0, 1.0);
  }

  double _estimateDistraction({
    required double switchRate,
    required double burstiness,
    required double fragmentation,
    required double notificationLoad,
  }) {
    // Simple weighted average (will be replaced by MLP)
    return (switchRate * 0.3 +
            burstiness * 0.2 +
            fragmentation * 0.3 +
            notificationLoad * 0.2)
        .clamp(0.0, 1.0);
  }

  double _getDuration(List<BehaviorEvent> events) {
    if (events.length < 2) return 0.0;
    return events.last.timestamp
        .difference(events.first.timestamp)
        .inSeconds
        .toDouble();
  }
}
