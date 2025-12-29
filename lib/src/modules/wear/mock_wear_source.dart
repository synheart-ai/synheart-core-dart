import 'dart:async';
import 'dart:math';
import 'wear_source_handler.dart';
import '../interfaces/feature_providers.dart';

/// Mock wearable data source for testing and development
class MockWearSourceHandler implements WearSourceHandler {
  final StreamController<WearSample> _controller =
      StreamController<WearSample>.broadcast();
  Timer? _timer;
  final Random _random = Random();

  // Simulate realistic HR/HRV patterns
  final double _baseHr = 70.0;
  final double _baseHrv = 50.0;

  @override
  WearSourceType get sourceType => WearSourceType.mock;

  @override
  bool get isAvailable => true;

  @override
  Future<void> initialize() async {
    // Mock initialization - no setup needed
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Stream<WearSample> get sampleStream {
    // Start emitting mock data when first listener subscribes
    if (!_controller.hasListener && _timer == null) {
      _startMockData();
    }
    return _controller.stream;
  }

  void _startMockData() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_controller.hasListener) {
        timer.cancel();
        _timer = null;
        return;
      }

      // Generate realistic mock data
      // Simulate circadian rhythm (HR increases during day, decreases at night)
      final hourOfDay = DateTime.now().hour;
      final circadianOffset = sin((hourOfDay - 6) * pi / 12) * 10;

      // Add some random variation
      final hrVariation = (_random.nextDouble() - 0.5) * 10;
      final hr = (_baseHr + circadianOffset + hrVariation).clamp(50.0, 120.0);

      // HRV inversely related to HR (higher HR = lower HRV)
      final hrvVariation = (_random.nextDouble() - 0.5) * 15;
      final hrv = (_baseHrv - (circadianOffset / 2) + hrvVariation).clamp(20.0, 100.0);

      // Generate realistic RR intervals (around 800-1000ms)
      final rrIntervals = List.generate(
        10,
        (i) => 60000 / hr + (_random.nextDouble() - 0.5) * 50,
      );

      // Motion level (lower at night)
      final motionLevel = hourOfDay >= 22 || hourOfDay <= 6
          ? _random.nextDouble() * 0.2
          : _random.nextDouble() * 0.8;

      // Sleep stage (only during sleep hours)
      SleepStage? sleepStage;
      if (hourOfDay >= 22 || hourOfDay <= 6) {
        final sleepStages = [
          SleepStage.light,
          SleepStage.deep,
          SleepStage.rem,
        ];
        sleepStage = sleepStages[_random.nextInt(sleepStages.length)];
      }

      // Respiration rate (12-20 breaths per minute)
      final respRate = 15.0 + (_random.nextDouble() - 0.5) * 4;

      _controller.add(WearSample(
        timestamp: DateTime.now(),
        hr: hr,
        hrvRmssd: hrv,
        respRate: respRate,
        motionLevel: motionLevel,
        sleepStage: sleepStage,
        rrIntervals: rrIntervals,
      ));
    });
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _controller.close();
  }
}
