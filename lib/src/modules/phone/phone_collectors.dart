import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Motion data from accelerometer/gyroscope
class MotionData {
  final double x;
  final double y;
  final double z;
  final double gx; // Gyroscope x
  final double gy; // Gyroscope y
  final double gz; // Gyroscope z
  final double energy;
  final DateTime timestamp;

  const MotionData({
    required this.x,
    required this.y,
    required this.z,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.energy,
    required this.timestamp,
  });
}

/// Screen state information
enum ScreenState {
  on,
  off,
  locked,
  unlocked,
}

/// Notification event with metadata
class NotificationEvent {
  final DateTime timestamp;
  final bool opened; // true if opened, false if just received
  final String? category; // Notification category (non-content)
  final String? sourceApp; // Source app (hashed)

  const NotificationEvent({
    required this.timestamp,
    required this.opened,
    this.category,
    this.sourceApp,
  });

  /// Convert to raw structure for Research capability
  Map<String, dynamic> toRawStructure() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'opened': opened,
      'category': category,
      'sourceApp': sourceApp,
    };
  }
}

/// Collects motion data from device sensors
class MotionCollector {
  final StreamController<MotionData> _controller =
      StreamController<MotionData>.broadcast();
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  double _currentMotionLevel = 0.0;

  // Store latest gyroscope values
  double _gx = 0.0;
  double _gy = 0.0;
  double _gz = 0.0;

  Stream<MotionData> get motionStream => _controller.stream;

  /// Current normalized motion level (0.0 - 1.0)
  double get currentMotionLevel => _currentMotionLevel;

  Future<void> start() async {
    try {
      // Use real accelerometer
      _accelSubscription = accelerometerEventStream().listen(
        (event) {
          _processMotionData(event.x, event.y, event.z);
        },
        onError: (error) {
          print('[MotionCollector] Accelerometer error: $error');
          // Don't cancel - sensor might recover
        },
        cancelOnError: false, // Keep stream open even on errors
      );

      // Use real gyroscope
      _gyroSubscription = gyroscopeEventStream().listen(
        (event) {
          _gx = event.x;
          _gy = event.y;
          _gz = event.z;
        },
        onError: (error) {
          print('[MotionCollector] Gyroscope error: $error');
          // Don't cancel - sensor might recover
        },
        cancelOnError: false, // Keep stream open even on errors
      );

      print('[MotionCollector] Using real sensors');
    } catch (e) {
      // No mock fallback - throw error if sensors unavailable
      print('[MotionCollector] Sensors not available: $e');
      throw Exception('Motion sensors not available: $e');
    }
  }

