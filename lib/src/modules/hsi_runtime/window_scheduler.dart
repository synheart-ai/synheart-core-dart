import 'dart:async';
import '../interfaces/feature_providers.dart';

/// Callback for window events
typedef WindowCallback = void Function(WindowType window);

/// Schedules window-based computation
class WindowScheduler {
  Timer? _30sTimer;
  Timer? _5mTimer;
  Timer? _1hTimer;
  Timer? _24hTimer;

  final WindowCallback _onWindow;

  WindowScheduler({required WindowCallback onWindow}) : _onWindow = onWindow;

  /// Start scheduling windows
  void start() {
    // 30-second window
    _30sTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _onWindow(WindowType.window30s),
    );

    // 5-minute window
    _5mTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _onWindow(WindowType.window5m),
    );

    // 1-hour window
    _1hTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _onWindow(WindowType.window1h),
    );

    // 24-hour window
    _24hTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => _onWindow(WindowType.window24h),
    );

    // Trigger initial computation immediately
    Future.microtask(() {
      _onWindow(WindowType.window30s);
      _onWindow(WindowType.window5m);
      _onWindow(WindowType.window1h);
      _onWindow(WindowType.window24h);
    });
  }

  /// Stop scheduling
  void stop() {
    _30sTimer?.cancel();
    _5mTimer?.cancel();
    _1hTimer?.cancel();
    _24hTimer?.cancel();

    _30sTimer = null;
    _5mTimer = null;
    _1hTimer = null;
    _24hTimer = null;
  }
}
