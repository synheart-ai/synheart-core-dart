// import 'dart:async';
// import 'dart:convert';

// import 'package:flutter/foundation.dart' show debugPrint;
// import 'package:shared_preferences/shared_preferences.dart';

// import 'runtime_bridge.dart';

// /// Manages the synheart-runtime lifecycle using batch ingest.
// ///
// /// Collects sensor events into a buffer and periodically submits them
// /// to the native runtime via [RuntimeBridge.ingestBatch]. Each batch
// /// call may produce an HSI snapshot, which is emitted on [onHsi].
// ///
// /// **Flush rule:** Batch ingestion is called:
// /// - Every [flushIntervalSeconds] while [start] is active (time-based), and
// /// - Immediately when the buffer size reaches [maxBufferSize] (if set), and
// /// - On [stop] / [dispose] (final flush before persisting SRM).
// ///
// /// When "End session" is triggered, call [stop] (or [dispose] if tearing down).
// /// [stop] performs a final [flush], then persists SRM baselines for the next session.
// class SynheartBatchRuntime {
//   final RuntimeBridge? _bridge;
//   final String _srmSnapshotKey;
//   final int? _maxBufferSize;

//   /// Buffered events waiting to be submitted in the next batch.
//   final List<Map<String, dynamic>> _eventBuffer = [];

//   /// Periodic timer that flushes the event buffer to the runtime.
//   Timer? _flushTimer;

//   /// Callback invoked each time an HSI frame is produced.
//   void Function(Map<String, dynamic> hsi, Map<String, dynamic>? hsv)? onHsi;

//   /// Callback invoked each time a batch result is received (even without HSI).
//   void Function(Map<String, dynamic> result)? onBatchResult;

//   /// Creates a batch-based runtime.
//   ///
//   /// [subjectId] and [sessionId] identify the subject and session for the native runtime.
//   /// [flushIntervalSeconds] is used when [start] is called (default 5).
//   /// [maxBufferSize] if set, triggers an immediate flush when the buffer reaches this size (e.g. 500).
//   SynheartBatchRuntime({
//     required String subjectId,
//     required String sessionId,
//     int windowMs = 30000,
//     int stepMs = 30000,
//     bool behaviorEnabled = true,
//     String srmSnapshotKey = 'synheart.srm_snapshot',
//     int? maxBufferSize,
//   })  : _srmSnapshotKey = srmSnapshotKey,
//         _maxBufferSize = maxBufferSize,
//         _bridge = RuntimeBridge.createIfAvailable(RuntimeConfig(
//           windowMs: windowMs,
//           stepMs: stepMs,
//           subjectId: subjectId,
//           sessionId: sessionId,
//           behaviorEnabled: behaviorEnabled,
//         ));

//   /// Whether the native runtime loaded successfully.
//   bool get isAvailable => _bridge != null;

//   /// Whether the flush timer is active (after [start], before [stop]).
//   bool get isRunning => _flushTimer != null;

//   // ---------------------------------------------------------------------------
//   // Lifecycle
//   // ---------------------------------------------------------------------------

//   /// Initialize the runtime and restore baselines from the previous session.
//   /// Call this once during app startup, before [start].
//   Future<void> initialize() async {
//     if (_bridge == null) return;

//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final saved = prefs.getString(_srmSnapshotKey);
//       if (saved != null) {
//         final code = _bridge.loadSrmSnapshot(saved);
//         debugPrint(
//           '[SynheartBatchRuntime] SRM restore: ${code == 0 ? "ok" : "failed ($code)"}',
//         );
//       }
//     } catch (e) {
//       debugPrint('[SynheartBatchRuntime] SRM restore error: $e');
//     }
//   }

//   /// Start the periodic flush timer. Events pushed after this will be
//   /// batched and submitted every [flushIntervalSeconds], or when buffer
//   /// reaches [maxBufferSize] if set.
//   void start({int flushIntervalSeconds = 5}) {
//     if (_bridge == null) return;

//     _flushTimer?.cancel();
//     _flushTimer = Timer.periodic(
//       Duration(seconds: flushIntervalSeconds),
//       (_) => flush(),
//     );
//     debugPrint(
//       '[SynheartBatchRuntime] started — flush every ${flushIntervalSeconds}s'
//       '${_maxBufferSize != null ? ", maxBufferSize=$_maxBufferSize" : ""}',
//     );
//   }

//   /// Stop the flush timer, perform a final flush, and persist SRM baselines.
//   ///
//   /// Call this when the user clicks "End session" (or equivalent). This ensures
//   /// any buffered events are sent and baselines are saved for the next session.
//   Future<void> stop() async {
//     _flushTimer?.cancel();
//     _flushTimer = null;

//     debugPrint('[SynheartBatchRuntime] stop — final flush then persist SRM');
//     flush();

//     await _persistBaselines();
//   }

//   /// Release the native handle. Call when the runtime is no longer needed.
//   /// For "End session" flow, prefer [stop] first to flush and persist, then [dispose] when tearing down.
//   void dispose() {
//     _flushTimer?.cancel();
//     _flushTimer = null;
//     _eventBuffer.clear();
//     _bridge?.dispose();
//   }

