import '../interfaces/feature_providers.dart';
import 'phone_collectors.dart';

/// Cache for phone window features
class PhoneCache {
  final Map<WindowType, List<_PhoneDataPoint>> _windowData = {};
  final Map<WindowType, PhoneWindowFeatures> _cachedFeatures = {};

  /// Add motion data
  void addMotionData(MotionData motion) {
    _addDataPoint(
      _PhoneDataPoint(
        timestamp: motion.timestamp,
        motionLevel: motion.energy / 3.0, // Normalize to 0-1
      ),
    );
  }

  /// Add screen state change
  void addScreenState(ScreenState state, DateTime timestamp) {
    _addDataPoint(
      _PhoneDataPoint(
        timestamp: timestamp,
        screenOn: state == ScreenState.on || state == ScreenState.unlocked,
      ),
    );
  }

  /// Add app switch event
  void addAppSwitch(DateTime timestamp) {
    _addDataPoint(_PhoneDataPoint(timestamp: timestamp, appSwitch: true));
  }

  /// Add notification event
  void addNotification(NotificationEvent event) {
    _addDataPoint(
      _PhoneDataPoint(timestamp: event.timestamp, notification: true),
    );
  }

  /// Get features for a window
  PhoneWindowFeatures? getFeatures(WindowType window) {
    return _cachedFeatures[window];
  }

  /// Add a data point and recompute features
  void _addDataPoint(_PhoneDataPoint point) {
    final now = point.timestamp;

    for (final windowType in WindowType.values) {
      final windowDuration = _getWindowDuration(windowType);
      final cutoffTime = now.subtract(windowDuration);

      // Initialize if needed
      _windowData[windowType] ??= [];

      // Add new point
      _windowData[windowType]!.add(point);

      // Remove old points
      _windowData[windowType]!.removeWhere(
        (p) => p.timestamp.isBefore(cutoffTime),
      );

      // Recompute features
      _cachedFeatures[windowType] = _computeFeatures(
        windowType,
        _windowData[windowType]!,
      );
    }
  }

  /// Compute features from data points
  PhoneWindowFeatures _computeFeatures(
    WindowType windowType,
    List<_PhoneDataPoint> data,
  ) {
    if (data.isEmpty) {
      return const PhoneWindowFeatures(
        motionLevel: 0.0,
        appSwitchRate: 0.0,
        screenOnRatio: 0.0,
        notificationRate: 0.0,
      );
    }

    // Motion level (average)
    final motionValues = data
        .where((d) => d.motionLevel != null)
        .map((d) => d.motionLevel!)
        .toList();
    final motionLevel = motionValues.isNotEmpty
        ? motionValues.reduce((a, b) => a + b) / motionValues.length
        : 0.0;

    // Screen on ratio
    final screenOnCount = data.where((d) => d.screenOn == true).length;
    final screenOnRatio = data.isNotEmpty ? screenOnCount / data.length : 0.0;

    // App switch rate (switches per minute)
    final appSwitches = data.where((d) => d.appSwitch == true).length;
    final windowMinutes = _getWindowDuration(windowType).inMinutes;
    final appSwitchRate = windowMinutes > 0 ? appSwitches / windowMinutes : 0.0;

    // Notification rate (per minute)
    final notifications = data.where((d) => d.notification == true).length;
    final notificationRate = windowMinutes > 0
        ? notifications / windowMinutes
        : 0.0;

    return PhoneWindowFeatures(
      motionLevel: motionLevel,
      appSwitchRate: appSwitchRate.clamp(0.0, 1.0),
      screenOnRatio: screenOnRatio,
      notificationRate: notificationRate.clamp(0.0, 1.0),
    );
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

/// Internal data point for phone data
class _PhoneDataPoint {
  final DateTime timestamp;
  final double? motionLevel;
  final bool? screenOn;
  final bool? appSwitch;
  final bool? notification;

  _PhoneDataPoint({
    required this.timestamp,
    this.motionLevel,
    this.screenOn,
    this.appSwitch,
    this.notification,
  });
}