  void _processMotionData(double x, double y, double z) {
    // Calculate motion level (normalize to 0-1)
    final magnitude = sqrt(x * x + y * y + z * z);
    _currentMotionLevel = (magnitude / 20.0)
        .clamp(0.0, 1.0); // Adjust divisor based on typical range

    _controller.add(MotionData(
      x: x,
      y: y,
      z: z,
      gx: _gx,
      gy: _gy,
      gz: _gz,
      energy: magnitude,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> stop() async {
    await _accelSubscription?.cancel();
    await _gyroSubscription?.cancel();
    _accelSubscription = null;
    _gyroSubscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}

/// Tracks screen state (on/off/locked/unlocked)
class ScreenStateTracker {
  final StreamController<ScreenState> _controller =
      StreamController<ScreenState>.broadcast();
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _periodicTimer; // Periodic updates to ensure continuous data points
  ScreenState _currentState = ScreenState.unlocked;

  Stream<ScreenState> get screenStream => _controller.stream;

  bool get isScreenOn =>
      _currentState == ScreenState.on || _currentState == ScreenState.unlocked;

  Future<void> start() async {
    try {
      _eventChannel = const EventChannel('screen_state');
      _subscription = _eventChannel!.receiveBroadcastStream().listen(
        (dynamic event) {
          final stateStr = event as String;
          switch (stateStr) {
            case 'on':
              _currentState = ScreenState.on;
              break;
            case 'off':
              _currentState = ScreenState.off;
              break;
            case 'unlocked':
              _currentState = ScreenState.unlocked;
              break;
            case 'locked':
              _currentState = ScreenState.locked;
              break;
          }
          _controller.add(_currentState);
        },
        onError: (error) {
          print('[ScreenStateTracker] Error: $error');
          // Don't throw - just log the error so stream stays open
          // The error might be temporary and can be resolved later
        },
        cancelOnError: false, // Keep stream open even on errors
      );

      // Get initial state
      _controller.add(_currentState);

      // Start periodic updates (every 5 seconds) to ensure continuous data points
      // This ensures screenOnRatio is calculated correctly even when screen state doesn't change
      _periodicTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _controller.add(_currentState);
      });

      print('[ScreenStateTracker] Using real screen state');
    } catch (e) {
      print('[ScreenStateTracker] Platform channel not available: $e');
      // No mock fallback - real data only
      throw Exception('Screen state platform channel not available: $e');
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}

/// Tracks app focus and switching with hashed app identifiers
class AppFocusTracker {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _subscription;
  int _switchCount = 0;
  DateTime _lastSwitch = DateTime.now();
  String? _currentApp;
  final Map<String, int> _appUsageTime = {}; // Track usage time per app
  final Map<String, DateTime> _appStartTimes = {};

  Stream<String> get appSwitchStream => _controller.stream;

  /// Get app switch rate (switches per minute)
  double get switchRate {
    final elapsed = DateTime.now().difference(_lastSwitch).inMinutes;
    if (elapsed == 0) return 0.0;
    return _switchCount / elapsed;
  }

  /// Get detailed app context (Extended/Research)
  Map<String, dynamic> getAppContext() {
    return {
      'currentApp': _currentApp,
      'appUsageTime': Map.from(_appUsageTime),
      'totalSwitches': _switchCount,
    };
  }

  /// Hash app identifier for privacy
  String _hashAppId(String appId) {
    final bytes = utf8.encode(appId);
    final hash = sha256.convert(bytes);
    return hash.toString().substring(0, 16); // Use first 16 chars of hash
  }

  Future<void> start() async {
    try {
      _eventChannel = const EventChannel('app_focus');
      _subscription = _eventChannel!.receiveBroadcastStream().listen(
        (dynamic event) {
          print(
              '[AppFocusTracker] Received event: $event (type: ${event.runtimeType})');
          if (event is! String) {
            print(
                '[AppFocusTracker] Warning: Expected String, got ${event.runtimeType}');
            return;
          }
          final appPackage = event;
          if (appPackage.isNotEmpty) {
            final hashedApp = _hashAppId(appPackage);

            // Update usage time for previous app
            if (_currentApp != null && _currentApp != hashedApp) {
              final appKey = _currentApp!;
              final elapsed = DateTime.now()
                  .difference(_appStartTimes[appKey] ?? DateTime.now());
              _appUsageTime[appKey] =
                  (_appUsageTime[appKey] ?? 0) + elapsed.inSeconds;
            }

            // Only count as switch if app actually changed
            if (_currentApp != hashedApp) {
              _currentApp = hashedApp;
              _appStartTimes[_currentApp!] = DateTime.now();
              _switchCount++;
              _lastSwitch = DateTime.now();
              print(
                  '[AppFocusTracker] App switched to: $hashedApp (total switches: $_switchCount)');
              _controller.add(hashedApp);
            }
          }
        },
        onError: (error) {
          // Only log permission errors once, not repeatedly(magnitude / 20.0)
          if (error.toString().contains('PERMISSION_DENIED')) {
            print('[AppFocusTracker] Permission not granted yet, waiting...');
          } else {
            print('[AppFocusTracker] Error: $error');
          }
          // Don't throw - just log the error so stream stays open
          // The error might be permission-related and can be resolved later
        },
        cancelOnError: false, // Keep stream open even on errors
      );

      print('[AppFocusTracker] Using real app switching');
    } catch (e) {
      print('[AppFocusTracker] Platform channel not available: $e');
      // No mock fallback - real data only
      throw Exception('App focus platform channel not available: $e');
    }
  }

  Future<void> stop() async {
    // Finalize usage time for current app
    if (_currentApp != null) {
      final appKey = _currentApp!;
      final elapsed =
          DateTime.now().difference(_appStartTimes[appKey] ?? DateTime.now());
      _appUsageTime[appKey] = (_appUsageTime[appKey] ?? 0) + elapsed.inSeconds;
    }
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}

/// Tracks notifications with metadata
class NotificationTracker {
  final StreamController<NotificationEvent> _controller =
      StreamController<NotificationEvent>.broadcast();
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _subscription;
  final List<NotificationEvent> _recentNotifications = [];
  final List<Map<String, dynamic>> _rawNotifications =
      []; // For Research capability

  Stream<NotificationEvent> get notificationStream => _controller.stream;

  /// Get notification count in last minute
  int get recentNotificationCount {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    return _recentNotifications
        .where((n) => n.timestamp.isAfter(cutoff))
        .length;
  }

  /// Get raw notification structure (Research only)
  List<Map<String, dynamic>> getRawNotifications() {
    return List.from(_rawNotifications);
  }

  Future<void> start() async {
    try {
      _eventChannel = const EventChannel('notifications');

      _subscription = _eventChannel!.receiveBroadcastStream().listen(
        (dynamic event) {
          // Parse notification event from native
          // Expected format: Map with 'timestamp', 'opened', 'category', 'sourceApp'
          if (event is Map) {
            final eventData = Map<String, dynamic>.from(event);

            try {
              final notificationEvent = NotificationEvent(
                timestamp: DateTime.parse(eventData['timestamp'] as String),
                opened: eventData['opened'] as bool? ?? false,
                category: eventData['category'] as String?,
                sourceApp: eventData['sourceApp'] as String?,
              );

              _recentNotifications.add(notificationEvent);
              _rawNotifications.add(notificationEvent.toRawStructure());
              _controller.add(notificationEvent);

              // Clean old notifications (keep last 5 minutes)
              final cutoff =
                  DateTime.now().subtract(const Duration(minutes: 5));
              _recentNotifications
                  .removeWhere((n) => n.timestamp.isBefore(cutoff));
              _rawNotifications.removeWhere((n) =>
                  DateTime.parse(n['timestamp'] as String).isBefore(cutoff));
            } catch (e) {
              print('[NotificationTracker] ❌ Error parsing notification: $e');
            }
          }
        },
        onError: (error) {
          print('[NotificationTracker] ❌ Stream error: $error');
          // Don't throw - just log the error so stream stays open
          // The error might be permission-related and can be resolved later
        },
        cancelOnError: false, // Keep stream open even on errors
      );

      print(
          '[NotificationTracker] ✅ Stream listener attached, notification tracking active');
    } catch (e, stackTrace) {
      print('[NotificationTracker] ❌ Platform channel not available: $e');
      print('[NotificationTracker] Stack trace: $stackTrace');
      // No mock fallback - real data only
      throw Exception('Notification platform channel not available: $e');
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
