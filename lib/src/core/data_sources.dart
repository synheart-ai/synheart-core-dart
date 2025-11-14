import 'dart:async';
import 'ingestion.dart';

/// Abstract interface for biosignal data sources
///
/// This allows HSI to work with any data source (wearables, mock data, etc.)
/// without tight coupling to specific SDK implementations.
abstract class BiosignalDataSource {
  /// Initialize the data source
  Future<void> initialize();

  /// Start streaming biosignal data
  Stream<Biosignals> get biosignalStream;

  /// Stop and cleanup
  Future<void> dispose();
}

/// Mock data source for testing and development
///
/// Provides simulated biosignal data when no real wearable is connected.
class MockBiosignalDataSource implements BiosignalDataSource {
  final StreamController<Biosignals> _controller =
      StreamController<Biosignals>.broadcast();
  Timer? _timer;

  @override
  Future<void> initialize() async {
    // Mock initialization - no setup needed
  }

  @override
  Stream<Biosignals> get biosignalStream {
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

      // Emit mock biosignals
      _controller.add(Biosignals(
        heartRate: 70.0 + (DateTime.now().millisecond % 20),
        hrv: 50.0,
        rrIntervals: [800.0, 850.0, 820.0, 810.0],
        respirationRate: 15.0,
      ));
    });
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }
}

/// Abstract interface for behavioral signal data sources
abstract class BehavioralDataSource {
  /// Initialize the data source
  Future<void> initialize();

  /// Start streaming behavioral data
  Stream<BehavioralSignals> get behavioralStream;

  /// Stop and cleanup
  Future<void> dispose();
}

/// Mock behavioral data source
class MockBehavioralDataSource implements BehavioralDataSource {
  final StreamController<BehavioralSignals> _controller =
      StreamController<BehavioralSignals>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  Stream<BehavioralSignals> get behavioralStream {
    // Return a stream that emits placeholder data
    return Stream.periodic(const Duration(seconds: 2), (_) {
      return BehavioralSignals(
        typingCadence: 0.4,
        scrollVelocity: 0.3,
        idleGaps: [1.5],
      );
    });
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

/// Abstract interface for context signal data sources
abstract class ContextDataSource {
  /// Initialize the data source
  Future<void> initialize();

  /// Start streaming context data
  Stream<ContextSignals> get contextStream;

  /// Stop and cleanup
  Future<void> dispose();
}

/// Mock context data source
class MockContextDataSource implements ContextDataSource {
  final StreamController<ContextSignals> _controller =
      StreamController<ContextSignals>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  Stream<ContextSignals> get contextStream {
    return Stream.periodic(const Duration(seconds: 3), (_) {
      return ContextSignals(
        deviceState: DeviceState(
          foreground: true,
          screenOn: true,
          focusMode: 'work',
        ),
      );
    });
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
