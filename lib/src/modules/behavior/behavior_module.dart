import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synheart_behavior/synheart_behavior.dart' as sb;
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../interfaces/consent_provider.dart';
import '../interfaces/feature_providers.dart';
import 'behavior_events.dart';
import 'behavior_event_stream.dart';
import 'window_aggregator.dart';
import 'feature_extractor.dart';

/// Behavior Module
///
/// Captures user-device interaction patterns using synheart_behavior package.
/// Provides window-based behavioral features to HSI Runtime.
class BehaviorModule extends BaseSynheartModule implements BehaviorFeatureProvider {
  @override
  String get moduleId => 'behavior';

  final BehaviorEventStream _eventStream = BehaviorEventStream();
  final WindowAggregator _aggregator = WindowAggregator();
  final BehaviorFeatureExtractor _extractor = BehaviorFeatureExtractor();

  final CapabilityProvider _capabilities;
  final ConsentProvider _consent;

  StreamSubscription<BehaviorEvent>? _eventSubscription;
  StreamSubscription? _synheartBehaviorSubscription;
  Timer? _cleanupTimer;
  sb.SynheartBehavior? _synheartBehavior;

  BehaviorModule({
    required CapabilityProvider capabilities,
    required ConsentProvider consent,
  })  : _capabilities = capabilities,
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

  @override
  BehaviorWindowFeatures? features(WindowType window) {
    // Check consent
    if (!_consent.current().behavior) {
      return null; // Return null if consent denied
    }

    final events = _aggregator.getEvents(window);
    final features = _extractor.extract(events);

    // Filter based on capability level
    return _filterByCapability(features);
  }

  /// Filter features based on capability level
  BehaviorWindowFeatures? _filterByCapability(BehaviorWindowFeatures features) {
    final level = _capabilities.capability(Module.behavior);

    switch (level) {
      case CapabilityLevel.none:
        return null;

      case CapabilityLevel.core:
        // Core: Only basic metrics
        return BehaviorWindowFeatures(
          tapRateNorm: features.tapRateNorm,
          keystrokeRateNorm: features.keystrokeRateNorm,
          scrollVelocityNorm: features.scrollVelocityNorm,
          idleRatio: features.idleRatio,
          switchRateNorm: features.switchRateNorm,
          burstiness: 0.0, // Not available at core
          sessionFragmentation: 0.0, // Not available at core
          notificationLoad: 0.0, // Not available at core
          distractionScore: features.distractionScore,
          focusHint: features.focusHint,
        );

      case CapabilityLevel.extended:
      case CapabilityLevel.research:
        // Extended/Research: Full access
        return features;
    }
  }

  @override
  Future<void> onInitialize() async {
    SynheartLogger.log('[BehaviorModule] Initializing behavior tracking...');

    // Initialize synheart_behavior package for automatic event capture
    try {
      _synheartBehavior = await sb.SynheartBehavior.initialize(
        config: const sb.BehaviorConfig(
          enableInputSignals: true,
          enableAttentionSignals: true,
          enableMotionLite: false,
        ),
      );
      SynheartLogger.log('[BehaviorModule] synheart_behavior initialized successfully');
    } catch (e) {
      SynheartLogger.log(
        '[BehaviorModule] Failed to initialize synheart_behavior: $e',
        error: e,
      );
      // Continue without automatic capture - fallback to manual instrumentation
    }
  }

  @override
  Future<void> onStart() async {
    SynheartLogger.log('[BehaviorModule] Starting behavior tracking...');

    // Subscribe to manual event stream
    _eventSubscription = _eventStream.events.listen(
      (event) {
        // Check consent before adding event
        if (_consent.current().behavior) {
          _aggregator.addEvent(event);
        }
      },
      onError: (e, st) => SynheartLogger.log(
        '[BehaviorModule] Event stream error: $e',
        error: e,
        stackTrace: st,
      ),
    );

    // Subscribe to synheart_behavior automatic events
    if (_synheartBehavior != null) {
      _synheartBehaviorSubscription = _synheartBehavior!.onEvent.listen(
        (event) {
          // Check consent before adding event
          if (_consent.current().behavior) {
            // Convert synheart_behavior event to internal BehaviorEvent
            final behaviorEvent = _convertSynheartEvent(event);
            if (behaviorEvent != null) {
              _aggregator.addEvent(behaviorEvent);
            }
          }
        },
        onError: (e, st) => SynheartLogger.log(
          '[BehaviorModule] synheart_behavior event error: $e',
          error: e,
          stackTrace: st,
        ),
      );
      SynheartLogger.log('[BehaviorModule] Subscribed to synheart_behavior events');
    }

    // Start cleanup timer (every minute)
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _aggregator.cleanOldWindows();
    });

    SynheartLogger.log('[BehaviorModule] Behavior tracking started');
  }

  /// Convert synheart_behavior event to internal BehaviorEvent format
  BehaviorEvent? _convertSynheartEvent(dynamic event) {
    // Map synheart_behavior events to internal event types
    final eventType = event.eventType as String?;
    if (eventType == null) return null;

    switch (eventType.toLowerCase()) {
      case 'tap':
      case 'touch':
        return BehaviorEvent.tap(Offset.zero);
      case 'scroll':
        final delta = event.metrics?['scrollDelta'] as double? ?? 0.0;
        return BehaviorEvent.scroll(delta);
      case 'keydown':
      case 'key_down':
        return BehaviorEvent.keyDown();
      case 'keyup':
      case 'key_up':
        return BehaviorEvent.keyUp();
      case 'app_switch':
      case 'appswitch':
        return BehaviorEvent.appSwitch();
      case 'notification_received':
        return BehaviorEvent.notificationReceived();
      case 'notification_opened':
        return BehaviorEvent.notificationOpened();
      default:
        return null;
    }
  }

  @override
  Future<void> onStop() async {
    SynheartLogger.log('[BehaviorModule] Stopping behavior tracking...');

    await _eventSubscription?.cancel();
    _eventSubscription = null;

    await _synheartBehaviorSubscription?.cancel();
    _synheartBehaviorSubscription = null;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  @override
  Future<void> onDispose() async {
    SynheartLogger.log('[BehaviorModule] Disposing behavior module...');
    await _eventStream.dispose();
    _synheartBehavior = null;
  }
}
