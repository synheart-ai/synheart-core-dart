import '../interfaces/feature_providers.dart';
import 'phone_collectors.dart';

/// Cache for phone raw data points
///
/// RFC-CORE-0007 compliant: buffers raw data only.
/// Feature computation is delegated to Flux.
class PhoneCache {
  final Map<WindowType, List<PhoneDataPoint>> _windowData = {};

  /// Add motion data
  void addMotionData(MotionData motion) {
    _addDataPoint(
      PhoneDataPoint(
        timestamp: motion.timestamp,
        motionLevel: motion.energy / 3.0,
      ),
    );
  }

  /// Add screen state change
  void addScreenState(ScreenState state, DateTime timestamp) {
    _addDataPoint(
      PhoneDataPoint(
        timestamp: timestamp,
        screenOn: state == ScreenState.on || state == ScreenState.unlocked,
      ),
    );
  }

  /// Add app switch event
  void addAppSwitch(DateTime timestamp) {
    _addDataPoint(PhoneDataPoint(timestamp: timestamp, appSwitch: true));
  }

  /// Add notification event
  void addNotification(NotificationEvent event) {
    _addDataPoint(
      PhoneDataPoint(timestamp: event.timestamp, notification: true),
    );
  }

  /// Get raw data points for a window
  List<PhoneDataPoint> getDataPoints(WindowType window) {
    return List.unmodifiable(_windowData[window] ?? []);
  }

  /// Add a data point to all windows
  void _addDataPoint(PhoneDataPoint point) {
    final now = point.timestamp;

    for (final windowType in WindowType.values) {
      final windowDuration = _getWindowDuration(windowType);
      final cutoffTime = now.subtract(windowDuration);

      _windowData[windowType] ??= [];
      _windowData[windowType]!.add(point);
      _windowData[windowType]!.removeWhere(
        (p) => p.timestamp.isBefore(cutoffTime),
      );
    }
  }

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

  /// Clear all cached data
  void clear() {
    _windowData.clear();
  }
}

/// Data point for phone data
class PhoneDataPoint {
  final DateTime timestamp;
  final double? motionLevel;
  final bool? screenOn;
  final bool? appSwitch;
  final bool? notification;

  const PhoneDataPoint({
    required this.timestamp,
    this.motionLevel,
    this.screenOn,
    this.appSwitch,
    this.notification,
  });
}
