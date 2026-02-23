import '../interfaces/feature_providers.dart';
import 'wear_source_handler.dart';

/// Cache for wear raw samples
///
/// RFC-CORE-0007 compliant: buffers raw data only.
/// Feature computation is delegated to Flux.
class WearCache {
  final Map<WindowType, List<WearSample>> _windowSamples = {};

  /// Add a new sample to the cache
  void addSample(WearSample sample) {
    final now = sample.timestamp;

    for (final windowType in WindowType.values) {
      final windowDuration = _getWindowDuration(windowType);
      final cutoffTime = now.subtract(windowDuration);

      _windowSamples[windowType] ??= [];
      _windowSamples[windowType]!.add(sample);
      _windowSamples[windowType]!.removeWhere(
        (s) => s.timestamp.isBefore(cutoffTime),
      );
    }
  }

  /// Get raw samples for a specific window
  List<WearSample> getSamples(WindowType window) {
    return List.unmodifiable(_windowSamples[window] ?? []);
  }

  /// Clear old data
  void clearOldData() {
    final now = DateTime.now();

    for (final windowType in WindowType.values) {
      final windowDuration = _getWindowDuration(windowType);
      final cutoffTime = now.subtract(windowDuration * 2);

      _windowSamples[windowType]?.removeWhere(
        (s) => s.timestamp.isBefore(cutoffTime),
      );
    }
  }

  /// Clear all cached data
  void clear() {
    _windowSamples.clear();
  }

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
