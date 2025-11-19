import 'dart:async';
import 'dart:math';

/// Motion data from accelerometer/gyroscope
class MotionData {
  final double x;
  final double y;
  final double z;
  final double energy;
  final DateTime timestamp;

  const MotionData({
    required this.x,
    required this.y,
    required this.z,
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

/// Notification event
class NotificationEvent {
  final DateTime timestamp;
  final bool opened; // true if opened, false if just received

  const NotificationEvent({
    required this.timestamp,
    required this.opened,
  });
}

/// Collects motion data from device sensors
class MotionCollector {
  final StreamController<MotionData> _controller =
      StreamController<MotionData>.broadcast();
  Timer? _timer;
  final Random _random = Random();
  double _currentMotionLevel = 0.0;

  Stream<MotionData> get motionStream => _controller.stream;

  /// Current normalized motion level (0.0 - 1.0)
  double get currentMotionLevel => _currentMotionLevel;

  Future<void> start() async {
    // Mock motion data (in production, use sensors_plus package)
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      // Simulate varying motion levels
      _currentMotionLevel += (_random.nextDouble() - 0.5) * 0.1;
      _currentMotionLevel = _currentMotionLevel.clamp(0.0, 1.0);

      final x = (_random.nextDouble() - 0.5) * 2;
      final y = (_random.nextDouble() - 0.5) * 2;
      final z = (_random.nextDouble() - 0.5) * 2;
      final energy = sqrt(x * x + y * y + z * z);

      _controller.add(MotionData(
        x: x,
        y: y,
        z: z,
        energy: energy,
        timestamp: DateTime.now(),
      ));
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
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
  Timer? _timer;
  final Random _random = Random();
  ScreenState _currentState = ScreenState.unlocked;

  Stream<ScreenState> get screenStream => _controller.stream;

  bool get isScreenOn =>
      _currentState == ScreenState.on || _currentState == ScreenState.unlocked;

  Future<void> start() async {
    // Mock screen state changes (in production, use platform channels)
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      // Randomly change screen state
      if (_random.nextDouble() < 0.3) {
        final states = ScreenState.values;
        _currentState = states[_random.nextInt(states.length)];
        _controller.add(_currentState);
      }
    });

    // Emit initial state
    _controller.add(_currentState);
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}

/// Tracks app focus and switching
class AppFocusTracker {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  Timer? _timer;
  final Random _random = Random();
  final List<String> _mockApps = ['app1', 'app2', 'app3', 'app4'];
  int _switchCount = 0;
  DateTime _lastSwitch = DateTime.now();

  Stream<String> get appSwitchStream => _controller.stream;

  /// Get app switch rate (switches per minute)
  double get switchRate {
    final elapsed = DateTime.now().difference(_lastSwitch).inMinutes;
    if (elapsed == 0) return 0.0;
    return _switchCount / elapsed;
  }

  Future<void> start() async {
    // Mock app switching (in production, use platform channels)
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
      // Randomly switch apps
      if (_random.nextDouble() < 0.4) {
        final app = _mockApps[_random.nextInt(_mockApps.length)];
        _switchCount++;
        _controller.add(app);
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}

/// Tracks notifications
class NotificationTracker {
  final StreamController<NotificationEvent> _controller =
      StreamController<NotificationEvent>.broadcast();
  Timer? _timer;
  final Random _random = Random();
  final List<NotificationEvent> _recentNotifications = [];

  Stream<NotificationEvent> get notificationStream => _controller.stream;

  /// Get notification count in last minute
  int get recentNotificationCount {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    return _recentNotifications
        .where((n) => n.timestamp.isAfter(cutoff))
        .length;
  }

  Future<void> start() async {
    // Mock notifications (in production, use platform channels)
    _timer = Timer.periodic(const Duration(seconds: 20), (timer) {
      // Randomly emit notifications
      if (_random.nextDouble() < 0.3) {
        final event = NotificationEvent(
          timestamp: DateTime.now(),
          opened: _random.nextDouble() < 0.5,
        );
        _recentNotifications.add(event);
        _controller.add(event);

        // Clean old notifications
        final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
        _recentNotifications.removeWhere((n) => n.timestamp.isBefore(cutoff));
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
