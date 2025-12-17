import '../interfaces/feature_providers.dart';
import 'phone_collectors.dart';

/// Cache for phone window features
class PhoneCache {
  final Map<WindowType, List<_PhoneDataPoint>> _windowData = {};
  final Map<WindowType, PhoneWindowFeatures> _cachedFeatures = {};

  /// Add motion data
  void addMotionData(MotionData motion) {
    _addDataPoint(_PhoneDataPoint(
      timestamp: motion.timestamp,
      motionLevel:
          motion.energy / 20.0, // Normalize to 0-1 (match MotionCollector)
      motionVector: [motion.x, motion.y, motion.z],
      gyroscopeVector: [motion.gx, motion.gy, motion.gz],
    ));
  }

  /// Add screen state change
  void addScreenState(ScreenState state, DateTime timestamp) {
    _addDataPoint(_PhoneDataPoint(
      timestamp: timestamp,
      screenOn: state == ScreenState.on || state == ScreenState.unlocked,
      screenState: state,
    ));
  }

  /// Add app switch event
  void addAppSwitch(DateTime timestamp) {
    // print('[PhoneCache] Adding app switch at ${timestamp.toIso8601String()}');
    _addDataPoint(_PhoneDataPoint(
      timestamp: timestamp,
      appSwitch: true,
    ));
    // Debug: Check window30s data after adding
    final window30sData = _windowData[WindowType.window30s] ?? [];
    // ignore: unused_local_variable
    final appSwitchCount =
        window30sData.where((d) => d.appSwitch == true).length;
    // print('[PhoneCache] Total app switches in window30s: $appSwitchCount');
  }

  /// Add notification event
  void addNotification(NotificationEvent event) {
    _addDataPoint(_PhoneDataPoint(
      timestamp: event.timestamp,
      notification: true,
    ));
  }

  /// Get features for a window
  PhoneWindowFeatures? getFeatures(WindowType window) {
    return _cachedFeatures[window];
  }