//   // ---------------------------------------------------------------------------
//   // Event collection
//   // ---------------------------------------------------------------------------

//   void _maybeFlushOnBufferSize() {
//     if (_maxBufferSize == null || _flushTimer == null) return;
//     if (_eventBuffer.length >= _maxBufferSize) flush();
//   }

//   /// Add an RR interval event to the buffer.
//   void addRr(int tsMs, double rrMs) {
//     _eventBuffer.add({'type': 'rr', 'ts_ms': tsMs, 'rr_ms': rrMs});
//     _maybeFlushOnBufferSize();
//   }

//   /// Add a heart rate event to the buffer (use when RR is not available).
//   void addHr(int tsMs, double bpm) {
//     _eventBuffer.add({'type': 'hr', 'ts_ms': tsMs, 'bpm': bpm});
//     _maybeFlushOnBufferSize();
//   }

//   /// Add an accelerometer event (x, y, z in g-force).
//   void addAccel(int tsMs, double x, double y, double z) {
//     _eventBuffer.add({'type': 'accel', 'ts_ms': tsMs, 'x': x, 'y': y, 'z': z});
//     _maybeFlushOnBufferSize();
//   }

//   /// Add a behavior event. [eventType]: 0=ScreenOn, 1=ScreenOff, 2=Touch, 3=AppSwitch,
//   /// 4=NotificationReceived, 5=Scroll, 6=Swipe, 7=Call.
//   void addBehavior(int tsMs, int eventType, {double value = 1.0}) {
//     _eventBuffer.add({
//       'type': 'behavior',
//       'ts_ms': tsMs,
//       'event_type': eventType,
//       'value': value,
//     });
//     _maybeFlushOnBufferSize();
//   }

//   void addScreenOn(int tsMs) => addBehavior(tsMs, 0);
//   void addScreenOff(int tsMs) => addBehavior(tsMs, 1);
//   void addTouch(int tsMs) => addBehavior(tsMs, 2);
//   void addAppSwitch(int tsMs) => addBehavior(tsMs, 3);
//   void addNotification(int tsMs) => addBehavior(tsMs, 4);
//   void addScroll(int tsMs, {double velocity = 1.0}) =>
//       addBehavior(tsMs, 5, value: velocity);
//   void addSwipe(int tsMs, {double velocity = 1.0}) =>
//       addBehavior(tsMs, 6, value: velocity);
//   void addCall(int tsMs) => addBehavior(tsMs, 7);

//   /// Add overnight sleep summary. Call once per day; each call replaces previous sleep data.
//   void addSleepStages({
//     double? totalSleepMinutes,
//     double? timeInBedMinutes,
//     double? deepSleepMinutes,
//     double? remSleepMinutes,
//     double? awakeMinutes,
//     int? awakenings,
//     double? vendorSleepScore,
//     double? vendorRecoveryScore,
//     double? vendorStrainScore,
//   }) {
//     final event = <String, dynamic>{'type': 'sleep_stages'};
//     if (totalSleepMinutes != null) {
//       event['total_sleep_minutes'] = totalSleepMinutes;
//     }
//     if (timeInBedMinutes != null) {
//       event['time_in_bed_minutes'] = timeInBedMinutes;
//     }
//     if (deepSleepMinutes != null) {
//       event['deep_sleep_minutes'] = deepSleepMinutes;
//     }
//     if (remSleepMinutes != null) {
//       event['rem_sleep_minutes'] = remSleepMinutes;
//     }
//     if (awakeMinutes != null) event['awake_minutes'] = awakeMinutes;
//     if (awakenings != null) event['awakenings'] = awakenings;
//     if (vendorSleepScore != null) {
//       event['vendor_sleep_score'] = vendorSleepScore;
//     }
//     if (vendorRecoveryScore != null) {
//       event['vendor_recovery_score'] = vendorRecoveryScore;
//     }
//     if (vendorStrainScore != null) {
//       event['vendor_strain_score'] = vendorStrainScore;
//     }
//     _eventBuffer.add(event);
//     _maybeFlushOnBufferSize();
//   }

//   // ---------------------------------------------------------------------------
//   // Flush (batch submit)
//   // ---------------------------------------------------------------------------

//   /// Flush the event buffer to the runtime. Produces HSI if a window completes.
//   /// Called automatically by the timer and on [stop]; can also be called manually.
//   void flush() {
//     if (_bridge == null || _eventBuffer.isEmpty) return;

//     final eventCount = _eventBuffer.length;
//     _eventBuffer.sort((a, b) {
//       final aTs = a['ts_ms'] as int? ?? 0;
//       final bTs = b['ts_ms'] as int? ?? 0;
//       return aTs.compareTo(bTs);
//     });

//     final nowMs = DateTime.now().millisecondsSinceEpoch;
//     final batchJson = jsonEncode(_eventBuffer);
//     _eventBuffer.clear();

//     debugPrint(
//       '[SynheartBatchRuntime] flush: sending $eventCount events, nowMs=$nowMs',
//     );

