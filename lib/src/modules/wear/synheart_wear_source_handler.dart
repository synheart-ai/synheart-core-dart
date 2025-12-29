import 'dart:async';
import 'package:synheart_wear/synheart_wear.dart' as wear;
import 'wear_source_handler.dart';

/// WearSourceHandler implementation using synheart_wear package
///
/// This adapter bridges the synheart_wear SDK to the Core SDK's WearModule.
/// It supports all devices that synheart_wear supports:
/// - Apple Watch (via HealthKit)
/// - Fitbit (via REST API)
/// - Garmin, Whoop, Samsung (when available)
///
/// See: https://pub.dev/packages/synheart_wear
class SynheartWearSourceHandler implements WearSourceHandler {
  wear.SynheartWear? _synheartWear;
  final wear.SynheartWearConfig? _config;

  StreamController<WearSample>? _controller;
  StreamSubscription<wear.WearMetrics>? _hrSubscription;
  StreamSubscription<wear.WearMetrics>? _hrvSubscription;

  bool _isInitialized = false;

  SynheartWearSourceHandler({wear.SynheartWearConfig? config})
    : _config = config;

  @override
  WearSourceType get sourceType {
    // Determine source type from config if available
    if (_config?.enabledAdapters.contains(wear.DeviceAdapter.appleHealthKit) ==
        true) {
      return WearSourceType.appleHealth;
    }
    if (_config?.enabledAdapters.contains(wear.DeviceAdapter.fitbit) == true) {
      return WearSourceType.whoop; // Using whoop as placeholder for Fitbit
    }
    // Default to Apple Health if no specific adapter configured
    return WearSourceType.appleHealth;
  }

  @override
  bool get isAvailable {
    // synheart_wear handles platform availability internally
    // We assume it's available if the package is imported
    return true;
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    // Initialize synheart_wear SDK
    _synheartWear = wear.SynheartWear(
      config:
          _config ??
          const wear.SynheartWearConfig(
            enabledAdapters: {wear.DeviceAdapter.appleHealthKit},
            enableLocalCaching: true,
            enableEncryption: true,
            streamInterval: Duration(seconds: 1),
          ),
    );

    await _synheartWear!.initialize();

    // Create stream controller
    _controller = StreamController<WearSample>.broadcast();

    // Start streaming data
    _startStreaming();

    _isInitialized = true;
  }

  void _startStreaming() {
    if (_synheartWear == null || _controller == null) {
      return;
    }

    // Stream HR data (every 1 second)
    _hrSubscription = _synheartWear!
        .streamHR(interval: const Duration(seconds: 1))
        .listen(
          (wearMetrics) {
            _emitSample(wearMetrics);
          },
          onError: (error) {
            _controller?.addError(error);
          },
        );

    // Stream HRV data (every 5 seconds for better accuracy)
    _hrvSubscription = _synheartWear!
        .streamHRV(windowSize: const Duration(seconds: 5))
        .listen(
          (wearMetrics) {
            _emitSample(wearMetrics);
          },
          onError: (error) {
            _controller?.addError(error);
          },
        );
  }

  void _emitSample(wear.WearMetrics wearMetrics) {
    if (_controller == null || _controller!.isClosed) {
      return;
    }

    // Convert WearMetrics to WearSample
    final hr = wearMetrics.getMetric(wear.MetricType.hr)?.toDouble();
    final hrvRmssd = wearMetrics
        .getMetric(wear.MetricType.hrvRmssd)
        ?.toDouble();
    final hrvSdnn = wearMetrics.getMetric(wear.MetricType.hrvSdnn)?.toDouble();

    // Use RMSSD if available, otherwise SDNN
    final hrv = hrvRmssd ?? hrvSdnn;

    // Get RR intervals if available
    final rrIntervals = wearMetrics.rrIntervalsMs;

    // Get steps for motion estimation (rough proxy)
    final steps =
        wearMetrics.getMetric(wear.MetricType.steps)?.toDouble() ?? 0.0;
    final motionLevel = _estimateMotionFromSteps(steps);

    final sample = WearSample(
      timestamp:
          DateTime.now(), // Use current time, or extract from metrics if available
      hr: hr,
      hrvRmssd: hrv,
      respRate: null, // Not provided by synheart_wear yet
      motionLevel: motionLevel,
      sleepStage: null, // Not provided by synheart_wear yet
      rrIntervals: rrIntervals,
    );

    _controller!.add(sample);
  }

  /// Estimate motion level from steps (rough approximation)
  /// This is a placeholder until synheart_wear provides direct motion data
  double _estimateMotionFromSteps(double steps) {
    // Normalize steps to 0-1 range (assuming 10000 steps = max activity)
    return (steps / 10000.0).clamp(0.0, 1.0);
  }

  @override
  Stream<WearSample> get sampleStream {
    if (_controller == null) {
      throw StateError(
        'SynheartWearSourceHandler not initialized. Call initialize() first.',
      );
    }
    return _controller!.stream;
  }

  @override
  Future<void> dispose() async {
    await _hrSubscription?.cancel();
    await _hrvSubscription?.cancel();

    // Note: synheart_wear may not have a dispose() method
    // The SDK handles cleanup internally when streams are cancelled
    _synheartWear = null;

    await _controller?.close();
    _isInitialized = false;
  }
}
