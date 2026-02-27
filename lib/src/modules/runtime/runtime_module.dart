import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../behavior/behavior_events.dart';
import '../wear/wear_source_handler.dart';
import 'runtime_bridge.dart';
import '../../core/defaults.dart';

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

  /// Key used to persist the SRM baseline snapshot in SharedPreferences.
  /// Set to null to disable auto-persistence. Defaults to "synheart.srm_snapshot".
  /// For multi-subject apps, include the subject ID in the key.
  final String? srmSnapshotKey;

  Timer? _tickTimer;
  StreamSubscription? _wearSubscription;
  StreamSubscription? _behaviorSubscription;

  /// True after we have started the tick timer (after first push, per runtime contract).
  bool _tickTimerStarted = false;

  /// Number of wear samples received this session (diagnostic for "no HSI" debugging).
  int _wearSampleCount = 0;

  /// Last timestamp (ms) sent to the runtime for ANY push (RR, HR, behavior, accel).
  /// Pipeline requires events monotonically non-decreasing by ts_ms across all types.
  int? _lastPushedTsMs;

  final BehaviorSubject<String> _hsiStream = BehaviorSubject<String>();

  /// Stream of HSI JSON strings emitted each time the runtime produces a frame.
  Stream<String> get hsiStream => _hsiStream.stream;

  /// The underlying RuntimeBridge (nullable — null when native library unavailable).
  RuntimeBridge? get bridge => _runtime;

  /// Number of wear samples received this session (diagnostic).
  int get wearSampleCount => _wearSampleCount;

  RuntimeModule({
    RuntimeBridge? runtime,
    Stream<WearSample>? wearSampleStream,
    Stream<BehaviorEvent>? behaviorEventStream,
    this.srmSnapshotKey = 'synheart.srm_snapshot',
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

    // Restore SRM baselines from previous session
    if (srmSnapshotKey != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString(srmSnapshotKey!);
        if (saved != null) {
          final rc = _runtime!.loadSrmSnapshot(saved);
          if (rc == 0) {
            SynheartLogger.log('[RuntimeModule] Restored SRM baselines from snapshot');
          } else {
            SynheartLogger.log('[RuntimeModule] SRM snapshot load failed (code $rc), starting fresh');
          }
        }
      } catch (e) {
        SynheartLogger.log('[RuntimeModule] SRM snapshot restore error: $e');
      }
    }

    // Subscribe to wear samples
    if (_wearSampleStream != null) {
      _wearSampleCount = 0;
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

    // Do NOT start the tick timer here. The runtime anchors the window to the
    // first tick(now_ms). Start the timer only after the first push (wear or
    // behavior); see _handleWearSample and _handleBehaviorEvent.
    SynheartLogger.log('[RuntimeModule] Started');
  }

  @override
  Future<void> onStop() async {
    if (_runtime != null) {
      // Flush any completed window before stopping (in case we're between timer fires).
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final hsiJson = _runtime!.tick(nowMs);
      if (hsiJson != null) {
        final fc = _runtime!.frameCount();
        final q = _runtime!.lastQuality();
        debugPrint('[Runtime] HSI frame #$fc (on stop)${q != null ? ' quality=$q' : ''}');
        debugPrint('[Runtime] HSI JSON: $hsiJson');
        SynheartLogger.log('[Runtime] HSI (tick result, on stop): $hsiJson');
        _hsiStream.add(hsiJson);
      }

      final fc = _runtime!.frameCount();
      final q = _runtime!.lastQuality();
      debugPrint(
        '[Runtime] Stopping: frameCount=$fc lastQuality=$q'
        '${fc == 0 ? " (no HSI produced, wearSamplesReceived=$_wearSampleCount)" : ""}',
      );
      if (fc == 0) {
        final preprocessed = _runtime!.lastPreprocessed();
        if (preprocessed != null && preprocessed.isNotEmpty) {
          debugPrint('[Runtime] Last preprocessed (input to Flux): $preprocessed');
        }
      }
    }
    SynheartLogger.log('[RuntimeModule] Stopping...');

    // Persist SRM baselines for next session
    if (_runtime != null && srmSnapshotKey != null) {
      try {
        final snapshot = _runtime!.exportSrmSnapshot();
        if (snapshot != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(srmSnapshotKey!, snapshot);
          SynheartLogger.log('[RuntimeModule] Saved SRM baselines snapshot');
        }
      } catch (e) {
        SynheartLogger.log('[RuntimeModule] SRM snapshot save error: $e');
      }
    }

    _tickTimer?.cancel();
    _tickTimer = null;
    _tickTimerStarted = false;

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
    _wearSampleCount += 1;
    int tsMs = sample.timestamp.millisecondsSinceEpoch;
    final lastTsMs = _lastPushedTsMs;
    // Pipeline requires monotonically non-decreasing ts_ms across ALL pushes (RR, HR, behavior).
    if (lastTsMs != null && tsMs <= lastTsMs) {
      tsMs = DateTime.now().millisecondsSinceEpoch;
      if (tsMs <= lastTsMs) tsMs = lastTsMs + 1;
    }
    _lastPushedTsMs = tsMs;

    // Log every exact push to the runtime (same as C API: push_rr, push_hr)
    if (sample.rrIntervals != null && sample.rrIntervals!.isNotEmpty) {
      for (final rr in sample.rrIntervals!) {
        debugPrint('[Runtime in] push_rr ts_ms=$tsMs rr_ms=$rr');
        _runtime!.pushRr(tsMs, rr);
      }
    }
    if (sample.hr != null && sample.hr! > 0) {
      if (sample.rrIntervals != null && sample.rrIntervals!.isNotEmpty) {
        debugPrint('[Runtime in] push_hr ts_ms=$tsMs bpm=${sample.hr}');
        _runtime!.pushHr(tsMs, sample.hr!);
      } else {
        // No RR from source (e.g. Health only gives HR). Send explicit RR so runtime
        // receives push_rr (some session runtimes count only explicit RR for quality/HRV).
        final rrMs = (SynheartDefaults.msPerMinute / sample.hr!)
            .clamp(SynheartDefaults.rrMinMs, SynheartDefaults.rrMaxMs);
        debugPrint('[Runtime in] push_rr ts_ms=$tsMs rr_ms=$rrMs (from hr=${sample.hr})');
        _runtime!.pushRr(tsMs, rrMs);
      }
    }

    // Start tick timer and anchor window AFTER first push (matches synthetic_pipeline: push then tick(0)).
    if (!_tickTimerStarted) {
      _startTickTimer();
      _tickTimerStarted = true;
      _runtime!.tick(tsMs);
    }
  }

  void _handleBehaviorEvent(BehaviorEvent event) {
    int tsMs = event.timestamp.millisecondsSinceEpoch;
    final lastTsMs = _lastPushedTsMs;
    // Pipeline requires monotonically non-decreasing ts_ms across ALL pushes.
    if (lastTsMs != null && tsMs <= lastTsMs) {
      tsMs = DateTime.now().millisecondsSinceEpoch;
      if (tsMs <= lastTsMs) tsMs = lastTsMs + 1;
    }
    _lastPushedTsMs = tsMs;

    // Runtime event_type: 0=ScreenOn, 1=ScreenOff, 2=Touch, 3=AppSwitch,
    // 4=NotificationReceived, 5=Scroll, 6=Swipe, 7=Call
    final int eventType;
    final double value;
    switch (event.type) {
      case BehaviorEventType.tap:
      case BehaviorEventType.keyDown:
      case BehaviorEventType.keyUp:
        eventType = 2; // Touch
        value = 1.0;
        break;
      case BehaviorEventType.scroll:
        eventType = 5; // Scroll (runtime 5=Scroll)
        value = event.metadata?['delta'] is num
            ? (event.metadata!['delta'] as num).toDouble()
            : 1.0;
        break;
      case BehaviorEventType.appSwitch:
        eventType = 3; // AppSwitch
        value = 1.0;
        break;
      case BehaviorEventType.notificationReceived:
      case BehaviorEventType.notificationOpened:
        eventType = 4; // NotificationReceived
        value = 1.0;
        break;
    }
    debugPrint('[Runtime in] push_behavior ts_ms=$tsMs event_type=$eventType value=$value');
    _runtime!.pushBehavior(tsMs, eventType, value);

    // Anchor window on first push of any type (matches Rust batch_ingest: t0 = min(ts_ms)).
    if (!_tickTimerStarted) {
      _startTickTimer();
      _tickTimerStarted = true;
      _runtime!.tick(tsMs);
    }
  }

  /// Starts the periodic tick timer. Called once after the first push (wear or behavior)
  /// so the first tick(now_ms) anchors the window to the earliest event timestamp.
  void _startTickTimer() {
    if (_runtime == null || _tickTimer != null) return;
    const intervalSec = 1; // Tick every 1s so we complete the first window within ~1s of 10s boundary.
    _tickTimer = Timer.periodic(const Duration(seconds: intervalSec), (_) {
      final hsiJson = _runtime?.tick(DateTime.now().millisecondsSinceEpoch);
      if (hsiJson != null) {
        final fc = _runtime.frameCount();
        final q = _runtime.lastQuality();
        debugPrint(
          '[Runtime] HSI frame #$fc${q != null ? ' quality=$q' : ''}',
        );
        debugPrint('[Runtime] HSI JSON: $hsiJson');
        SynheartLogger.log('[Runtime] HSI (tick result): $hsiJson');
        _hsiStream.add(hsiJson);
      } else {
        final fc = _runtime!.frameCount();
        if (fc == 0) {
          debugPrint(
            '[Runtime] tick: no HSI yet (window not completed, frameCount=0, wearSamplesReceived=$_wearSampleCount)',
          );
          final preprocessed = _runtime!.lastPreprocessed();
          if (preprocessed != null && preprocessed.isNotEmpty) {
            debugPrint('[Runtime] Last preprocessed (input to Flux): $preprocessed');
          }
        }
      }
    });
    SynheartLogger.log('[RuntimeModule] Tick timer started (after first push)');
  }
}