  /// Add a data point and recompute features
  void _addDataPoint(_PhoneDataPoint point) {
    // Use current time, not point timestamp, to calculate cutoff
    // This ensures old events are properly removed based on actual elapsed time
    final now = DateTime.now();

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
    // Filter data points to ensure they're within the window
    // This is a safety check in case old points weren't removed properly
    final now = DateTime.now();
    final windowDuration = _getWindowDuration(windowType);
    final cutoffTime = now.subtract(windowDuration);
    final filteredData =
        data.where((point) => point.timestamp.isAfter(cutoffTime)).toList();

    if (filteredData.isEmpty) {
      return PhoneWindowFeatures(
        motionLevel: 0.0,
        motionVector: [0.0, 0.0, 0.0],
        gyroscopeVector: [0.0, 0.0, 0.0],
        activityCode: ActivityCode.stationary,
        screenState: ScreenState.off,
        appSwitchRate: 0.0,
        screenOnRatio: 0.0,
        notificationRate: 0.0,
        idleRatio: 1.0,
      );
    }

    // Use filtered data for all calculations
    final validData = filteredData;

    // Motion level (average)
    final motionValues = validData
        .where((d) => d.motionLevel != null)
        .map((d) => d.motionLevel!)
        .toList();
    final motionLevel = motionValues.isNotEmpty
        ? motionValues.reduce((a, b) => a + b) / motionValues.length
        : 0.0;

    // Motion vector (average of recent vectors)
    final motionVectors = validData
        .where((d) => d.motionVector != null)
        .map((d) => d.motionVector!)
        .toList();
    List<double> motionVector = [0.0, 0.0, 0.0];
    if (motionVectors.isNotEmpty) {
      motionVector = [
        motionVectors.map((v) => v[0]).reduce((a, b) => a + b) /
            motionVectors.length,
        motionVectors.map((v) => v[1]).reduce((a, b) => a + b) /
            motionVectors.length,
        motionVectors.map((v) => v[2]).reduce((a, b) => a + b) /
            motionVectors.length,
      ];
    }

    // Gyroscope vector (average of recent vectors)
    final gyroscopeVectors = validData
        .where((d) => d.gyroscopeVector != null)
        .map((d) => d.gyroscopeVector!)
        .toList();
    List<double> gyroscopeVector = [0.0, 0.0, 0.0];
    if (gyroscopeVectors.isNotEmpty) {
      gyroscopeVector = [
        gyroscopeVectors.map((v) => v[0]).reduce((a, b) => a + b) /
            gyroscopeVectors.length,
        gyroscopeVectors.map((v) => v[1]).reduce((a, b) => a + b) /
            gyroscopeVectors.length,
        gyroscopeVectors.map((v) => v[2]).reduce((a, b) => a + b) /
            gyroscopeVectors.length,
      ];
    }

    // Activity classification based on motion level (normalized, accounts for gravity)
    // motionLevel is already normalized 0-1, where ~0.5 is stationary (gravity baseline)
    final activityCode = _classifyActivity(motionLevel);

    // Get window duration for time-based calculations (already calculated above, but keep for clarity)
    final windowSeconds = windowDuration.inSeconds.toDouble();
    final windowMinutes = windowSeconds / 60.0;

    // Screen on ratio: Calculate based on time intervals, not data point counts
    // Screen state changes are rare events, so we calculate time spent in each state
    final screenStatePoints = validData
        .where((d) => d.screenState != null)
        .map((d) => MapEntry(d.timestamp, d.screenState!))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    double screenOnRatio = 0.0;
    ScreenState? screenState;

    if (screenStatePoints.isEmpty) {
      // No screen state data - assume screen is off
      screenOnRatio = 0.0;
      screenState = ScreenState.off;
    } else {
      // Get most recent screen state
      screenState = screenStatePoints.last.value;

      // Calculate time spent with screen on
      // If only one state point, assume that state for entire window
      if (screenStatePoints.length == 1) {
        final state = screenStatePoints.first.value;
        final isOn = state == ScreenState.on || state == ScreenState.unlocked;
        screenOnRatio = isOn ? 1.0 : 0.0;
      } else {
        // Calculate time intervals between state changes
        double screenOnTime = 0.0;
        final windowEnd = DateTime.now();
        final windowStart = windowEnd.subtract(windowDuration);

        for (int i = 0; i < screenStatePoints.length; i++) {
          final currentState = screenStatePoints[i].value;
          final isOn = currentState == ScreenState.on ||
              currentState == ScreenState.unlocked;
          final stateStart = screenStatePoints[i].key;
          final stateEnd = i < screenStatePoints.length - 1
              ? screenStatePoints[i + 1].key
              : windowEnd;

          // Only count time if state is within window
          if (stateStart.isBefore(windowEnd) && stateEnd.isAfter(windowStart)) {
            final intervalStart =
                stateStart.isAfter(windowStart) ? stateStart : windowStart;
            final intervalEnd =
                stateEnd.isBefore(windowEnd) ? stateEnd : windowEnd;
            final intervalDuration =
                intervalEnd.difference(intervalStart).inSeconds.toDouble();

            if (isOn) {
              screenOnTime += intervalDuration;
            }
          }
        }

        screenOnRatio = windowSeconds > 0
            ? (screenOnTime / windowSeconds).clamp(0.0, 1.0)
            : 0.0;
      }
    }

    // App switch rate (switches per minute) - no clamping to show actual rates
    final appSwitches = validData.where((d) => d.appSwitch == true).length;
    final appSwitchRate = windowMinutes > 0 ? appSwitches / windowMinutes : 0.0;

    // Debug: Log app switch calculation for window30s
    if (windowType == WindowType.window30s) {
      final totalDataPoints = validData.length;
      final appSwitchDataPoints =
          validData.where((d) => d.appSwitch == true).toList();
      if (appSwitches > 0 || totalDataPoints > 100) {
        // print(
        //     '[PhoneCache] window30s: totalData=$totalDataPoints, appSwitches=$appSwitches, windowMinutes=$windowMinutes, rate=$appSwitchRate');
        if (appSwitchDataPoints.isNotEmpty) {
          // print(
          //     '[PhoneCache] App switch timestamps: ${appSwitchDataPoints.map((d) => d.timestamp.toIso8601String()).join(", ")}');
          // print(
          //     '[PhoneCache] Cutoff time: ${cutoffTime.toIso8601String()}, Now: ${now.toIso8601String()}');
        }
      }
    }

    // Notification rate (per minute) - no clamping to show actual rates
    final notifications = validData.where((d) => d.notification == true).length;
    final notificationRate =
        windowMinutes > 0 ? notifications / windowMinutes : 0.0;

    // Idle detection: calculate ratio of time with low motion
    // Motion level ~0.5 is stationary (gravity baseline), so idle threshold should be around 0.6
    final idleThreshold =
        0.6; // Motion level below this is considered idle (stationary)
    final idleCount = motionValues.where((v) => v < idleThreshold).length;
    final idleRatio =
        motionValues.isNotEmpty ? idleCount / motionValues.length : 1.0;

    return PhoneWindowFeatures(
      motionLevel: motionLevel,
      motionVector: motionVector,
      gyroscopeVector: gyroscopeVector,
      activityCode: activityCode,
      screenState: screenState,
      appSwitchRate: appSwitchRate, // No clamping - show actual rate per minute
      screenOnRatio: screenOnRatio,
      notificationRate:
          notificationRate, // No clamping - show actual rate per minute
      idleRatio: idleRatio,
    );
  }

  /// Classify activity based on normalized motion level
  /// motionLevel is normalized 0-1 where:
  /// - ~0.5 = stationary (gravity baseline ~9.8 m/s² / 20.0)
  /// - 0.5-0.6 = walking (slight movement above gravity)
  /// - 0.6-0.75 = running (moderate movement)
  /// - >0.75 = in vehicle (significant movement/vibration)
  ActivityCode _classifyActivity(double motionLevel) {
    // Account for gravity baseline (~0.5 when normalized)
    final adjustedLevel = motionLevel - 0.5;

    if (adjustedLevel < -0.1) {
      // Very low motion (below gravity baseline - unlikely but possible)
      return ActivityCode.stationary;
    } else if (adjustedLevel < 0.1) {
      // Near gravity baseline - stationary
      return ActivityCode.stationary;
    } else if (adjustedLevel < 0.25) {
      // Slight movement above gravity - walking
      return ActivityCode.walking;
    } else if (adjustedLevel < 0.5) {
      // Moderate movement - running
      return ActivityCode.running;
    } else {
      // Significant movement/vibration - in vehicle
      return ActivityCode.inVehicle;
    }
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
  final List<double>? motionVector;
  final List<double>? gyroscopeVector;
  final bool? screenOn;
  final ScreenState? screenState;
  final bool? appSwitch;
  final bool? notification;

  _PhoneDataPoint({
    required this.timestamp,
    this.motionLevel,
    this.motionVector,
    this.gyroscopeVector,
    this.screenOn,
    this.screenState,
    this.appSwitch,
    this.notification,
  });
}
