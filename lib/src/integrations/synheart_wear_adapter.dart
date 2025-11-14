/// Optional integration adapter for synheart_wear package
///
/// To use this adapter:
/// 1. Add synheart_wear to your pubspec.yaml:
///    dependencies:
///      synheart_wear: ^0.1.2
///
/// 2. Import this file and synheart_wear in your app:
///    import 'package:hsi_flutter/hsi_flutter.dart';
///    import 'package:synheart_wear/synheart_wear.dart';
///    import 'package:hsi_flutter/src/integrations/synheart_wear_adapter.dart';
///
/// 3. Create the adapter and pass it to HSI:
///    final wearAdapter = SynheartWearDataSource();
///    final hsi = HSI.shared;
///    await hsi.configure(
///      appKey: 'YOUR_KEY',
///      biosignalSource: wearAdapter,
///    );
///
/// Note: This file is commented out by default since synheart_wear is optional.
/// Uncomment the code below if you have synheart_wear installed.

/*
import 'dart:async';
import 'package:synheart_wear/synheart_wear.dart' as wear;
import '../core/data_sources.dart';
import '../core/ingestion.dart';

/// Adapter that bridges synheart_wear SDK to HSI's BiosignalDataSource interface
class SynheartWearDataSource implements BiosignalDataSource {
  late final wear.SynheartWear _synheartWear;
  final StreamController<Biosignals> _controller =
      StreamController<Biosignals>.broadcast();

  StreamSubscription<wear.WearMetrics>? _hrSubscription;
  StreamSubscription<wear.WearMetrics>? _hrvSubscription;
  wear.WearMetrics? _latestMetrics;

  final wear.SynheartWearConfig? config;

  SynheartWearDataSource({this.config});

  @override
  Future<void> initialize() async {
    // Initialize synheart_wear SDK
    _synheartWear = wear.SynheartWear(
      config: config ??
          const wear.SynheartWearConfig(
            enabledAdapters: {
              wear.DeviceAdapter.appleHealthKit,
            },
            enableLocalCaching: true,
            enableEncryption: true,
            streamInterval: Duration(seconds: 1),
          ),
    );

    await _synheartWear.initialize();

    // Start streaming
    _startStreaming();
  }

  void _startStreaming() {
    // Stream HR data (every 1 second)
    _hrSubscription = _synheartWear
        .streamHR(interval: const Duration(seconds: 1))
        .listen(
      (wearMetrics) {
        _latestMetrics = wearMetrics;
        _emitBiosignals(wearMetrics);
      },
      onError: (error) {
        _controller.addError(error);
      },
    );

    // Stream HRV data (every 5 seconds for better accuracy)
    _hrvSubscription = _synheartWear
        .streamHRV(windowSize: const Duration(seconds: 5))
        .listen(
      (wearMetrics) {
        _latestMetrics = wearMetrics;
        _emitBiosignals(wearMetrics);
      },
      onError: (error) {
        _controller.addError(error);
      },
    );
  }

  void _emitBiosignals(wear.WearMetrics wearMetrics) {
    // Convert WearMetrics to Biosignals
    final biosignals = Biosignals(
      heartRate: wearMetrics.getMetric(wear.MetricType.hr)?.toDouble(),
      hrv: wearMetrics.getMetric(wear.MetricType.hrvRmssd)?.toDouble() ??
          wearMetrics.getMetric(wear.MetricType.hrvSdnn)?.toDouble(),
      rrIntervals: wearMetrics.rrIntervalsMs,
      respirationRate: null, // Not provided by wear SDK yet
      motion: null, // TODO: Add motion data mapping if available
      sleepStage: null, // TODO: Add sleep stage mapping if available
    );

    _controller.add(biosignals);
  }

  @override
  Stream<Biosignals> get biosignalStream => _controller.stream;

  @override
  Future<void> dispose() async {
    await _hrSubscription?.cancel();
    await _hrvSubscription?.cancel();
    _synheartWear.dispose();
    await _controller.close();
  }
}
*/
