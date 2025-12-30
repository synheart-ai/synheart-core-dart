import 'dart:async';
import '../interfaces/feature_providers.dart';

/// Callback for window events
typedef WindowCallback = void Function(WindowType window);

/// Schedules window-based computation
class WindowScheduler {
  Timer? _timer30s;
  Timer? _timer5m;
  Timer? _timer1h;
  Timer? _timer24h;

  final WindowCallback _onWindow;

  WindowScheduler({required WindowCallback onWindow}) : _onWindow = onWindow;

  /// Start scheduling windows
  void start() {
    // 30-second window
    _timer30s = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _onWindow(WindowType.window30s),
    );

    // 5-minute window
    _timer5m = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _onWindow(WindowType.window5m),
    );

    // 1-hour window
    _timer1h = Timer.periodic(
      const Duration(hours: 1),
      (_) => _onWindow(WindowType.window1h),
    );

    // 24-hour window
    _timer24h = Timer.periodic(
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
    _timer30s?.cancel();
    _timer5m?.cancel();
    _timer1h?.cancel();
    _timer24h?.cancel();

    _timer30s = null;
    _timer5m = null;
    _timer1h = null;
    _timer24h = null;
  }
}
