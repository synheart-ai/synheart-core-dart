import 'dart:async';
import '../../core/logger.dart';
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
  StreamSubscription<ConsentSnapshot>? _consentSubscription;

  // Stream controller for raw samples (broadcast for multiple subscribers)
  StreamController<WearSample>? _rawSampleController;

  WearModule({
    required CapabilityProvider capabilities,
    required ConsentProvider consent,
    List<WearSourceHandler>? sources,
    bool useSynheartWear = true, // Use synheart_wear package by default
    bool focusEnabled = false,
    bool emotionEnabled = false,
  }) : _capabilities = capabilities,
       _consent = consent,
       _sources =
           sources ??
           (useSynheartWear
               ? [
                   SynheartWearSourceHandler(
                     focusEnabled: focusEnabled,
                     emotionEnabled: emotionEnabled,
                   ),
                 ] // Use synheart_wear by default
               : [MockWearSourceHandler()]); // Fallback to mock if disabled

  /// Update module enablement status
  ///
  /// This allows dynamic adjustment of collection frequency when
  /// Focus/Emotion modules are enabled or disabled at runtime.
  Future<void> updateModuleStatus({
    bool? focusEnabled,
    bool? emotionEnabled,
  }) async {
    // Update all SynheartWearSourceHandler instances
    for (final source in _sources) {
      if (source is SynheartWearSourceHandler) {
        await source.updateModuleStatus(
          focusEnabled: focusEnabled,
          emotionEnabled: emotionEnabled,
        );
      }
    }
  }

  /// Update collection interval
  ///
  /// Changes the collection frequency for wear data.
  /// This will restart streaming with the new interval if already running.
  ///
  /// Example:
  /// ```dart
  /// await wearModule.updateCollectionInterval(Duration(seconds: 1));
  /// ```
  Future<void> updateCollectionInterval(Duration interval) async {
    for (final source in _sources) {
      if (source is SynheartWearSourceHandler) {
        await source.updateCollectionInterval(interval);
      }
    }
  }

  @override
  WearWindowFeatures? features(WindowType window) {
    // Check consent first
    if (!_consent.current().biosignals) {
      SynheartLogger.log('[WearModule] No features: biosignals consent denied');
      return null; // Return null if consent denied
    }

    final features = _cache.getFeatures(window);
    if (features == null) {
      SynheartLogger.log(
        '[WearModule] No features: cache returned null for $window',
      );
      return null;
    }

    // Check if features are actually populated
    if (features.hrAverage == null &&
        features.hrvRmssd == null &&
        features.motionIndex == null) {
      SynheartLogger.log(
        '[WearModule] No features: cache has empty features for $window (no data collected yet)',
      );
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
    SynheartLogger.log('[WearModule] Initializing wear sources...');

    for (final source in _sources) {
      if (source.isAvailable) {
        try {
          await source.initialize();
          SynheartLogger.log(
            '[WearModule] Initialized ${source.sourceType.name} source',
          );
        } catch (e) {
          SynheartLogger.log(
            '[WearModule] Failed to initialize ${source.sourceType.name}: $e',
            error: e,
          );
        }
      }
    }
  }

  @override
  Future<void> onStart() async {
    SynheartLogger.log('[WearModule] Starting wear data collection...');

    // Check consent before starting - don't collect data if consent is denied
    if (!_consent.current().biosignals) {
      SynheartLogger.log(
        '[WearModule] Not starting data collection: biosignals consent denied',
      );
      return;
    }

    // Listen to consent changes to dynamically stop/start collection
    // Use asyncMap to properly handle async operations in the stream
    _consentSubscription = _consent
        .observe()
        .asyncMap((consent) async {
          if (!consent.biosignals) {
            // Consent revoked - stop data collection immediately
            SynheartLogger.log(
              '[WearModule] Biosignals consent revoked - stopping data collection',
            );
            await _stopDataCollection();
          } else if (consent.biosignals && _subscriptions.isEmpty) {
            // Consent granted - start data collection if not already started
            SynheartLogger.log(
              '[WearModule] Biosignals consent granted - starting data collection',
            );
            await _startDataCollection();
          }
          return consent;
        })
        .listen(
          (_) {
            // Stream processed
          },
          onError: (error) {
            SynheartLogger.log(
              '[WearModule] Error in consent stream: $error',
              error: error,
            );
          },
        );

    // Start data collection
    await _startDataCollection();

    SynheartLogger.log(
      '[WearModule] Started ${_subscriptions.length} wear sources',
    );
  }

  /// Start data collection from all sources
  Future<void> _startDataCollection() async {
    // Check consent again before starting
    if (!_consent.current().biosignals) {
      SynheartLogger.log(
        '[WearModule] Cannot start: biosignals consent denied',
      );
      return;
    }

    // Ensure all sources are initialized (in case they were stopped)
    for (final source in _sources) {
      if (source.isAvailable) {
        try {
          // Re-initialize if needed (e.g., after stop() disposed the SDK)
          await source.initialize();

          // For SynheartWearSourceHandler, explicitly start streaming after initialization
          // This ensures we only start streaming when consent is granted
          if (source is SynheartWearSourceHandler) {
            source.startStreaming();
            SynheartLogger.log(
              '[WearModule] Started HR streaming for ${source.sourceType.name}',
            );
          }
        } catch (e) {
          SynheartLogger.log(
            '[WearModule] Failed to re-initialize ${source.sourceType.name}: $e',
            error: e,
          );
          // Continue with other sources even if one fails
        }
      }
    }

    // Subscribe to each source
    for (final source in _sources) {
      if (source.isAvailable) {
        final subscription = source.sampleStream.listen(
          (sample) {
            // Check consent before caching or streaming - don't process if consent is denied
            if (!_consent.current().biosignals) {
              SynheartLogger.log(
                '[WearModule] Sample ignored: biosignals consent denied',
              );
              return;
            }
            // Add to cache only if consent is granted
            _cache.addSample(sample);

            // Emit to raw sample stream only if consent is granted and controller exists
            // Double-check consent here for extra safety
            if (_consent.current().biosignals &&
                _rawSampleController != null &&
                !_rawSampleController!.isClosed) {
              _rawSampleController!.add(sample);
            }
          },
          onError: (error) {
            SynheartLogger.log(
              '[WearModule] Error from ${source.sourceType.name}: $error',
              error: error,
            );
            // Forward error to raw sample stream
            if (_rawSampleController != null &&
                !_rawSampleController!.isClosed) {
              _rawSampleController!.addError(error);
            }
          },
        );

        _subscriptions.add(subscription);
      }
    }
  }

  /// Stop data collection from all sources (but keep module initialized)
  Future<void> _stopDataCollection() async {
    // Cancel all subscriptions to stop receiving data
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // Stop all sources to stop their internal streaming
    for (final source in _sources) {
      if (source.isAvailable) {
        try {
          await source.stop();
        } catch (e) {
          SynheartLogger.log(
            '[WearModule] Error stopping ${source.sourceType.name}: $e',
            error: e,
          );
        }
      }
    }
  }

  @override
  Future<void> onStop() async {
    SynheartLogger.log('[WearModule] Stopping wear data collection...');

    // Cancel consent subscription
    await _consentSubscription?.cancel();
    _consentSubscription = null;

    // Stop data collection
    await _stopDataCollection();
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    _cache.clear();
    SynheartLogger.log('[WearModule] Cache cleared');
  }

  /// Stream of raw wear samples
  ///
  /// Subscribe to this stream to receive real-time biosignal data.
  /// The stream respects consent - no data is emitted if consent is denied.
  ///
  /// Example:
  /// ```dart
  /// wearModule.rawSampleStream.listen((sample) {
  ///   print('HR: ${sample.hr} BPM');
  ///   print('RR Intervals: ${sample.rrIntervals}');
  /// });
  /// ```
  Stream<WearSample> get rawSampleStream {
    _rawSampleController ??= StreamController<WearSample>.broadcast();
    return _rawSampleController!.stream;
  }

  @override
  Future<void> onDispose() async {
    SynheartLogger.log('[WearModule] Disposing wear module...');

    // Close raw sample stream controller
    await _rawSampleController?.close();
    _rawSampleController = null;

    // Dispose all sources
    for (final source in _sources) {
      try {
        await source.dispose();
      } catch (e) {
        SynheartLogger.log(
          '[WearModule] Error disposing ${source.sourceType.name}: $e',
          error: e,
        );
      }
    }
  }
}