//     final resultJson = _bridge.ingestBatch(batchJson, nowMs);
//     if (resultJson == null) {
//       debugPrint('[SynheartBatchRuntime] ingestBatch returned null (symbol not available?)');
//       return;
//     }

//     final result = jsonDecode(resultJson) as Map<String, dynamic>;
//     final applied = result['applied'] as int? ?? 0;
//     final ignored = result['ignored'] as int? ?? 0;
//     final ok = result['ok'] == true;
//     final hasHsi = result['hsi'] != null;
//     final frameCountVal = result['frame_count'] as int? ?? _bridge.frameCount();
//     final lastError = result['last_error_code'] as int? ?? _bridge.lastErrorCode() ?? 0;

//     debugPrint(
//       '[SynheartBatchRuntime] batch result: ok=$ok applied=$applied ignored=$ignored '
//       'hsi=${hasHsi ? "yes" : "no"} frame_count=$frameCountVal last_error_code=$lastError',
//     );

//     if (!hasHsi) {
//       if (lastError == 2001) {
//         debugPrint(
//           '[SynheartBatchRuntime] No HSI: ERR_FLUX (2001) — window may have insufficient data or Flux failed. '
//           'Need at least window_ms of data (e.g. 10–30s) with enough RR/HR samples.',
//         );
//       } else if (frameCountVal == 0) {
//         debugPrint(
//           '[SynheartBatchRuntime] No HSI yet: not enough data to complete first window. '
//           'Keep session running longer (e.g. 15–30s with wear + behavior).',
//         );
//       }
//     }

//     if (hasHsi && result['hsv'] != null) {
//       final hsv = result['hsv'] as Map<String, dynamic>;
//       final focus = hsv['focus']?['value'];
//       final strain = hsv['strain']?['value'];
//       final emotion = hsv['emotion'];
//       debugPrint(
//         '[SynheartBatchRuntime] HSI produced — focus=$focus strain=$strain emotion=$emotion',
//       );
//     }

//     onBatchResult?.call(result);

//     if (result['ok'] == true && result['hsi'] != null) {
//       onHsi?.call(
//         result['hsi'] as Map<String, dynamic>,
//         result['hsv'] as Map<String, dynamic>?,
//       );
//     }

//     _drainRemainingWindows(nowMs);
//   }

//   void _drainRemainingWindows(int nowMs) {
//     var drained = 0;
//     while (true) {
//       final hsiJson = _bridge?.tick(nowMs);
//       if (hsiJson == null) break;

//       drained++;
//       final hsi = jsonDecode(hsiJson) as Map<String, dynamic>;
//       final hsv = _bridge?.lastHsv();
//       final hsvMap =
//           hsv != null ? jsonDecode(hsv) as Map<String, dynamic>? : null;

//       if (hsvMap != null) {
//         final focus = hsvMap['focus']?['value'];
//         final strain = hsvMap['strain']?['value'];
//         debugPrint(
//           '[SynheartBatchRuntime] drain window #$drained — focus=$focus strain=$strain',
//         );
//       } else {
//         debugPrint('[SynheartBatchRuntime] drain window #$drained');
//       }

//       onHsi?.call(hsi, hsvMap);
//     }
//     if (drained > 0) {
//       debugPrint('[SynheartBatchRuntime] drained $drained additional HSI window(s)');
//     }
//   }

//   // ---------------------------------------------------------------------------
//   // Queries
//   // ---------------------------------------------------------------------------

//   int get frameCount => _bridge?.frameCount() ?? 0;

//   Map<String, dynamic>? get lastQuality {
//     final json = _bridge?.lastQuality();
//     return json != null ? jsonDecode(json) as Map<String, dynamic> : null;
//   }

//   Map<String, dynamic>? get lastHsv {
//     final json = _bridge?.lastHsv();
//     return json != null ? jsonDecode(json) as Map<String, dynamic> : null;
//   }

//   Map<String, dynamic>? get baselineSummary {
//     final json = _bridge?.baselineSummary();
//     return json != null ? jsonDecode(json) as Map<String, dynamic> : null;
//   }

//   int get lastErrorCode => _bridge?.lastErrorCode() ?? 0;

//   Map<String, dynamic>? get diagnostics {
//     final json = _bridge?.diagnosticsJson();
//     return json != null ? jsonDecode(json) as Map<String, dynamic> : null;
//   }

//   /// Reset the pipeline (clears all buffers, baselines, frame count).
//   void reset() {
//     _eventBuffer.clear();
//     _bridge?.reset();
//   }

//   // ---------------------------------------------------------------------------
//   // SRM persistence
//   // ---------------------------------------------------------------------------

//   Future<void> _persistBaselines() async {
//     if (_bridge == null) return;
//     try {
//       final snapshot = _bridge.exportSrmSnapshot();
//       if (snapshot != null) {
//         final prefs = await SharedPreferences.getInstance();
//         await prefs.setString(_srmSnapshotKey, snapshot);
//         debugPrint('[SynheartBatchRuntime] SRM baselines saved');
//       }
//     } catch (e) {
//       debugPrint('[SynheartBatchRuntime] SRM save error: $e');
//     }
//   }
// }
