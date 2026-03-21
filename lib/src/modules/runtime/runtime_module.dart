import 'dart:async';
import 'dart:convert';

import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../behavior/behavior_events.dart';
import '../wear/wear_source_handler.dart';
import 'runtime_behavior_code.dart';
import 'runtime_bridge.dart';
import '../../core/defaults.dart';

/// Runtime Module — streams wear and behavior data into the synheart-runtime
/// C ABI and periodically ticks to produce HSI JSON frames.
///
/// When [batchIngestOnStop] is true, events are buffered during the session and
/// a single [ingestBatch] + drain is run on stop, so HSI is only produced after stop.
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

  /// When true, buffer events and run batch ingest only on stop (no live HSI during session).
  /// Can be changed at runtime; applies to the next session start.
  bool batchIngestOnStop;

  /// Key used to persist the SRM baseline snapshot in SharedPreferences.
  /// Set to null to disable auto-persistence. Defaults to "synheart.srm_snapshot".
  /// For multi-subject apps, include the subject ID in the key.
  final String? srmSnapshotKey;

  Timer? _tickTimer;
  StreamSubscription? _wearSubscription;
  StreamSubscription? _behaviorSubscription;

  /// Buffered events for batch ingest (only used when [batchIngestOnStop] is true).
  final List<Map<String, dynamic>> _batchEventBuffer = [];

  /// True after we have started the tick timer (after first push, per runtime contract).
  bool _tickTimerStarted = false;

  /// Number of wear samples received this session (diagnostic for "no HSI" debugging).
  int _wearSampleCount = 0;

  /// Temporary debug toggle: set true only when you want full per-tick HSI JSON logs.
  static const bool _logTickHsiJson = false;

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

  /// Push a behavior event and ensure the tick timer is started so the pipeline advances and HSI is produced.
  /// Use this when pushing from a callback (e.g. notification from BehaviorModule) so behavioral data is not stuck at 0.
  void pushBehaviorAndEnsureTick(int tsMs, int eventType, double value) {
    if (_runtime == null) return;
    // In batch mode, behavior events must be buffered (see _handleBehaviorEvent),
    // not pushed directly, otherwise we violate "HSI only on stop".
    if (batchIngestOnStop) return;

    var safeTsMs = tsMs;
    final lastTsMs = _lastPushedTsMs;
    if (lastTsMs != null && safeTsMs <= lastTsMs) {
      safeTsMs = lastTsMs + 1;
    }
    _runtime!.pushBehavior(safeTsMs, eventType, value);
    _lastPushedTsMs = safeTsMs;
    if (!_tickTimerStarted) {
      _startTickTimer();
      _tickTimerStarted = true;
      _runtime!.tick(safeTsMs);
    }
  }

  /// Push a wear HR sample directly into runtime and ensure ticking is active.
  /// Optionally synthesizes one RR interval from BPM so RR-dependent wear metrics are populated.
  void pushWearHrAndEnsureTick(
    int tsMs,
    double bpm, {
    bool synthesizeRr = true,
  }) {
    if (_runtime == null || bpm <= 0) return;
    _wearSampleCount += 1;

    if (batchIngestOnStop) {
      _batchEventBuffer.add({'type': 'hr', 'ts_ms': tsMs, 'bpm': bpm});
      if (synthesizeRr) {
        final rrMs = (SynheartDefaults.msPerMinute / bpm)
            .clamp(SynheartDefaults.rrMinMs, SynheartDefaults.rrMaxMs);
        _batchEventBuffer.add({'type': 'rr', 'ts_ms': tsMs, 'rr_ms': rrMs});
      }
      return;
    }

    var safeTsMs = tsMs;
    if (_lastPushedTsMs != null && safeTsMs <= _lastPushedTsMs!) {
      safeTsMs = _lastPushedTsMs! + 1;
    }
    _runtime!.pushHr(safeTsMs, bpm);
    if (synthesizeRr) {
      final rrMs = (SynheartDefaults.msPerMinute / bpm)
          .clamp(SynheartDefaults.rrMinMs, SynheartDefaults.rrMaxMs);
      _runtime!.pushRr(safeTsMs, rrMs);
    }
    _lastPushedTsMs = safeTsMs;
    if (!_tickTimerStarted) {
      _startTickTimer();
      _tickTimerStarted = true;
      _runtime!.tick(safeTsMs);
    }
  }

  RuntimeModule({
    RuntimeBridge? runtime,
    Stream<WearSample>? wearSampleStream,
    Stream<BehaviorEvent>? behaviorEventStream,
    this.batchIngestOnStop = false,
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
    SynheartLogger.log('[RuntimeModule] Starting... (bridge ${_runtime != null ? "available" : "NULL"})');

    if (_runtime != null) {
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

      // Subscribe to wear samples (only when bridge available)
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
    } else {
      SynheartLogger.log(
        '[RuntimeModule] No native bridge — behavior/wear events will be dropped until synheart_runtime is linked',
      );
    }

    // Always subscribe to behavior events so we can log when bridge is null (diagnostics)
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
    if (_runtime != null && batchIngestOnStop && _batchEventBuffer.isNotEmpty) {
      // Batch-on-stop: run single ingestBatch + drain, then persist SRM
      _flushBatchOnStop();
    } else if (_runtime != null && !batchIngestOnStop) {
      // Streaming: flush any completed window before stopping
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final hsiJson = _runtime!.tick(nowMs);
      if (hsiJson != null) {
        SynheartLogger.log('[Runtime] HSI (tick result, on stop): $hsiJson');
        _hsiStream.add(hsiJson);
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

  /// Flush buffered events to the native runtime via ingestBatch (batch mode only).
  /// Call before labFinalize() so the lab payload includes behavior/wear data.
  void flushBatch() {
    if (batchIngestOnStop && _runtime != null && _batchEventBuffer.isNotEmpty) {
      _flushBatchOnStop();
    }
  }

  /// Runs when [batchIngestOnStop] is true: sort buffer, ingestBatch, drain tick(), emit all HSI.
  void _flushBatchOnStop() {
    if (_runtime == null || _batchEventBuffer.isEmpty) return;

    _batchEventBuffer.sort((a, b) {
      final aTs = a['ts_ms'] as int? ?? 0;
      final bTs = b['ts_ms'] as int? ?? 0;
      return aTs.compareTo(bTs);
    });

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final batchJson = jsonEncode(_batchEventBuffer);
    final resultJson = _runtime!.ingestBatch(batchJson, nowMs);

    if (resultJson == null) {
      SynheartLogger.log(
        '[RuntimeModule] Batch ingest not available (synheart_runtime_ingest_batch_json missing). '
        'HSI will not be produced for this session.',
      );
      _batchEventBuffer.clear();
      return;
    }

    try {
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      final frames = result['frames'] as List<dynamic>?;
      if (result['ok'] == true && frames != null && frames.isNotEmpty) {
        for (final frame in frames) {
          if (frame is Map<String, dynamic> && frame['hsi'] != null) {
            final hsiJson = jsonEncode(frame['hsi']);
            SynheartLogger.log('[Runtime] HSI (batch on stop, frame): $hsiJson');
            _hsiStream.add(hsiJson);
          }
        }
      } else if (result['ok'] == true && result['hsi'] != null) {
        // Legacy: single top-level hsi when frames not present
        final hsiJson = jsonEncode(result['hsi']);
        SynheartLogger.log('[Runtime] HSI (batch on stop): $hsiJson');
        _hsiStream.add(hsiJson);
        const int maxDrainIterations = 256;
        int drainCount = 0;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        while (drainCount < maxDrainIterations) {
          final hsiJson = _runtime!.tick(nowMs);
          if (hsiJson == null) break;
          drainCount += 1;
          SynheartLogger.log('[Runtime] HSI (batch drain): $hsiJson');
          _hsiStream.add(hsiJson);
        }
        if (drainCount >= maxDrainIterations) {
          SynheartLogger.log(
            '[RuntimeModule] Batch drain hit max iterations ($maxDrainIterations); stopping to avoid infinite loop.',
          );
        }
      }
    } catch (e) {
      SynheartLogger.log('[RuntimeModule] Batch result parse error: $e');
    }
    _batchEventBuffer.clear();
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

    if (batchIngestOnStop) {
      _appendWearToBatch(sample, tsMs);
      return;
    }

    final lastTsMs = _lastPushedTsMs;
    if (lastTsMs != null && tsMs <= lastTsMs) {
      tsMs = DateTime.now().millisecondsSinceEpoch;
      if (tsMs <= lastTsMs) tsMs = lastTsMs + 1;
    }

    if (sample.rrIntervals != null && sample.rrIntervals!.isNotEmpty) {
      final rrs = sample.rrIntervals!;

      // Stagger RR timestamps so each beat gets a distinct ts_ms.
      // Work backwards from the sample timestamp: the last RR ends at tsMs,
      // so the first RR started at tsMs - sum(all RRs).
      final totalRrMs = rrs.fold<double>(0, (sum, rr) => sum + rr);
      var rrTs = tsMs - totalRrMs.round();

      // Ensure the first staggered ts doesn't go backwards past the last push.
      if (lastTsMs != null && rrTs <= lastTsMs) {
        rrTs = lastTsMs + 1;
      }

      for (final rr in rrs) {
        _runtime!.pushRr(rrTs, rr);
        _lastPushedTsMs = rrTs;
        rrTs += rr.round();
      }
      tsMs = rrTs; // advance past the last RR for any subsequent pushes
    }

    if (sample.hr != null && sample.hr! > 0) {
      if (sample.rrIntervals == null || sample.rrIntervals!.isEmpty) {
        // No RR from source (e.g. Health only gives HR). Synthesize RR
        // so the runtime has explicit RR data for quality/HRV.
        final rrMs = (SynheartDefaults.msPerMinute / sample.hr!)
            .clamp(SynheartDefaults.rrMinMs, SynheartDefaults.rrMaxMs);
        if (_lastPushedTsMs != null && tsMs <= _lastPushedTsMs!) {
          tsMs = _lastPushedTsMs! + 1;
        }
        _runtime!.pushRr(tsMs, rrMs);
      }
    }
    _lastPushedTsMs = tsMs;

    // Start tick timer and anchor window AFTER first push.
    if (!_tickTimerStarted) {
      _startTickTimer();
      _tickTimerStarted = true;
      _runtime!.tick(tsMs);
    }
  }

  /// Append wear sample to batch buffer (same event shape as ingestBatch expects).
  void _appendWearToBatch(WearSample sample, int tsMs) {
    if (sample.rrIntervals != null && sample.rrIntervals!.isNotEmpty) {
      final rrs = sample.rrIntervals!;
      final totalRrMs = rrs.fold<double>(0, (sum, rr) => sum + rr);
      var rrTs = tsMs - totalRrMs.round();
      for (final rr in rrs) {
        _batchEventBuffer.add({'type': 'rr', 'ts_ms': rrTs, 'rr_ms': rr});
        rrTs += rr.round();
      }
    } else if (sample.hr != null && sample.hr! > 0) {
      _batchEventBuffer.add({
        'type': 'hr',
        'ts_ms': tsMs,
        'bpm': sample.hr!,
      });
    }
  }

  /// Build batch JSON object for a behavior event (guide: event string + optional options).
  Map<String, dynamic> _behaviorEventToBatchMap(int tsMs, BehaviorEvent event) {
    String eventName;
    final options = <String, dynamic>{};
    final meta = event.metadata;
    switch (event.type) {
      case BehaviorEventType.screenOn:
        eventName = 'screen_on';
        break;
      case BehaviorEventType.screenOff:
        eventName = 'screen_off';
        break;
      case BehaviorEventType.tap:
      case BehaviorEventType.keyDown:
      case BehaviorEventType.keyUp:
        eventName = 'touch';
        if (meta != null) {
          if (meta['x'] is num) options['x'] = (meta['x'] as num).toDouble();
          if (meta['y'] is num) options['y'] = (meta['y'] as num).toDouble();
        }
        break;
      case BehaviorEventType.appSwitch:
        eventName = 'app_switch';
        if (meta != null) {
          if (meta['from_app_id'] != null) options['from_app_id'] = meta['from_app_id'];
          if (meta['to_app_id'] != null) options['to_app_id'] = meta['to_app_id'];
        }
        break;
      case BehaviorEventType.notificationReceived:
      case BehaviorEventType.notificationOpened:
        eventName = 'notification';
        if (meta != null) {
          if (meta['action'] != null) options['action'] = meta['action'];
          if (meta['source_app_id'] != null) options['source_app_id'] = meta['source_app_id'];
        }
        break;
      case BehaviorEventType.scroll:
        eventName = 'scroll';
        if (meta != null) {
          if (meta['delta'] is num) options['delta'] = (meta['delta'] as num).toDouble();
          if (meta['velocity'] != null) options['velocity'] = meta['velocity'];
          if (meta['direction'] != null) options['direction'] = meta['direction'];
          if (meta['direction_reversal'] != null) options['direction_reversal'] = meta['direction_reversal'];
        }
        break;
      case BehaviorEventType.swipe:
        eventName = 'swipe';
        if (meta != null) {
          if (meta['velocity'] is num) options['velocity'] = (meta['velocity'] as num).toDouble();
          if (meta['direction'] != null) options['direction'] = meta['direction'];
        }
        break;
      case BehaviorEventType.call:
        eventName = 'call';
        if (meta != null && meta['action'] != null) {
          options['action'] = meta['action'];
        }
        break;
    }
    return <String, dynamic>{
      'type': 'behavior',
      'ts_ms': tsMs,
      'event': eventName,
      if (options.isNotEmpty) 'options': options,
      'provider': 'behavior_app',
    };
  }

  /// Push aggregate overnight sleep data into the runtime.
  ///
  /// Call this once per day (e.g. on app launch) with the previous night's
  /// summary from your wearable platform. All fields are optional.
  ///
  /// Example:
  /// ```dart
  /// runtimeModule.pushSleepSummary(
  ///   totalSleepMinutes: 420,
  ///   timeInBedMinutes: 480,
  ///   deepSleepMinutes: 84,
  ///   remSleepMinutes: 105,
  ///   awakeMinutes: 30,
  ///   awakenings: 3,
  ///   vendorSleepScore: 85,
  /// );
  /// ```
  void pushSleepSummary({
    double? totalSleepMinutes,
    double? timeInBedMinutes,
    double? deepSleepMinutes,
    double? remSleepMinutes,
    double? awakeMinutes,
    int? awakenings,
    double? vendorSleepScore,
    double? vendorRecoveryScore,
    double? vendorStrainScore,
  }) {
    if (_runtime == null) return;
    final payload = <String, dynamic>{
      if (totalSleepMinutes != null) 'total_sleep_minutes': totalSleepMinutes,
      if (timeInBedMinutes != null) 'time_in_bed_minutes': timeInBedMinutes,
      if (deepSleepMinutes != null) 'deep_sleep_minutes': deepSleepMinutes,
      if (remSleepMinutes != null) 'rem_sleep_minutes': remSleepMinutes,
      if (awakeMinutes != null) 'awake_minutes': awakeMinutes,
      if (awakenings != null) 'awakenings': awakenings,
      if (vendorSleepScore != null) 'vendor_sleep_score': vendorSleepScore,
      if (vendorRecoveryScore != null) 'vendor_recovery_score': vendorRecoveryScore,
      if (vendorStrainScore != null) 'vendor_strain_score': vendorStrainScore,
    };
    _runtime!.pushSleepStages(jsonEncode(payload));
  }

  void _handleBehaviorEvent(BehaviorEvent event) {
    if (_runtime == null) {
      SynheartLogger.log(
        '[RuntimeModule] Dropping behavior event — native bridge not loaded. Copy libsynheart_runtime.so into android/app/src/main/jniLibs/<abi>/ and do a clean build.',
      );
      return;
    }

    int tsMs = event.timestamp.millisecondsSinceEpoch;
    final lastTsMs = _lastPushedTsMs;
    // Pipeline requires monotonically non-decreasing ts_ms across ALL pushes.
    if (lastTsMs != null && tsMs <= lastTsMs) {
      tsMs = DateTime.now().millisecondsSinceEpoch;
      if (tsMs <= lastTsMs) tsMs = lastTsMs + 1;
    }

    final int eventType;
    final double value;
    switch (event.type) {
      case BehaviorEventType.screenOn:
        eventType = RuntimeBehaviorCode.screenOn;
        value = 1.0;
        break;
      case BehaviorEventType.screenOff:
        eventType = RuntimeBehaviorCode.screenOff;
        value = 1.0;
        break;
      case BehaviorEventType.tap:
      case BehaviorEventType.keyDown:
      case BehaviorEventType.keyUp:
        eventType = RuntimeBehaviorCode.input;
        value = 1.0;
        break;
      case BehaviorEventType.appSwitch:
        eventType = RuntimeBehaviorCode.appSwitch;
        value = 1.0;
        break;
      case BehaviorEventType.notificationReceived:
      case BehaviorEventType.notificationOpened:
        eventType = RuntimeBehaviorCode.notification;
        value = 1.0;
        break;
      case BehaviorEventType.scroll:
        eventType = RuntimeBehaviorCode.scroll;
        value = event.metadata?['delta'] is num
            ? (event.metadata!['delta'] as num).toDouble()
            : 1.0;
        break;
      case BehaviorEventType.swipe:
        eventType = RuntimeBehaviorCode.swipe;
        value = event.metadata?['velocity'] is num
            ? (event.metadata!['velocity'] as num).toDouble()
            : 1.0;
        break;
      case BehaviorEventType.call:
        eventType = RuntimeBehaviorCode.call;
        value = 1.0;
        break;
    }

    if (batchIngestOnStop) {
      _batchEventBuffer.add(_behaviorEventToBatchMap(tsMs, event));
      return;
    }

    _lastPushedTsMs = tsMs;
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
        if (_logTickHsiJson) {
          SynheartLogger.log('[Runtime] HSI (tick result): $hsiJson');
        }
        _hsiStream.add(hsiJson);
      }
    });
    SynheartLogger.log('[RuntimeModule] Tick timer started (after first push)');
  }
}
