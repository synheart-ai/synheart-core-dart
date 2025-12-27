import 'dart:async';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../interfaces/consent_provider.dart';
import '../interfaces/feature_providers.dart';
import 'wear_source_handler.dart';
import 'wear_cache.dart';
import 'mock_wear_source.dart';
import 'synheart_wear_source_handler.dart';

/// Wear Module
///
/// Collects and normalizes biosignals from wearables.
/// Provides window-based features to HSI Runtime.
class WearModule extends BaseSynheartModule implements WearFeatureProvider {
  @override
  String get moduleId => 'wear';

  final List<WearSourceHandler> _sources;
  final WearCache _cache = WearCache();
  final CapabilityProvider _capabilities;
  final ConsentProvider _consent;

  final List<StreamSubscription<WearSample>> _subscriptions = [];

  WearModule({
    required CapabilityProvider capabilities,
    required ConsentProvider consent,
    List<WearSourceHandler>? sources,
    bool useSynheartWear = true, // Use synheart_wear package by default
  })  : _capabilities = capabilities,
        _consent = consent,
        _sources = sources ??
            (useSynheartWear
                ? [SynheartWearSourceHandler()] // Use synheart_wear by default
                : [MockWearSourceHandler()]); // Fallback to mock if disabled

  @override
  WearWindowFeatures? features(WindowType window) {
    // Check consent first
    if (!_consent.current().biosignals) {
      return null; // Return null if consent denied
    }

    final features = _cache.getFeatures(window);
    if (features == null) {
      return null;
    }

    // Filter based on capability level
    return _filterByCapability(features);
  }

  /// Filter features based on capability level
  WearWindowFeatures? _filterByCapability(WearWindowFeatures features) {
    final level = _capabilities.capability(Module.wear);

    switch (level) {
      case CapabilityLevel.none:
        return null;

      case CapabilityLevel.core:
        // Core: Only derived metrics (average HR, HRV)
        return WearWindowFeatures(
          windowDuration: features.windowDuration,
          hrAverage: features.hrAverage,
          hrvRmssd: features.hrvRmssd,
          hrvSdnn: features.hrvSdnn,
          pnn50: features.pnn50,
          meanRrMs: features.meanRrMs,
          motionIndex: features.motionIndex,
          sleepStage: features.sleepStage,
          respRate: features.respRate,
          // No min/max for core level
        );

      case CapabilityLevel.extended:
        // Extended: Include min/max
        return features;

      case CapabilityLevel.research:
        // Research: Full access (would include raw RR intervals in production)
        return features;
    }
  }

  @override
  Future<void> onInitialize() async {
    print('[WearModule] Initializing wear sources...');

    for (final source in _sources) {
      if (source.isAvailable) {
        try {
          await source.initialize();
          print('[WearModule] Initialized ${source.sourceType.name} source');
        } catch (e) {
          print('[WearModule] Failed to initialize ${source.sourceType.name}: $e');
        }
      }
    }
  }

  @override
  Future<void> onStart() async {
    print('[WearModule] Starting wear data collection...');

    // Subscribe to each source
    for (final source in _sources) {
      if (source.isAvailable) {
        final subscription = source.sampleStream.listen(
          (sample) {
            // Add to cache
            _cache.addSample(sample);
          },
          onError: (error) {
            print('[WearModule] Error from ${source.sourceType.name}: $error');
          },
        );

        _subscriptions.add(subscription);
      }
    }

    print('[WearModule] Started ${_subscriptions.length} wear sources');
  }

  @override
  Future<void> onStop() async {
    print('[WearModule] Stopping wear data collection...');

    // Cancel all subscriptions
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  @override
  Future<void> onDispose() async {
    print('[WearModule] Disposing wear module...');

    // Dispose all sources
    for (final source in _sources) {
      try {
        await source.dispose();
      } catch (e) {
        print('[WearModule] Error disposing ${source.sourceType.name}: $e');
      }
    }
  }
}
