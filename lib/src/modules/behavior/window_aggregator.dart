import '../interfaces/feature_providers.dart';
import 'behavior_events.dart';

/// Aggregates behavior events into time windows
class WindowAggregator {
  final Map<WindowType, List<BehaviorEvent>> _windows = {};

  /// Add an event to all windows
  void addEvent(BehaviorEvent event) {
    final now = event.timestamp;

    for (final windowType in WindowType.values) {
      final windowDuration = _getWindowDuration(windowType);
      final cutoffTime = now.subtract(windowDuration);

      // Initialize if needed
      _windows[windowType] ??= [];

      // Add event
      _windows[windowType]!.add(event);

      // Remove old events
      _windows[windowType]!.removeWhere(
        (e) => e.timestamp.isBefore(cutoffTime),
      );
    }
  }

  /// Get events for a window
  List<BehaviorEvent> getEvents(WindowType window) {
    return List.unmodifiable(_windows[window] ?? []);
  }

  /// Clean old windows (call periodically)
  void cleanOldWindows() {
    final now = DateTime.now();

    for (final windowType in WindowType.values) {
      final windowDuration = _getWindowDuration(windowType);
      final cutoffTime = now.subtract(windowDuration * 2); // Keep 2x window

      _windows[windowType]?.removeWhere(
        (e) => e.timestamp.isBefore(cutoffTime),
      );
    }
  }

  /// Clear all cached data
  void clear() {
    _windows.clear();
  }

  /// Get window duration
  Duration _getWindowDuration(WindowType windowType) {
    switch (windowType) {
      case WindowType.window30s:
        return const Duration(seconds: 30);
      case WindowType.window5m:
        return const Duration(minutes: 5);
      case WindowType.window1h:
        return const Duration(hours: 1);
      case WindowType.window24h:
        return const Duration(hours: 24);
    }
  }
}
