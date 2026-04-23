import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synheart_behavior/synheart_behavior.dart' as sb;
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/capability_provider.dart';
import '../interfaces/consent_provider.dart';
import '../interfaces/feature_providers.dart';
import '../interfaces/raw_data_provider.dart';
import 'behavior_code.dart';
import 'behavior_events.dart';
import 'behavior_event_stream.dart';
import 'window_aggregator.dart';

/// Behavior Module
///
/// Captures user-device interaction patterns using synheart_behavior package.
///
/// Consent gating policy: no collection at all without consent.
/// synheart_behavior.initialize() starts native collection, so we only
/// initialize when `behavior` consent is granted (inside onStart).
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
  StreamSubscription<ConsentSnapshot>? _consentSubscription;
  bool _isStarting = false;

  /// When set, all behavior events are pushed to the runtime via this callback
  /// (so the runtime receives events even if stream delivery is delayed).
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

  @override
  List<BehaviorEvent> rawEvents(WindowType window) {
    if (!_consent.current().allowsChannel('behavior.digital_activity'))
      return [];
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

  /// Handle events from synheart_behavior, forwarding to event stream and runtime.
  ///
  /// Per-call diagnostics are gated to the first few events so we don't
  /// spam logs at the native event rate — just enough to answer the
  /// "are events flowing through the Dart bridge at all?" question when
  /// `behavior_events` shows up empty in an export.
  int _synheartBehaviorEventLogCount = 0;
  void _onSynheartBehaviorEvent(sb.BehaviorEvent event) {
    if (_synheartBehaviorEventLogCount < 3) {
      SynheartLogger.log(
        '[BehaviorModule] _onSynheartBehaviorEvent: received event '
        'type=${event.eventType.name}',
      );
      _synheartBehaviorEventLogCount++;
    }
    if (!_consent.current().allowsChannel('behavior.digital_activity')) {
      if (_synheartBehaviorEventLogCount <= 3) {
        SynheartLogger.log(
          '[BehaviorModule] _onSynheartBehaviorEvent: DROPPED '
          '(consent channel "behavior.digital_activity" not allowed — '
          'events are NOT forwarding to Synheart.behaviorEventStream, '
          'behavior_events will be empty)',
        );
      }
      return;
    }
    final behaviorEvent = _convertSynheartEvent(event);
    if (behaviorEvent != null) {
      _eventStream.addEvent(behaviorEvent);
      // Push directly to runtime so app_switch, notification, etc. are never missed.
      final mapped = _behaviorEventToRuntimeCode(behaviorEvent);
      if (mapped != null) {
        final tsMs = behaviorEvent.timestamp.millisecondsSinceEpoch;
        _pushBehaviorToRuntime?.call(tsMs, mapped.$1, mapped.$2);
      }
    } else if (_synheartBehaviorEventLogCount <= 3) {
      SynheartLogger.log(
        '[BehaviorModule] _onSynheartBehaviorEvent: DROPPED '
        '(_convertSynheartEvent returned null for type=${event.eventType.name})',
      );
    }
  }

  /// Maps internal BehaviorEvent to runtime (eventType, value).
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

    // Observe consent so we can start/stop dynamically.
    _consentSubscription ??= _consent.observe().listen(
      (consent) async {
        if (!consent.allowsChannel('behavior.digital_activity')) {
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
    if (_isStarting) {
      SynheartLogger.log(
        '[BehaviorModule] _startTrackingIfNeeded: SKIP (already starting)',
      );
      return;
    }
    if (_eventSubscription != null || _cleanupTimer != null) {
      SynheartLogger.log(
        '[BehaviorModule] _startTrackingIfNeeded: SKIP (already running: '
        'eventSub=${_eventSubscription != null}, '
        'cleanupTimer=${_cleanupTimer != null}, '
        'synheart_behavior=${_synheartBehavior != null})',
      );
      return;
    }
    if (!_consent.current().allowsChannel('behavior.digital_activity')) {
      SynheartLogger.log(
        '[BehaviorModule] _startTrackingIfNeeded: SKIP (consent channel '
        '"behavior.digital_activity" not granted)',
      );
      return;
    }

    SynheartLogger.log(
      '[BehaviorModule] _startTrackingIfNeeded: proceeding '
      '(synheart_behavior currently ${_synheartBehavior == null ? "null" : "set"})',
    );

    _isStarting = true;
    try {
      // Initialize synheart_behavior only after consent is granted.
      if (_synheartBehavior == null) {
        SynheartLogger.log(
          '[BehaviorModule] Calling SynheartBehavior.initialize()…',
        );
        try {
          _synheartBehavior = await sb.SynheartBehavior.initialize(
            config: sb.BehaviorConfig(
              enableInputSignals: true,
              enableAttentionSignals: true,
              enableMotionLite: _enableMotionLite,
            ),
          );
          SynheartLogger.log(
            '[BehaviorModule] synheart_behavior initialized successfully '
            '(instance=${_synheartBehavior != null})',
          );
        } catch (e, st) {
          SynheartLogger.log(
            '[BehaviorModule] Failed to initialize synheart_behavior: $e',
            error: e,
            stackTrace: st,
          );
          _synheartBehavior = null;
        }
      }

      // Subscribe to manual event stream only when consent is granted.
      _eventSubscription = _eventStream.events.listen(
        (event) {
          if (!_consent.current().allowsChannel('behavior.digital_activity'))
            return;
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
          _onSynheartBehaviorEvent,
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
    final eventType = event.eventType;

    switch (eventType) {
      case sb.BehaviorEventType.tap:
        // Preserve the native tap coordinates when the iOS plugin
        // provides them (UITapGestureRecognizer.location(in:) on a
        // non-zero view). Falls back to Offset.zero when absent so
        // downstream consumers always receive a well-formed event.
        final x = (event.metrics['x'] as num?)?.toDouble() ?? 0.0;
        final y = (event.metrics['y'] as num?)?.toDouble() ?? 0.0;
        return BehaviorEvent.tap(Offset(x, y));
      case sb.BehaviorEventType.scroll:
        final velocity = event.metrics['velocity'] as double? ?? 0.0;
        return BehaviorEvent.scroll(velocity);
      case sb.BehaviorEventType.typing:
        return BehaviorEvent.keyDown();
      case sb.BehaviorEventType.notification:
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
        return null;
      // Forward-compat: newer synheart_behavior versions may add variants
      // (e.g. app_switch) that this SDK doesn't yet map. Drop them silently.
      // ignore: unreachable_switch_default
      default:
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
