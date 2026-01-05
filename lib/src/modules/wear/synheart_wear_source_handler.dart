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
    // If already initialized and SDK exists, skip
    if (_isInitialized && _synheartWear != null) {
      return;
    }

    // If SDK was disposed (e.g., after stop()), we need to recreate it
    if (_synheartWear == null) {
      // Initialize synheart_wear SDK with config or default
      _synheartWear = wear.SynheartWear(
        config:
            _config ??
            wear.SynheartWearConfig.withAdapters({
              wear.DeviceAdapter.appleHealthKit,
            }),
      );

      // Step 1: Request permissions explicitly (recommended pattern from README)
      // This allows providing a custom reason for better UX
      try {
        final permissionResult = await _synheartWear!.requestPermissions(
          permissions: {
            wear.PermissionType.heartRate,
            wear.PermissionType.heartRateVariability,
            wear.PermissionType.steps,
            wear.PermissionType.calories,
          },
          reason:
              'Synheart Core needs access to your health data to provide personalized insights.',
        );

        // Step 2: Check if permissions were granted before initializing
        if (permissionResult.values.any(
          (s) => s == wear.ConsentStatus.granted,
        )) {
          // Step 3: Initialize SDK (validates permissions and data availability)
          await _synheartWear!.initialize();
        } else {
          // Permissions were denied - throw error
          throw Exception(
            'Health data permissions were not granted. Please grant permissions to use wearable features.',
          );
        }
      } on wear.SynheartWearError {
        // Re-throw synheart_wear errors as-is
        rethrow;
      } catch (e) {
        // Wrap other errors
        throw Exception('Failed to initialize synheart_wear: $e');
      }
    }

    // Create stream controller if it doesn't exist
    _controller ??= StreamController<WearSample>.broadcast();

    // Start streaming data (only if not already streaming)
    if (_hrSubscription == null && _hrvSubscription == null) {
      _startStreaming();
    }

    _isInitialized = true;
  }

  void _startStreaming() {
    if (_synheartWear == null || _controller == null) {
      return;
    }

    // Stream HR data - use config interval or SDK default (2 seconds)
    final hrInterval = _config?.streamInterval ?? const Duration(seconds: 2);
    _hrSubscription = _synheartWear!
        .streamHR(interval: hrInterval)
        .listen(
          (wearMetrics) {
            _emitSample(wearMetrics);
          },
          onError: (error) {
            _controller?.addError(error);
          },
        );

    // Stream HRV data - use config window size or SDK default (5 seconds)
    final hrvWindowSize = _config?.hrvWindowSize ?? const Duration(seconds: 5);
    _hrvSubscription = _synheartWear!
        .streamHRV(windowSize: hrvWindowSize)
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
      timestamp: wearMetrics.timestamp, // Use timestamp from metrics
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
  Future<void> stop() async {
    // Cancel subscriptions to stop receiving data
    await _hrSubscription?.cancel();
    _hrSubscription = null;
    await _hrvSubscription?.cancel();
    _hrvSubscription = null;

    // Explicitly dispose synheart_wear SDK to stop its internal timers
    // This ensures streaming stops immediately, not waiting for timer checks
    // The SDK will be re-initialized if needed when restarting
    _synheartWear?.dispose();
    _synheartWear = null;

    // Note: _isInitialized remains true to allow checking if re-init is needed
    // The controller stays open for potential restart
  }

  @override
  Future<void> dispose() async {
    // Stop streaming first
    await stop();

    // Close the stream controller
    await _controller?.close();
    _controller = null;
    _isInitialized = false;
  }
}
