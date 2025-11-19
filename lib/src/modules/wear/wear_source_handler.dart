import 'dart:async';
import '../interfaces/feature_providers.dart';

/// Types of wear data sources
enum WearSourceType {
  appleHealth,
  googleFit,
  whoop,
  garmin,
  mock,
}

/// Raw wear sample from a data source
class WearSample {
  final DateTime timestamp;
  final double? hr;
  final double? hrvRmssd;
  final double? respRate;
  final double? motionLevel;
  final SleepStage? sleepStage;
  final List<double>? rrIntervals;

  const WearSample({
    required this.timestamp,
    this.hr,
    this.hrvRmssd,
    this.respRate,
    this.motionLevel,
    this.sleepStage,
    this.rrIntervals,
  });
}

// SleepStage is defined in feature_providers.dart - imported above

/// Abstract handler for wearable data sources
///
/// Each vendor (Apple Health, Google Fit, WHOOP, etc.) implements this interface
abstract class WearSourceHandler {
  /// Source type identifier
  WearSourceType get sourceType;

  /// Whether this source is available on the current platform
  bool get isAvailable;

  /// Initialize the data source
  Future<void> initialize();

  /// Start streaming wear samples
  Stream<WearSample> get sampleStream;

  /// Stop and cleanup
  Future<void> dispose();
}
