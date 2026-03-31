import 'dart:async';
import 'package:synheart_wear/synheart_wear.dart' as wear;
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../interfaces/consent_provider.dart';
import '../interfaces/feature_providers.dart';
import '../interfaces/raw_data_provider.dart';
import 'wear_source_handler.dart';
import 'wear_cache.dart';
import 'wear_module_status.dart';
import 'mock_wear_source.dart';
import 'synheart_wear_source_handler.dart';
import 'wearable_event_processor.dart';

/// Wear Module
///
/// Collects and buffers raw biosignals from wearables.
/// RFC-CORE-0007 compliant: no feature computation in Core.
class WearModule extends BaseSynheartModule
    implements RawWearDataProvider {
  @override
  String get moduleId => 'wear';

  final List<WearSourceHandler> _sources;
  final WearCache _cache = WearCache();
  final CapabilityProvider _capabilities;
  final ConsentProvider _consent;

  final List<StreamSubscription<WearSample>> _subscriptions = [];
  StreamSubscription<ConsentSnapshot>? _consentSubscription;
  bool _isStartingCollection = false;

  // True after onStart() has run at least once; used to avoid double _startDataCollection
  // when consent stream emits during initial start, and to allow re-start when consent re-granted.
  bool _dataCollectionStarted = false;

  // Stream controller for raw samples (broadcast for multiple subscribers)
  StreamController<WearSample>? _rawSampleController;

  // Stream controller for module status events
  final StreamController<WearModuleStatus> _statusController =
      StreamController<WearModuleStatus>.broadcast();

  // Vendor sync state — emits true/false when vendor_sync consent changes.
  // The wear SDK (synheart_wear) subscribes to this to start/stop RAMEN.
  final StreamController<bool> _vendorSyncController =
      StreamController<bool>.broadcast();
  bool _lastVendorSyncState = false;

  // Wearable event processor — bridges RAMEN events to the SRM pipeline.
  // Set via setEventProcessor() after Synheart.configure() provides storage + runtime.
  WearableEventProcessor? _eventProcessor;

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

  // MARK: - RawWearDataProvider

  @override
  List<WearSample> rawSamples(WindowType window) {
    if (!_consent.current().allowsChannel('biosignals.vitals')) return [];
    return _cache.getSamples(window);
  }

  @override
  Future<void> onInitialize() async {
    // Intentionally do not initialize sources here.
    //
    // `synheart_wear.initialize()` may trigger OS permission dialogs (HealthKit /
    // Health Connect). We must not prompt until the user has granted Synheart
    // biosignals consent. Sources are initialized on-demand inside
    // `_startDataCollection()` when consent is granted.
  }

  @override
  Future<void> onStart() async {
    // SynheartLogger.log('[WearModule] Starting wear data collection...');

    // Create raw sample stream controller *before* starting collection so that
    // samples are forwarded to the runtime. Previously the controller was created
    // lazily when the runtime subscribed (after Wear started), so early samples
    // were only cached and never reached the runtime → frameCount stayed 0.
    _rawSampleController ??= StreamController<WearSample>.broadcast();

    // Listen to consent changes to dynamically stop/start collection
    // Use asyncMap to properly handle async operations in the stream
    _consentSubscription = _consent
        .observe()
        .asyncMap((consent) async {
          if (!consent.allowsChannel('biosignals.vitals')) {
            // Consent revoked - stop data collection immediately
            // SynheartLogger.log(
            //   '[WearModule] Biosignals consent revoked - stopping data collection',
            // );
            await _stopDataCollection();
          } else if (consent.allowsChannel('biosignals.vitals') && _subscriptions.isEmpty) {
            // Consent granted (either initially or after revoke) — start data collection.
            await _startDataCollection();
          }

          // Track vendor sync state changes
          final vendorSyncNow = consent.vendorSync;
          if (vendorSyncNow != _lastVendorSyncState) {
            _lastVendorSyncState = vendorSyncNow;
            _vendorSyncController.add(vendorSyncNow);
            SynheartLogger.log(
              '[WearModule] Vendor sync ${vendorSyncNow ? "enabled" : "disabled"}',
            );
          }

          return consent;
        })
        .listen(
          (_) {
            // Stream processed
          },
          onError: (error) {
            _emitStatus(WearModuleStatus(
              type: WearModuleStatusType.consentStreamError,
              error: error,
              message: 'Consent observation stream error',
            ));
          },
        );

    // Initialize vendor sync state
    _lastVendorSyncState = _consent.current().vendorSync;
    if (_lastVendorSyncState) {
      _vendorSyncController.add(true);
    }

    // Start data collection only when consent is granted.
    // This prevents OS health permission dialogs from appearing before the user
    // grants Synheart biosignals consent.
    if (_consent.current().allowsChannel('biosignals.vitals')) {
      await _startDataCollection();
    }

    _dataCollectionStarted = true;
    // SynheartLogger.log(
    //   '[WearModule] Started ${_subscriptions.length} wear sources',
    // );
  }

  /// Start data collection from all sources
  Future<void> _startDataCollection() async {
    // Synchronous flag guards against async race: BehaviorSubject emits
    // immediately in onStart, so both the asyncMap callback and the
    // explicit call can enter this method before either awaits.
    if (_isStartingCollection || _subscriptions.isNotEmpty) {
      SynheartLogger.log(
        '[WearModule] Data collection already active/starting, skipping',
      );
      return;
    }
    _isStartingCollection = true;

    try {
    // Check consent again before starting
    if (!_consent.current().allowsChannel('biosignals.vitals')) {
      // SynheartLogger.log(
      //   '[WearModule] Cannot start: biosignals consent denied',
      // );
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
            // SynheartLogger.log(
            //   '[WearModule] Started HR streaming for ${source.sourceType.name}',
            // );
          }
        } catch (e) {
          final isPermission = e is wear.PermissionDeniedError ||
              (e is wear.SynheartWearError && e.code == 'PERMISSION_DENIED');

          _emitStatus(WearModuleStatus(
            type: isPermission
                ? WearModuleStatusType.permissionDenied
                : WearModuleStatusType.sourceInitFailed,
            source: source.sourceType.name,
            error: e,
            message: isPermission
                ? 'Health data permissions not granted'
                : 'Failed to re-initialize ${source.sourceType.name}',
          ));
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
            if (!_consent.current().allowsChannel('biosignals.vitals')) {
              // SynheartLogger.log(
              //   '[WearModule] Sample ignored: biosignals consent denied',
              // );
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
            _emitStatus(WearModuleStatus(
              type: WearModuleStatusType.streamingError,
              source: source.sourceType.name,
              error: error,
              message: 'Streaming error from ${source.sourceType.name}',
            ));
            // Do not forward to rawSampleStream to avoid unhandled exceptions
            // (e.g. Health Connect PERMISSION_DENIED). Listeners still get samples.
          },
        );

        _subscriptions.add(subscription);
      }
    }
    _emitStatus(const WearModuleStatus(
      type: WearModuleStatusType.dataCollectionStarted,
    ));
    } finally {
      _isStartingCollection = false;
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
          _emitStatus(WearModuleStatus(
            type: WearModuleStatusType.streamingError,
            source: source.sourceType.name,
            error: e,
            message: 'Error stopping ${source.sourceType.name}',
          ));
        }
      }
    }

    _emitStatus(const WearModuleStatus(
      type: WearModuleStatusType.dataCollectionStopped,
    ));
  }

  @override
  Future<void> onStop() async {
    _dataCollectionStarted = false;
    // Cancel consent subscription
    await _consentSubscription?.cancel();
    _consentSubscription = null;

    // Stop data collection
    await _stopDataCollection();
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    _cache.clear();
    // SynheartLogger.log('[WearModule] Cache cleared');
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

  /// Stream of module status events.
  ///
  /// Subscribe to this stream to observe initialization outcomes, permission
  /// failures, and streaming errors. Callers that don't subscribe are
  /// unaffected — existing behavior is preserved.
  ///
  /// Example:
  /// ```dart
  /// wearModule.statusStream.listen((status) {
  ///   if (status.type == WearModuleStatusType.permissionDenied) {
  ///     // Prompt user to grant health permissions
  ///   }
  /// });
  /// ```
  Stream<WearModuleStatus> get statusStream => _statusController.stream;

  /// Stream that emits `true` when vendor_sync consent is granted,
  /// `false` when revoked. The wear SDK (synheart_wear) uses this to
  /// start/stop the RAMEN real-time event connection.
  Stream<bool> get vendorSyncState => _vendorSyncController.stream;

  /// Current vendor sync consent state.
  bool get isVendorSyncEnabled => _lastVendorSyncState;

  /// Set the wearable event processor (called by Synheart after configure).
  void setEventProcessor(WearableEventProcessor processor) {
    _eventProcessor = processor;
  }

  /// Process a vendor event from RAMEN into the SRM pipeline.
  ///
  /// Call this when a [RamenEvent] arrives from the wear SDK.
  /// The processor normalizes the event, stores it in SQLite,
  /// and pushes daily values to the runtime for baseline computation.
  Future<void> processVendorEvent({
    required String provider,
    required String eventType,
    required Map<String, dynamic> payload,
    required String eventId,
    required int seq,
  }) async {
    if (!_lastVendorSyncState) {
      SynheartLogger.log(
        '[WearModule] Vendor sync consent not granted — dropping $provider/$eventType',
      );
      return;
    }
    if (_eventProcessor == null) {
      SynheartLogger.log(
        '[WearModule] Event processor not configured — dropping $provider/$eventType',
      );
      return;
    }
    await _eventProcessor!.processRamenEvent(
      provider: provider,
      eventType: eventType,
      payload: payload,
      eventId: eventId,
      seq: seq,
    );
  }

  void _emitStatus(WearModuleStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  @override
  Future<void> onDispose() async {
    // Close vendor sync stream
    await _vendorSyncController.close();

    // Close raw sample stream controller
    await _rawSampleController?.close();
    _rawSampleController = null;

    // Dispose all sources
    for (final source in _sources) {
      try {
        await source.dispose();
      } catch (e) {
        _emitStatus(WearModuleStatus(
          type: WearModuleStatusType.streamingError,
          source: source.sourceType.name,
          error: e,
          message: 'Error disposing ${source.sourceType.name}',
        ));
      }
    }

    // Close status stream last so all status events are delivered
    await _statusController.close();
  }
}
