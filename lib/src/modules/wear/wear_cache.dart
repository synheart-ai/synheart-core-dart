import 'dart:math';

import '../interfaces/feature_providers.dart';
import 'wear_source_handler.dart';

/// Cache for wear window features
///
/// Maintains aggregated biosignal features for different time windows
class WearCache {
  final Map<WindowType, List<WearSample>> _windowSamples = {};
  final Map<WindowType, WearWindowFeatures> _cachedFeatures = {};

  /// Add a new sample to the cache
  void addSample(WearSample sample) {
    final now = sample.timestamp;

    // Add to each window type
    for (final windowType in WindowType.values) {
      final windowDuration = _getWindowDuration(windowType);
      final cutoffTime = now.subtract(windowDuration);

      // Initialize if needed
      _windowSamples[windowType] ??= [];

      // Add new sample
      _windowSamples[windowType]!.add(sample);

      // Remove old samples
      _windowSamples[windowType]!.removeWhere(
        (s) => s.timestamp.isBefore(cutoffTime),
      );

      // Recompute features for this window
      _cachedFeatures[windowType] = _computeFeatures(
        windowType,
        _windowSamples[windowType]!,
      );
    }
  }

  /// Get features for a specific window
  WearWindowFeatures? getFeatures(WindowType window) {
    return _cachedFeatures[window];
  }

  /// Clear old data
  void clearOldData() {
    final now = DateTime.now();

    for (final windowType in WindowType.values) {
      final windowDuration = _getWindowDuration(windowType);
      final cutoffTime = now.subtract(windowDuration * 2); // Keep 2x window

      _windowSamples[windowType]?.removeWhere(
        (s) => s.timestamp.isBefore(cutoffTime),
      );
    }
  }

  /// Compute aggregated features from samples
  WearWindowFeatures _computeFeatures(
    WindowType windowType,
    List<WearSample> samples,
  ) {
    if (samples.isEmpty) {
      return WearWindowFeatures(windowDuration: _getWindowDuration(windowType));
    }

    // Extract HR values
    final hrValues = samples
        .where((s) => s.hr != null)
        .map((s) => s.hr!)
        .toList();

    // Flatten RR intervals across the window (best source of HRV features)
    final rrIntervals = samples
        .where((s) => s.rrIntervals != null && s.rrIntervals!.isNotEmpty)
        .expand((s) => s.rrIntervals!)
        .toList();

    // Fallback HRV values (may be vendor-provided RMSSD or SDNN; treat as best-effort)
    final hrvFallbackValues = samples
        .where((s) => s.hrvRmssd != null)
        .map((s) => s.hrvRmssd!)
        .toList();

    // Extract motion values
    final motionValues = samples
        .where((s) => s.motionLevel != null)
        .map((s) => s.motionLevel!)
        .toList();

    // Extract respiration values
    final respValues = samples
        .where((s) => s.respRate != null)
        .map((s) => s.respRate!)
        .toList();

    // Get most recent sleep stage
    final sleepStages = samples
        .where((s) => s.sleepStage != null)
        .map((s) => s.sleepStage!)
        .toList();
    final sleepStage = sleepStages.isNotEmpty ? sleepStages.last : null;

    // Compute RR-derived HRV metrics if available
    final rrMean = rrIntervals.isNotEmpty ? _mean(rrIntervals) : null;
    final rrSdnn = rrIntervals.length >= 2 ? _sdnn(rrIntervals) : null;
    final rrRmssd = rrIntervals.length >= 2 ? _rmssd(rrIntervals) : null;
    final rrPnn50 = rrIntervals.length >= 2 ? _pnn50(rrIntervals) : null;

    return WearWindowFeatures(
      windowDuration: _getWindowDuration(windowType),
      hrAverage: hrValues.isNotEmpty
          ? hrValues.reduce((a, b) => a + b) / hrValues.length
          : null,
      hrMin: hrValues.isNotEmpty
          ? hrValues.reduce((a, b) => a < b ? a : b)
          : null,
      hrMax: hrValues.isNotEmpty
          ? hrValues.reduce((a, b) => a > b ? a : b)
          : null,
      // Prefer RR-derived RMSSD; fallback to vendor-provided value
      hrvRmssd:
          rrRmssd ??
          (hrvFallbackValues.isNotEmpty
              ? hrvFallbackValues.reduce((a, b) => a + b) /
                    hrvFallbackValues.length
              : null),
      hrvSdnn: rrSdnn,
      pnn50: rrPnn50,
      meanRrMs: rrMean,
      motionIndex: motionValues.isNotEmpty
          ? motionValues.reduce((a, b) => a + b) / motionValues.length
          : null,
      sleepStage: sleepStage,
      respRate: respValues.isNotEmpty
          ? respValues.reduce((a, b) => a + b) / respValues.length
          : null,
    );
  }

  double _mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

  double _sdnn(List<double> rrIntervalsMs) {
    final mean = _mean(rrIntervalsMs);
    var sumSq = 0.0;
    for (final x in rrIntervalsMs) {
      final d = x - mean;
      sumSq += d * d;
    }
    return sqrt(sumSq / rrIntervalsMs.length);
  }

  double _rmssd(List<double> rrIntervalsMs) {
    var sumSq = 0.0;
    for (var i = 1; i < rrIntervalsMs.length; i++) {
      final d = rrIntervalsMs[i] - rrIntervalsMs[i - 1];
      sumSq += d * d;
    }
    return sqrt(sumSq / (rrIntervalsMs.length - 1));
  }

  double _pnn50(List<double> rrIntervalsMs) {
    var count = 0;
    for (var i = 1; i < rrIntervalsMs.length; i++) {
      if ((rrIntervalsMs[i] - rrIntervalsMs[i - 1]).abs() > 50.0) {
        count++;
      }
    }
    return (count / (rrIntervalsMs.length - 1)) * 100.0;
  }

  /// Get duration for a window type
  Duration _getWindowDuration(WindowType windowType) {
    switch (windowType) {
      case WindowType.window30s:
        return const Duration(seconds: 30);
      case WindowType.window5m:
        return const Duration(minutes: 5);
      case WindowType.window1h:
        return const Duration(hours: 1);
      case WindowType.window24h:
        return const Duration(hours: 24);
    }
  }
}
