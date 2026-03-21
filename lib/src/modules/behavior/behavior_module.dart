import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synheart_behavior/synheart_behavior.dart' as sb;
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../interfaces/consent_provider.dart';
import '../interfaces/feature_providers.dart';
import '../interfaces/raw_data_provider.dart';
import '../runtime/runtime_behavior_code.dart';
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
  final bool _enableMotionLite;

  StreamSubscription<BehaviorEvent>? _eventSubscription;
  StreamSubscription? _synheartBehaviorSubscription;
  Timer? _cleanupTimer;
  sb.SynheartBehavior? _synheartBehavior;

  /// When set, all behavior events are pushed to the runtime via this callback
  /// (so the runtime receives events even if stream delivery is delayed). Signature: (tsMs, eventType, value).
  void Function(int tsMs, int eventType, double value)? _pushBehaviorToRuntime;
  set pushBehaviorToRuntime(
    void Function(int tsMs, int eventType, double value)? f,
  ) {
    _pushBehaviorToRuntime = f;
  }

  BehaviorModule({
    required CapabilityProvider capabilities,
    required ConsentProvider consent,
    bool enableMotionLite = false,
  }) : _capabilities = capabilities,
       _consent = consent,
       _enableMotionLite = enableMotionLite;

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
    SynheartLogger.log('[BehaviorModule] Initializing behavior tracking...');

    // Initialize synheart_behavior package for automatic event capture
    try {
      _synheartBehavior = await sb.SynheartBehavior.initialize(
        config: sb.BehaviorConfig(
          enableInputSignals: true,
          enableAttentionSignals: true,
          enableMotionLite: _enableMotionLite,
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
    }

    // Subscribe to synheart_behavior as soon as SDK is ready so we never miss
    // events that arrive before onStart() (e.g. app_switch right after app open).
    if (_synheartBehavior != null) {
      _synheartBehaviorSubscription = _synheartBehavior!.onEvent.listen(
        _onSynheartBehaviorEvent,
        onError: (e, st) => SynheartLogger.log(
          '[BehaviorModule] synheart_behavior event error: $e',
          error: e,
          stackTrace: st,
        ),
      );
      SynheartLogger.log(
        '[BehaviorModule] Subscribed to synheart_behavior events (at init)',
      );
    }
  }

  void _onSynheartBehaviorEvent(sb.BehaviorEvent event) {
    SynheartLogger.log(
      '[BehaviorModule] synheart_behavior event: type=${event.eventType} ts=${event.timestamp}',
    );
    if (!_consent.current().behavior) return;
    final behaviorEvent = _convertSynheartEvent(event);
    if (behaviorEvent != null) {
      _eventStream.addEvent(behaviorEvent);
      // Push every behavior event directly to runtime (so app_switch, notification, etc. are never missed)
      final mapped = _behaviorEventToRuntimeCode(behaviorEvent);
      if (mapped != null) {
        final tsMs = behaviorEvent.timestamp.millisecondsSinceEpoch;
        _pushBehaviorToRuntime?.call(tsMs, mapped.$1, mapped.$2);
      }
    }
  }

  /// Maps internal BehaviorEvent to runtime (eventType, value). Returns null for types we skip (e.g. clipboard).
  (int, double)? _behaviorEventToRuntimeCode(BehaviorEvent event) {
    switch (event.type) {
      case BehaviorEventType.screenOn:
        return (RuntimeBehaviorCode.screenOn, 1.0);
      case BehaviorEventType.screenOff:
        return (RuntimeBehaviorCode.screenOff, 1.0);
      case BehaviorEventType.tap:
      case BehaviorEventType.keyDown:
      case BehaviorEventType.keyUp:
        return (RuntimeBehaviorCode.input, 1.0);
      case BehaviorEventType.appSwitch:
        return (RuntimeBehaviorCode.appSwitch, 1.0);
      case BehaviorEventType.notificationReceived:
      case BehaviorEventType.notificationOpened:
        return (RuntimeBehaviorCode.notification, 1.0);
      case BehaviorEventType.scroll:
        final delta = event.metadata?['delta'] is num
            ? (event.metadata!['delta'] as num).toDouble()
            : 1.0;
        return (RuntimeBehaviorCode.scroll, delta);
      case BehaviorEventType.swipe:
        final vel = event.metadata?['velocity'] is num
            ? (event.metadata!['velocity'] as num).toDouble()
            : 1.0;
        return (RuntimeBehaviorCode.swipe, vel);
      case BehaviorEventType.call:
        return (RuntimeBehaviorCode.call, 1.0);
    }
  }

  @override
  Future<void> onStart() async {
    SynheartLogger.log('[BehaviorModule] Starting behavior tracking...');

    // Check consent status
    final consent = _consent.current();
    SynheartLogger.log(
      '[BehaviorModule] Behavior consent: ${consent.behavior}',
    );

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

    // synheart_behavior already subscribed in onInitialize() so we never miss events
    if (_synheartBehavior != null && _synheartBehaviorSubscription == null) {
      _synheartBehaviorSubscription = _synheartBehavior!.onEvent.listen(
        _onSynheartBehaviorEvent,
        onError: (e, st) => SynheartLogger.log(
          '[BehaviorModule] synheart_behavior event error: $e',
          error: e,
          stackTrace: st,
        ),
      );
    }

    // Start cleanup timer (every minute)
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _aggregator.cleanOldWindows();
    });

    SynheartLogger.log('[BehaviorModule] Behavior tracking started');
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
        return BehaviorEvent.call();
      case sb.BehaviorEventType.swipe:
        final velocity = event.metrics['velocity'] is num
            ? (event.metrics['velocity'] as num).toDouble()
            : 1.0;
        final direction = event.metrics['direction'] is String
            ? event.metrics['direction'] as String
            : null;
        return BehaviorEvent.swipe(velocity: velocity, direction: direction);
      case sb.BehaviorEventType.clipboard:
        // Clipboard events don't map to an internal behavior event
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
