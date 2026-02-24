import 'dart:async';

import 'package:rxdart/rxdart.dart';

import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../behavior/behavior_events.dart';
import '../wear/wear_source_handler.dart';
import 'runtime_bridge.dart';

/// Runtime Module — streams wear and behavior data into the synheart-runtime
/// C ABI and periodically ticks to produce HSI JSON frames.
///
/// When [_runtime] is null (native library unavailable) the pipeline is
/// gracefully inert: subscriptions are skipped and no HSI is produced.
/// This is the standard pattern for all synheart-runtime consumers.
class RuntimeModule extends BaseSynheartModule {
  @override
  String get moduleId => 'runtime';

  final RuntimeBridge? _runtime;
  final Stream<WearSample>? _wearSampleStream;
  final Stream<BehaviorEvent>? _behaviorEventStream;

  Timer? _tickTimer;
  StreamSubscription? _wearSubscription;
  StreamSubscription? _behaviorSubscription;

  final BehaviorSubject<String> _hsiStream = BehaviorSubject<String>();

  /// Stream of HSI JSON strings emitted each time the runtime produces a frame.
  Stream<String> get hsiStream => _hsiStream.stream;

  /// The underlying RuntimeBridge (nullable — null when native library unavailable).
  RuntimeBridge? get bridge => _runtime;

  RuntimeModule({
    RuntimeBridge? runtime,
    Stream<WearSample>? wearSampleStream,
    Stream<BehaviorEvent>? behaviorEventStream,
  })  : _runtime = runtime,
        _wearSampleStream = wearSampleStream,
        _behaviorEventStream = behaviorEventStream;

  @override
  Future<void> onInitialize() async {
    SynheartLogger.log('[RuntimeModule] Initialized (native bridge ${_runtime != null ? "available" : "unavailable"})');
  }

  @override
  Future<void> onStart() async {
    SynheartLogger.log('[RuntimeModule] Starting...');

    if (_runtime == null) {
      SynheartLogger.log(
        '[RuntimeModule] No native bridge — pipeline inert until synheart_runtime is linked',
      );
      return;
    }

    // Subscribe to wear samples
    if (_wearSampleStream != null) {
      _wearSubscription = _wearSampleStream!.listen(
        _handleWearSample,
        onError: (e, st) => SynheartLogger.log(
          '[RuntimeModule] Wear stream error: $e',
          error: e,
          stackTrace: st,
        ),
      );
    }

    // Subscribe to behavior events
    if (_behaviorEventStream != null) {
      _behaviorSubscription = _behaviorEventStream!.listen(
        _handleBehaviorEvent,
        onError: (e, st) => SynheartLogger.log(
          '[RuntimeModule] Behavior stream error: $e',
          error: e,
          stackTrace: st,
        ),
      );
    }

    // Tick every 5 seconds
    _tickTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final hsiJson = _runtime?.tick(DateTime.now().millisecondsSinceEpoch);
      if (hsiJson != null) {
        _hsiStream.add(hsiJson);
      }
    });

    SynheartLogger.log('[RuntimeModule] Started');
  }

  @override
  Future<void> onStop() async {
    SynheartLogger.log('[RuntimeModule] Stopping...');

    _tickTimer?.cancel();
    _tickTimer = null;

    await _wearSubscription?.cancel();
    _wearSubscription = null;

    await _behaviorSubscription?.cancel();
    _behaviorSubscription = null;

    SynheartLogger.log('[RuntimeModule] Stopped');
  }

  @override
  Future<void> onDispose() async {
    SynheartLogger.log('[RuntimeModule] Disposing...');

    await _hsiStream.close();
    _runtime?.dispose();
  }

  // --- Private helpers ---

  void _handleWearSample(WearSample sample) {
    final tsMs = sample.timestamp.millisecondsSinceEpoch;

    // Push individual RR intervals
    if (sample.rrIntervals != null) {
      for (final rr in sample.rrIntervals!) {
        _runtime!.pushRr(tsMs, rr);
      }
    }

    // Push heart rate
    if (sample.hr != null) {
      _runtime!.pushHr(tsMs, sample.hr!);
    }
  }

  void _handleBehaviorEvent(BehaviorEvent event) {
    final tsMs = event.timestamp.millisecondsSinceEpoch;

    switch (event.type) {
      case BehaviorEventType.tap:
      case BehaviorEventType.scroll:
      case BehaviorEventType.keyDown:
      case BehaviorEventType.keyUp:
        // Touch / input — event_type 2
        _runtime!.pushBehavior(tsMs, 2, 1.0);
      case BehaviorEventType.appSwitch:
        // App switch — event_type 3
        _runtime!.pushBehavior(tsMs, 3, 1.0);
      case BehaviorEventType.notificationReceived:
      case BehaviorEventType.notificationOpened:
        // Notification — event_type 4
        _runtime!.pushBehavior(tsMs, 4, 1.0);
    }
  }
}
