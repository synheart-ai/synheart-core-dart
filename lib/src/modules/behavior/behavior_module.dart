import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synheart_behavior/synheart_behavior.dart' as sb;
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../interfaces/consent_provider.dart';
import '../interfaces/feature_providers.dart';
import '../interfaces/raw_data_provider.dart';
import 'behavior_events.dart';
import 'behavior_event_stream.dart';
import 'window_aggregator.dart';

/// Behavior Module
///
/// Captures user-device interaction patterns using synheart_behavior package.
/// RFC-CORE-0007 compliant: no feature computation in Core.
class BehaviorModule extends BaseSynheartModule
    implements RawBehaviorDataProvider {
  @override
  String get moduleId => 'behavior';

  final BehaviorEventStream _eventStream = BehaviorEventStream();
  final WindowAggregator _aggregator = WindowAggregator();

  final CapabilityProvider _capabilities;
  final ConsentProvider _consent;

  StreamSubscription<BehaviorEvent>? _eventSubscription;
  StreamSubscription? _synheartBehaviorSubscription;
  Timer? _cleanupTimer;
  sb.SynheartBehavior? _synheartBehavior;
  StreamSubscription<ConsentSnapshot>? _consentSubscription;
  bool _isStarting = false;

  BehaviorModule({
    required CapabilityProvider capabilities,
    required ConsentProvider consent,
  }) : _capabilities = capabilities,
       _consent = consent;

  /// Get the event stream for recording events (for manual instrumentation)
  BehaviorEventStream get eventStream => _eventStream;

  /// Get the synheart_behavior instance for wrapping your app
  ///
  /// Usage:
  /// ```dart
  /// Widget build(BuildContext context) {
  ///   return hsi.behaviorModule!.synheartBehavior!.wrapWithGestureDetector(
  ///     MaterialApp(...)
  ///   );
  /// }
  /// ```
  sb.SynheartBehavior? get synheartBehavior => _synheartBehavior;


  // MARK: - RawBehaviorDataProvider

  @override
  List<BehaviorEvent> rawEvents(WindowType window) {
    if (!_consent.current().behavior) return [];
    return _aggregator.getEvents(window);
  }

  @override
  Future<void> onInitialize() async {
    // Intentionally do not initialize synheart_behavior here.
    //
    // Consent gating policy: no collection at all without consent.
    // synheart_behavior.initialize() starts native collection, so we only
    // initialize when `behavior` consent is granted (inside onStart).
  }

  @override
  Future<void> onStart() async {
    SynheartLogger.log('[BehaviorModule] Starting behavior tracking...');

    // Consent gating policy: no collection at all without consent.
    // Observe consent so we can start/stop dynamically.
    _consentSubscription ??= _consent.observe().listen(
      (consent) async {
        if (!consent.behavior) {
          await _stopTracking(disposeSdk: true);
        } else {
          await _startTrackingIfNeeded();
        }
      },
      onError: (e, st) => SynheartLogger.log(
        '[BehaviorModule] Consent observation error: $e',
        error: e,
        stackTrace: st,
      ),
    );

    // Start only if consent is granted.
    await _startTrackingIfNeeded();
  }

  Future<void> _startTrackingIfNeeded() async {
    if (_isStarting) return;
    if (_eventSubscription != null || _cleanupTimer != null) return;
    if (!_consent.current().behavior) return;

    _isStarting = true;
    try {
      // Initialize synheart_behavior only after consent is granted.
      if (_synheartBehavior == null) {
        try {
          _synheartBehavior = await sb.SynheartBehavior.initialize(
            config: const sb.BehaviorConfig(
              enableInputSignals: true,
              enableAttentionSignals: true,
              enableMotionLite:
                  false, // Disabled: 50Hz sensor + ONNX inference is too heavy during debug
            ),
          );
          SynheartLogger.log(
            '[BehaviorModule] synheart_behavior initialized successfully',
          );
        } catch (e) {
          SynheartLogger.log(
            '[BehaviorModule] Failed to initialize synheart_behavior: $e',
            error: e,
          );
          // Continue without automatic capture - fallback to manual instrumentation
          _synheartBehavior = null;
        }
      }

      // Subscribe to manual event stream only when consent is granted.
      _eventSubscription = _eventStream.events.listen(
        (event) {
          if (!_consent.current().behavior) return;
          _aggregator.addEvent(event);
        },
        onError: (e, st) => SynheartLogger.log(
          '[BehaviorModule] Event stream error: $e',
          error: e,
          stackTrace: st,
        ),
      );

      // Subscribe to synheart_behavior automatic events (if available).
      final synheartBehavior = _synheartBehavior;
      if (synheartBehavior != null) {
        _synheartBehaviorSubscription = synheartBehavior.onEvent.listen(
          (event) {
            if (!_consent.current().behavior) return;
            final behaviorEvent = _convertSynheartEvent(event);
            if (behaviorEvent != null) {
              _eventStream.addEvent(behaviorEvent);
            }
          },
          onError: (e, st) => SynheartLogger.log(
            '[BehaviorModule] synheart_behavior event error: $e',
            error: e,
            stackTrace: st,
          ),
        );
      }

      // Start cleanup timer (every minute) only while collecting.
      _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _aggregator.cleanOldWindows();
      });

      SynheartLogger.log('[BehaviorModule] Behavior tracking started');
    } finally {
      _isStarting = false;
    }
  }

  Future<void> _stopTracking({required bool disposeSdk}) async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    await _synheartBehaviorSubscription?.cancel();
    _synheartBehaviorSubscription = null;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    if (disposeSdk) {
      try {
        await _synheartBehavior?.dispose();
      } catch (e) {
        SynheartLogger.log(
          '[BehaviorModule] Error disposing synheart_behavior: $e',
          error: e,
        );
      } finally {
        _synheartBehavior = null;
      }
    }
  }

  /// Convert synheart_behavior event to internal BehaviorEvent format
  BehaviorEvent? _convertSynheartEvent(sb.BehaviorEvent event) {
    // Map synheart_behavior events to internal event types
    final eventType = event.eventType;

    switch (eventType) {
      case sb.BehaviorEventType.tap:
        return BehaviorEvent.tap(Offset.zero);
      case sb.BehaviorEventType.scroll:
        // Extract velocity from metrics (synheart_behavior uses 'velocity' key)
        final velocity = event.metrics['velocity'] as double? ?? 0.0;
        // Use velocity as delta for scroll events
        return BehaviorEvent.scroll(velocity);
      case sb.BehaviorEventType.typing:
        // Map typing to keyDown for now
        return BehaviorEvent.keyDown();
      case sb.BehaviorEventType.notification:
        // Check the action in metrics to determine if received or opened
        final action = event.metrics['action'] as String?;
        if (action == 'opened') {
          return BehaviorEvent.notificationOpened();
        } else {
          return BehaviorEvent.notificationReceived();
        }
      case sb.BehaviorEventType.call:
        // Map call events to notification received for now
        return BehaviorEvent.notificationReceived();
      case sb.BehaviorEventType.swipe:
        // Map swipe to tap for now (could be enhanced later)
        return BehaviorEvent.tap(Offset.zero);
      case sb.BehaviorEventType.clipboard:
        // Clipboard events don't map to an internal behavior event
        return null;
    }
  }

  @override
  Future<void> onStop() async {
    SynheartLogger.log('[BehaviorModule] Stopping behavior tracking...');
    await _consentSubscription?.cancel();
    _consentSubscription = null;
    await _stopTracking(disposeSdk: true);
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    _aggregator.clear();
    SynheartLogger.log('[BehaviorModule] Cache cleared');
  }

  @override
  Future<void> onDispose() async {
    SynheartLogger.log('[BehaviorModule] Disposing behavior module...');
    await _eventStream.dispose();
    _synheartBehavior = null;
  }
}
