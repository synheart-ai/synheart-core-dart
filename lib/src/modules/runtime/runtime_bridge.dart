import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../core/defaults.dart';
import '../../core/logger.dart';

// --- C function typedefs (native signatures) ---

typedef _RuntimeNewC = Pointer<Void> Function(Pointer<Utf8> configJson);
typedef _RuntimeNewDart = Pointer<Void> Function(Pointer<Utf8> configJson);

typedef _RuntimeFreeC = Void Function(Pointer<Void> handle);
typedef _RuntimeFreeDart = void Function(Pointer<Void> handle);

typedef _RuntimePushRrC =
    Void Function(Pointer<Void> handle, Int64 tsMs, Double rrMs);
typedef _RuntimePushRrDart =
    void Function(Pointer<Void> handle, int tsMs, double rrMs);

typedef _RuntimePushHrC =
    Void Function(Pointer<Void> handle, Int64 tsMs, Double bpm);
typedef _RuntimePushHrDart =
    void Function(Pointer<Void> handle, int tsMs, double bpm);

typedef _RuntimePushAccelC =
    Void Function(
      Pointer<Void> handle,
      Int64 tsMs,
      Double x,
      Double y,
      Double z,
    );
typedef _RuntimePushAccelDart =
    void Function(Pointer<Void> handle, int tsMs, double x, double y, double z);

typedef _RuntimePushBehaviorC =
    Void Function(
      Pointer<Void> handle,
      Int64 tsMs,
      Int32 eventType,
      Double value,
    );
typedef _RuntimePushBehaviorDart =
    void Function(Pointer<Void> handle, int tsMs, int eventType, double value);

typedef _RuntimeTickC =
    Pointer<Utf8> Function(Pointer<Void> handle, Int64 nowMs);
typedef _RuntimeTickDart =
    Pointer<Utf8> Function(Pointer<Void> handle, int nowMs);

typedef _RuntimeLastQualityC = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _RuntimeLastQualityDart = Pointer<Utf8> Function(Pointer<Void> handle);

typedef _RuntimeLastHsvC = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _RuntimeLastHsvDart = Pointer<Utf8> Function(Pointer<Void> handle);

typedef _RuntimeLastPreprocessedC =
    Pointer<Utf8> Function(Pointer<Void> handle);
typedef _RuntimeLastPreprocessedDart =
    Pointer<Utf8> Function(Pointer<Void> handle);

typedef _RuntimeFrameCountC = Uint64 Function(Pointer<Void> handle);
typedef _RuntimeFrameCountDart = int Function(Pointer<Void> handle);

typedef _RuntimeResetC = Void Function(Pointer<Void> handle);
typedef _RuntimeResetDart = void Function(Pointer<Void> handle);

typedef _RuntimeFreeStringC = Void Function(Pointer<Utf8> ptr);
typedef _RuntimeFreeStringDart = void Function(Pointer<Utf8> ptr);

typedef _RuntimeVersionC = Pointer<Utf8> Function();
typedef _RuntimeVersionDart = Pointer<Utf8> Function();

// Sleep stages
typedef _RuntimePushSleepStagesC =
    Void Function(Pointer<Void> handle, Pointer<Utf8> json);
typedef _RuntimePushSleepStagesDart =
    void Function(Pointer<Void> handle, Pointer<Utf8> json);

// Batch ingest
typedef _RuntimeIngestBatchC =
    Pointer<Utf8> Function(
      Pointer<Void> handle,
      Pointer<Utf8> batchJson,
      Int64 nowMs,
    );
typedef _RuntimeIngestBatchDart =
    Pointer<Utf8> Function(
      Pointer<Void> handle,
      Pointer<Utf8> batchJson,
      int nowMs,
    );

// Diagnostics
typedef _RuntimeLastErrorCodeC = Int32 Function(Pointer<Void> handle);
typedef _RuntimeLastErrorCodeDart = int Function(Pointer<Void> handle);

typedef _RuntimeDiagnosticsJsonC = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _RuntimeDiagnosticsJsonDart =
    Pointer<Utf8> Function(Pointer<Void> handle);

typedef _RuntimeClearDiagnosticsC = Void Function(Pointer<Void> handle);
typedef _RuntimeClearDiagnosticsDart = void Function(Pointer<Void> handle);

// SRM Wearable
typedef _SrmPushWearableDailyValueC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Uint32, Double, Double, Int32);
typedef _SrmPushWearableDailyValueDart = int Function(Pointer<Void>, Pointer<Utf8>, int, double, double, int);

typedef _SrmTriggerWearableRecomputeC = Int32 Function(Pointer<Void>, Int32, Uint32);
typedef _SrmTriggerWearableRecomputeDart = int Function(Pointer<Void>, int, int);

typedef _SrmGetWearableReferenceC = Pointer<Utf8> Function(Pointer<Void>);
typedef _SrmGetWearableReferenceDart = Pointer<Utf8> Function(Pointer<Void>);

// SRM
typedef _RuntimeBaselinesJsonC = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _RuntimeBaselinesJsonDart =
    Pointer<Utf8> Function(Pointer<Void> handle);

typedef _RuntimeBaselineSummaryC = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _RuntimeBaselineSummaryDart =
    Pointer<Utf8> Function(Pointer<Void> handle);

typedef _RuntimeExportSrmSnapshotC =
    Pointer<Utf8> Function(Pointer<Void> handle);
typedef _RuntimeExportSrmSnapshotDart =
    Pointer<Utf8> Function(Pointer<Void> handle);

typedef _RuntimeLoadSrmSnapshotC =
    Int32 Function(Pointer<Void> handle, Pointer<Utf8> snapshotJson);
typedef _RuntimeLoadSrmSnapshotDart =
    int Function(Pointer<Void> handle, Pointer<Utf8> snapshotJson);

// Lab
typedef _LabStartC =
    Pointer<Utf8> Function(
      Pointer<Void> handle,
      Pointer<Utf8> protocolJson,
      Int64 startedAtMs,
    );
typedef _LabStartDart =
    Pointer<Utf8> Function(
      Pointer<Void> handle,
      Pointer<Utf8> protocolJson,
      int startedAtMs,
    );

typedef _LabOpenWindowC =
    Pointer<Utf8> Function(
      Pointer<Void> handle,
      Pointer<Utf8> parentId,
      Pointer<Utf8> windowType,
      Pointer<Utf8> label,
      Int64 startedAtMs,
    );
typedef _LabOpenWindowDart =
    Pointer<Utf8> Function(
      Pointer<Void> handle,
      Pointer<Utf8> parentId,
      Pointer<Utf8> windowType,
      Pointer<Utf8> label,
      int startedAtMs,
    );

typedef _LabCloseWindowC =
    Void Function(
      Pointer<Void> handle,
      Pointer<Utf8> windowId,
      Int64 endedAtMs,
    );
typedef _LabCloseWindowDart =
    void Function(Pointer<Void> handle, Pointer<Utf8> windowId, int endedAtMs);

typedef _LabSetWindowValuesC =
    Void Function(
      Pointer<Void> handle,
      Pointer<Utf8> windowId,
      Pointer<Utf8> valuesJson,
    );
typedef _LabSetWindowValuesDart =
    void Function(
      Pointer<Void> handle,
      Pointer<Utf8> windowId,
      Pointer<Utf8> valuesJson,
    );

typedef _LabMergeSessionExtraDataC =
    Pointer<Utf8> Function(Pointer<Void> handle, Pointer<Utf8> patchJson);
typedef _LabMergeSessionExtraDataDart =
    Pointer<Utf8> Function(Pointer<Void> handle, Pointer<Utf8> patchJson);

typedef _LabSetWindowStateOverridesC =
    Void Function(
      Pointer<Void> handle,
      Pointer<Utf8> windowId,
      Pointer<Utf8> overridesJson,
    );
typedef _LabSetWindowStateOverridesDart =
    void Function(
      Pointer<Void> handle,
      Pointer<Utf8> windowId,
      Pointer<Utf8> overridesJson,
    );

typedef _LabFinalizeC =
    Pointer<Utf8> Function(Pointer<Void> handle, Int64 endedAtMs);
typedef _LabFinalizeDart =
    Pointer<Utf8> Function(Pointer<Void> handle, int endedAtMs);

// --- Config ---

/// Configuration passed to `synheart_runtime_new` as JSON.
class RuntimeConfig {
  final int windowMs;
  final int stepMs;
  final String subjectId;
  final String sessionId;
  final bool behaviorEnabled;

  RuntimeConfig({
    this.windowMs = SynheartDefaults.runtimeWindowMs,
    this.stepMs = SynheartDefaults.runtimeStepMs,
    required this.subjectId,
    required this.sessionId,
    this.behaviorEnabled = true,
  });

  Map<String, dynamic> toJson() => {
    'window_ms': windowMs,
    'step_ms': stepMs,
    'subject_id': subjectId,
    'session_id': sessionId,
    'behavior_enabled': behaviorEnabled,
  };
}

// --- RuntimeBridge ---

/// dart:ffi wrapper that binds to the `synheart_runtime_*` C ABI functions.
///
/// Use [createIfAvailable] to attempt loading the native library. If the
/// library is not present on this platform the factory returns `null` and the
/// pipeline is gracefully inert.
class RuntimeBridge {
  final DynamicLibrary _lib;
  final Pointer<Void> _handle;

  late final _RuntimeFreeDart _runtimeFree;
  late final _RuntimePushRrDart _pushRrFfi;
  late final _RuntimePushHrDart _pushHrFfi;
  late final _RuntimePushAccelDart _pushAccelFfi;
  late final _RuntimePushBehaviorDart _pushBehaviorFfi;
  late final _RuntimeTickDart _tickFfi;
  late final _RuntimeLastQualityDart _lastQualityFfi;
  _RuntimeLastHsvDart? _lastHsvFfi;
  _RuntimeLastPreprocessedDart? _lastPreprocessedFfi;
  late final _RuntimeFrameCountDart _frameCountFfi;
  late final _RuntimeResetDart _resetFfi;
  late final _RuntimeFreeStringDart _freeString;

  // Sleep stages (optional — may be missing in older .so)
  _RuntimePushSleepStagesDart? _pushSleepStagesFfi;

  // Batch ingest (optional)
  _RuntimeIngestBatchDart? _ingestBatchFfi;

  // Diagnostics (optional — may be missing in older .so)
  _RuntimeLastErrorCodeDart? _lastErrorCodeFfi;
  _RuntimeDiagnosticsJsonDart? _diagnosticsJsonFfi;
  _RuntimeClearDiagnosticsDart? _clearDiagnosticsFfi;

  // SRM (optional — may be missing in older .so)
  _RuntimeBaselinesJsonDart? _baselinesJsonFfi;
  _RuntimeBaselineSummaryDart? _baselineSummaryFfi;
  _RuntimeExportSrmSnapshotDart? _exportSrmSnapshotFfi;
  _RuntimeLoadSrmSnapshotDart? _loadSrmSnapshotFfi;

  // SRM Wearable (optional)
  _SrmPushWearableDailyValueDart? _pushWearableDailyValueFfi;
  _SrmTriggerWearableRecomputeDart? _triggerWearableRecomputeFfi;
  _SrmGetWearableReferenceDart? _getWearableReferenceFfi;

  // Lab (optional — requires lab feature in runtime .so)
  _LabStartDart? _labStartFfi;
  _LabOpenWindowDart? _labOpenWindowFfi;
  _LabCloseWindowDart? _labCloseWindowFfi;
  _LabSetWindowValuesDart? _labSetWindowValuesFfi;
  _LabMergeSessionExtraDataDart? _labMergeSessionExtraDataFfi;
  _LabSetWindowStateOverridesDart? _labSetWindowStateOverridesFfi;
  _LabFinalizeDart? _labFinalizeFfi;

  RuntimeBridge._(this._lib, this._handle) {
    _runtimeFree = _lib.lookupFunction<_RuntimeFreeC, _RuntimeFreeDart>(
      'synheart_runtime_free',
    );
    _pushRrFfi = _lib.lookupFunction<_RuntimePushRrC, _RuntimePushRrDart>(
      'synheart_runtime_push_rr',
    );
    _pushHrFfi = _lib.lookupFunction<_RuntimePushHrC, _RuntimePushHrDart>(
      'synheart_runtime_push_hr',
    );
    _pushAccelFfi = _lib
        .lookupFunction<_RuntimePushAccelC, _RuntimePushAccelDart>(
          'synheart_runtime_push_accel',
        );
    _pushBehaviorFfi = _lib
        .lookupFunction<_RuntimePushBehaviorC, _RuntimePushBehaviorDart>(
          'synheart_runtime_push_behavior',
        );
    _tickFfi = _lib.lookupFunction<_RuntimeTickC, _RuntimeTickDart>(
      'synheart_runtime_tick',
    );
    _lastQualityFfi = _lib
        .lookupFunction<_RuntimeLastQualityC, _RuntimeLastQualityDart>(
          'synheart_runtime_last_quality',
        );
    _lastHsvFfi = _lookupLastHsv(_lib);
    _lastPreprocessedFfi = _lookupLastPreprocessed(_lib);
    _frameCountFfi = _lib
        .lookupFunction<_RuntimeFrameCountC, _RuntimeFrameCountDart>(
          'synheart_runtime_frame_count',
        );
    _resetFfi = _lib.lookupFunction<_RuntimeResetC, _RuntimeResetDart>(
      'synheart_runtime_reset',
    );
    _freeString = _lib
        .lookupFunction<_RuntimeFreeStringC, _RuntimeFreeStringDart>(
          'synheart_runtime_free_string',
        );
    _pushSleepStagesFfi = _lookupPushSleepStages(_lib);
    _ingestBatchFfi = _lookupIngestBatch(_lib);
    _lastErrorCodeFfi = _lookupLastErrorCode(_lib);
    _diagnosticsJsonFfi = _lookupDiagnosticsJson(_lib);
    _clearDiagnosticsFfi = _lookupClearDiagnostics(_lib);
    _baselinesJsonFfi = _lookupBaselinesJson(_lib);
    _baselineSummaryFfi = _lookupBaselineSummary(_lib);
    _exportSrmSnapshotFfi = _lookupExportSrmSnapshot(_lib);
    _loadSrmSnapshotFfi = _lookupLoadSrmSnapshot(_lib);
    _pushWearableDailyValueFfi = _lookupPushWearableDailyValue(_lib);
    _triggerWearableRecomputeFfi = _lookupTriggerWearableRecompute(_lib);
    _getWearableReferenceFfi = _lookupGetWearableReference(_lib);
    _labStartFfi = _lookupLabStart(_lib);
    _labOpenWindowFfi = _lookupLabOpenWindow(_lib);
    _labCloseWindowFfi = _lookupLabCloseWindow(_lib);
    _labSetWindowValuesFfi = _lookupLabSetWindowValues(_lib);
    _labMergeSessionExtraDataFfi = _lookupLabMergeSessionExtraData(_lib);
    _labSetWindowStateOverridesFfi = _lookupLabSetWindowStateOverrides(_lib);
    _labFinalizeFfi = _lookupLabFinalize(_lib);
    SynheartLogger.log(
      '[RuntimeBridge] Native lib loaded. Lab symbols available: ${_labStartFfi != null} (build runtime with --features lab if false)',
    );
  }

  static _RuntimePushSleepStagesDart? _lookupPushSleepStages(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _RuntimePushSleepStagesC,
        _RuntimePushSleepStagesDart
      >('synheart_runtime_push_sleep_stages');
    } catch (_) {
      return null;
    }
  }

  static _RuntimeIngestBatchDart? _lookupIngestBatch(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<_RuntimeIngestBatchC, _RuntimeIngestBatchDart>(
        'synheart_runtime_ingest_batch_json',
      );
    } catch (_) {
      return null;
    }
  }

  static _RuntimeLastErrorCodeDart? _lookupLastErrorCode(DynamicLibrary lib) {
    try {
      return lib
          .lookupFunction<_RuntimeLastErrorCodeC, _RuntimeLastErrorCodeDart>(
            'synheart_runtime_last_error_code',
          );
    } catch (_) {
      return null;
    }
  }

  static _RuntimeDiagnosticsJsonDart? _lookupDiagnosticsJson(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _RuntimeDiagnosticsJsonC,
        _RuntimeDiagnosticsJsonDart
      >('synheart_runtime_diagnostics_json');
    } catch (_) {
      return null;
    }
  }

  static _RuntimeClearDiagnosticsDart? _lookupClearDiagnostics(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _RuntimeClearDiagnosticsC,
        _RuntimeClearDiagnosticsDart
      >('synheart_runtime_clear_diagnostics');
    } catch (_) {
      return null;
    }
  }

  static _RuntimeLastHsvDart? _lookupLastHsv(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<_RuntimeLastHsvC, _RuntimeLastHsvDart>(
        'synheart_runtime_last_hsv',
      );
    } catch (_) {
      return null;
    }
  }

  static _RuntimeLastPreprocessedDart? _lookupLastPreprocessed(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _RuntimeLastPreprocessedC,
        _RuntimeLastPreprocessedDart
      >('synheart_runtime_last_preprocessed');
    } catch (_) {
      return null;
    }
  }

  static _RuntimeBaselinesJsonDart? _lookupBaselinesJson(DynamicLibrary lib) {
    try {
      return lib
          .lookupFunction<_RuntimeBaselinesJsonC, _RuntimeBaselinesJsonDart>(
            'synheart_runtime_baselines_json',
          );
    } catch (_) {
      return null;
    }
  }

  static _RuntimeBaselineSummaryDart? _lookupBaselineSummary(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _RuntimeBaselineSummaryC,
        _RuntimeBaselineSummaryDart
      >('synheart_runtime_baseline_summary');
    } catch (_) {
      return null;
    }
  }

  static _RuntimeExportSrmSnapshotDart? _lookupExportSrmSnapshot(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _RuntimeExportSrmSnapshotC,
        _RuntimeExportSrmSnapshotDart
      >('synheart_runtime_export_srm_snapshot');
    } catch (_) {
      return null;
    }
  }

  static _RuntimeLoadSrmSnapshotDart? _lookupLoadSrmSnapshot(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _RuntimeLoadSrmSnapshotC,
        _RuntimeLoadSrmSnapshotDart
      >('synheart_runtime_load_srm_snapshot');
    } catch (_) {
      return null;
    }
  }

  // SRM Wearable lookups

  static _SrmPushWearableDailyValueDart? _lookupPushWearableDailyValue(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _SrmPushWearableDailyValueC,
        _SrmPushWearableDailyValueDart
      >('synheart_srm_push_wearable_daily_value');
    } catch (_) {
      return null;
    }
  }

  static _SrmTriggerWearableRecomputeDart? _lookupTriggerWearableRecompute(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _SrmTriggerWearableRecomputeC,
        _SrmTriggerWearableRecomputeDart
      >('synheart_srm_trigger_wearable_recompute');
    } catch (_) {
      return null;
    }
  }

  static _SrmGetWearableReferenceDart? _lookupGetWearableReference(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _SrmGetWearableReferenceC,
        _SrmGetWearableReferenceDart
      >('synheart_srm_get_wearable_reference');
    } catch (_) {
      return null;
    }
  }

  // Lab lookups

  static _LabStartDart? _lookupLabStart(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<_LabStartC, _LabStartDart>(
        'synheart_lab_start',
      );
    } catch (_) {
      return null;
    }
  }

  static _LabOpenWindowDart? _lookupLabOpenWindow(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<_LabOpenWindowC, _LabOpenWindowDart>(
        'synheart_lab_open_window',
      );
    } catch (_) {
      return null;
    }
  }

  static _LabCloseWindowDart? _lookupLabCloseWindow(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<_LabCloseWindowC, _LabCloseWindowDart>(
        'synheart_lab_close_window',
      );
    } catch (_) {
      return null;
    }
  }

  static _LabSetWindowValuesDart? _lookupLabSetWindowValues(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<_LabSetWindowValuesC, _LabSetWindowValuesDart>(
        'synheart_lab_set_window_values',
      );
    } catch (_) {
      return null;
    }
  }

  static _LabMergeSessionExtraDataDart? _lookupLabMergeSessionExtraData(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _LabMergeSessionExtraDataC,
        _LabMergeSessionExtraDataDart
      >('synheart_lab_merge_session_extra_data');
    } catch (_) {
      return null;
    }
  }

  static _LabSetWindowStateOverridesDart? _lookupLabSetWindowStateOverrides(
    DynamicLibrary lib,
  ) {
    try {
      return lib.lookupFunction<
        _LabSetWindowStateOverridesC,
        _LabSetWindowStateOverridesDart
      >('synheart_lab_set_window_state_overrides');
    } catch (_) {
      return null;
    }
  }

  static _LabFinalizeDart? _lookupLabFinalize(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<_LabFinalizeC, _LabFinalizeDart>(
        'synheart_lab_finalize',
      );
    } catch (_) {
      return null;
    }
  }

  /// Create a [RuntimeBridge] if the native library is available, otherwise null.
  static RuntimeBridge? createIfAvailable(RuntimeConfig config) {
    try {
      final lib = _loadLibrary();
      if (lib == null) {
        SynheartLogger.log(
          '[RuntimeBridge] libsynheart_runtime.so not loaded — check that the .so is in the app (e.g. example/android/app/src/main/jniLibs/<abi>/) and do a clean build.',
        );
        return null;
      }

      final runtimeNew = lib.lookupFunction<_RuntimeNewC, _RuntimeNewDart>(
        'synheart_runtime_new',
      );

      final configJson = jsonEncode(config.toJson());
      final configNative = configJson.toNativeUtf8();
      Pointer<Void> handle;
      try {
        handle = runtimeNew(configNative);
      } finally {
        malloc.free(configNative);
      }

      if (handle == nullptr) return null;

      return RuntimeBridge._(lib, handle);
    } catch (e, st) {
      SynheartLogger.log(
        '[RuntimeBridge] createIfAvailable failed: $e',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  static DynamicLibrary? _loadLibrary() {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        return DynamicLibrary.open('libsynheart_runtime.so');
      } else if (Platform.isIOS) {
        return DynamicLibrary.process();
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('libsynheart_runtime.dylib');
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('synheart_runtime.dll');
      }
      return null;
    } catch (e, st) {
      SynheartLogger.log(
        '[RuntimeBridge] Failed to load libsynheart_runtime: $e',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Push an RR-interval sample into the runtime.
  void pushRr(int tsMs, double rrMs) {
    _pushRrFfi(_handle, tsMs, rrMs);
  }

  /// Push a heart-rate sample into the runtime.
  void pushHr(int tsMs, double bpm) {
    _pushHrFfi(_handle, tsMs, bpm);
  }

  /// Push a 3-axis accelerometer sample into the runtime.
  void pushAccel(int tsMs, double x, double y, double z) {
    _pushAccelFfi(_handle, tsMs, x, y, z);
  }

  /// Push a behavioral event into the runtime.
  void pushBehavior(int tsMs, int eventType, double value) {
    _pushBehaviorFfi(_handle, tsMs, eventType, value);
  }

  /// Push vendor-reported sleep stage data as JSON.
  ///
  /// JSON fields (all optional): `total_sleep_minutes`, `time_in_bed_minutes`,
  /// `deep_sleep_minutes`, `rem_sleep_minutes`, `awake_minutes`, `awakenings`,
  /// `vendor_sleep_score`, `vendor_recovery_score`, `vendor_strain_score`.
  ///
  /// Returns false if the symbol is not present in the loaded .so.
  bool pushSleepStages(String json) {
    final ffi = _pushSleepStagesFfi;
    if (ffi == null) return false;
    final native = json.toNativeUtf8();
    try {
      ffi(_handle, native);
      return true;
    } finally {
      malloc.free(native);
    }
  }

  /// Ingest a JSON array of events and tick once. Returns output bundle JSON.
  ///
  /// Supported event forms:
  /// - `{"type":"rr","ts_ms":123,"rr_ms":800.0}`
  /// - `{"type":"hr","ts_ms":123,"bpm":72.0}`
  /// - `{"type":"accel","ts_ms":123,"x":0.01,"y":0.02,"z":0.98}`
  /// - `{"type":"behavior","ts_ms":123,"event_type":2,"value":1.0}`
  /// - `{"type":"sleep_stages","total_sleep_minutes":420,...}`
  ///
  /// Returns null if the symbol is not present in the loaded .so.
  /// Ingetst for runtime
  String? ingestBatch(String batchJson, int nowMs) {
    final ffi = _ingestBatchFfi;
    if (ffi == null) return null;
    final native = batchJson.toNativeUtf8();
    try {
      final resultPtr = ffi(_handle, native, nowMs);
      if (resultPtr == nullptr) return null;
      final json = resultPtr.toDartString();
      _freeString(resultPtr);
      return json;
    } finally {
      malloc.free(native);
    }
  }

  /// Advance the runtime clock and return HSI JSON if a new frame was produced.
  ///
  /// Returns `null` when the runtime has not accumulated enough data to emit
  /// a new frame since the last tick.
  String? tick(int nowMs) {
    final resultPtr = _tickFfi(_handle, nowMs);
    if (resultPtr == nullptr) return null;
    final json = resultPtr.toDartString();
    _freeString(resultPtr);
    return json;
  }

  /// Return the latest quality-assessment JSON, or `null` if unavailable.
  String? lastQuality() {
    final resultPtr = _lastQualityFfi(_handle);
    if (resultPtr == nullptr) return null;
    final json = resultPtr.toDartString();
    _freeString(resultPtr);
    return json;
  }

  /// Return the latest HSV (Human State Vector) values as JSON, or `null`
  /// if no window has completed yet.
  ///
  /// The JSON contains per-head values (emotion, focus, capacity, recovery,
  /// strain, sleep) with confidence and inference metadata. This is the
  /// canonical source for all HSV data — SDK-side head computation is
  /// deprecated in favour of this endpoint.
  ///
  /// Returns `null` if the native runtime does not export this symbol (older .so).
  String? lastHsv() {
    final ffi = _lastHsvFfi;
    if (ffi == null) return null;
    final resultPtr = ffi(_handle);
    if (resultPtr == nullptr) return null;
    final json = resultPtr.toDartString();
    _freeString(resultPtr);
    return json;
  }

  /// Get the last pre-processed window as JSON (internal use only).
  ///
  /// Returns `null` if no window has completed yet, or if the symbol is not
  /// present in the loaded .so.
  String? lastPreprocessed() {
    final ffi = _lastPreprocessedFfi;
    if (ffi == null) return null;
    final resultPtr = ffi(_handle);
    if (resultPtr == nullptr) return null;
    final json = resultPtr.toDartString();
    _freeString(resultPtr);
    return json;
  }

  /// Number of HSI frames produced so far.
  int frameCount() {
    return _frameCountFfi(_handle);
  }

  /// Reset the runtime state (clears all internal buffers).
  void reset() {
    _resetFfi(_handle);
  }

  // -- Diagnostics --

  /// Get the last recorded error code (0 = no error).
  ///
  /// Error codes: 1001=out-of-order, 1002=concurrent call, 2001=flux error,
  /// 3001=SRM schema mismatch, 3002=SRM config mismatch, 3003=SRM load failed.
  /// Returns null if the symbol is not present in the loaded .so.
  int? lastErrorCode() {
    final ffi = _lastErrorCodeFfi;
    if (ffi == null) return null;
    return ffi(_handle);
  }

  /// Get diagnostics as compact JSON.
  ///
  /// Example: `{"config_id":"cfg_...","last_error_code":0,"out_of_order_events":0,...}`
  /// Returns null if the symbol is not present in the loaded .so.
  String? diagnosticsJson() {
    final ffi = _diagnosticsJsonFfi;
    if (ffi == null) return null;
    final ptr = ffi(_handle);
    if (ptr == nullptr) return null;
    final json = ptr.toDartString();
    _freeString(ptr);
    return json;
  }

  /// Clear diagnostics counters and last error code.
  void clearDiagnostics() {
    _clearDiagnosticsFfi?.call(_handle);
  }

  // -- SRM Baselines --

  /// Return all SRM baselines as JSON, or `null` if unavailable or symbol not in .so.
  String? baselinesJson() {
    final ffi = _baselinesJsonFfi;
    if (ffi == null) return null;
    final ptr = ffi(_handle);
    if (ptr == nullptr) return null;
    final json = ptr.toDartString();
    _freeString(ptr);
    return json;
  }

  /// Return baseline summary as JSON: `{"total":14,"ready":0,"warming":5,"empty":9}`.
  /// Returns `null` if symbol not in .so.
  String? baselineSummary() {
    final ffi = _baselineSummaryFfi;
    if (ffi == null) return null;
    final ptr = ffi(_handle);
    if (ptr == nullptr) return null;
    final json = ptr.toDartString();
    _freeString(ptr);
    return json;
  }

  /// Export the SRM snapshot as JSON for persistence, or `null`.
  /// Used by RuntimeModule for auto-save/load lifecycle.
  /// Returns `null` if symbol not in .so.
  String? exportSrmSnapshot() {
    final ffi = _exportSrmSnapshotFfi;
    if (ffi == null) return null;
    final ptr = ffi(_handle);
    if (ptr == nullptr) return null;
    final json = ptr.toDartString();
    _freeString(ptr);
    return json;
  }

  /// Load an SRM snapshot from JSON. Returns 0 on success, error code on failure.
  /// Returns -1 if the symbol is not present in the loaded .so.
  /// Used by RuntimeModule for auto-save/load lifecycle.
  int loadSrmSnapshot(String json) {
    final ffi = _loadSrmSnapshotFfi;
    if (ffi == null) return -1;
    final native = json.toNativeUtf8();
    try {
      return ffi(_handle, native);
    } finally {
      malloc.free(native);
    }
  }

  // -- SRM Wearable --

  int? pushWearableDailyValue(String dimension, int dayIndex, double value, double confidence, int fidelity) {
    final ffi = _pushWearableDailyValueFfi;
    if (ffi == null) return null;
    final native = dimension.toNativeUtf8();
    try {
      return ffi(_handle, native, dayIndex, value, confidence, fidelity);
    } finally {
      malloc.free(native);
    }
  }

  int? triggerWearableRecompute(int triggerType, int asOfDay) {
    final ffi = _triggerWearableRecomputeFfi;
    if (ffi == null) return null;
    return ffi(_handle, triggerType, asOfDay);
  }

  String? getWearableReference() {
    final ffi = _getWearableReferenceFfi;
    if (ffi == null) return null;
    final ptr = ffi(_handle);
    if (ptr == nullptr) return null;
    final result = ptr.toDartString();
    _freeString(ptr);
    return result;
  }

  // -- Lab Session --

  /// Whether the lab C ABI symbols are available in the loaded native library.
  bool get isLabAvailable => _labStartFfi != null;

  /// Start a lab session.
  ///
  /// [protocolJson] should contain: `namespace`, `protocol_version`, `parameters`,
  /// and optionally `app_id`, `device_id`, `user_id`, `protocol_id`.
  ///
  /// Returns `null` on success, or an error string on failure.
  String? labStart(String protocolJson, int startedAtMs) {
    final ffi = _labStartFfi;
    if (ffi == null) return 'lab symbols not available';
    final native = protocolJson.toNativeUtf8();
    try {
      final ptr = ffi(_handle, native, startedAtMs);
      if (ptr == nullptr) return null; // success
      final err = ptr.toDartString();
      _freeString(ptr);
      return err;
    } finally {
      malloc.free(native);
    }
  }

  /// Open a window in the active lab session. Returns the window ID, or `null` on failure.
  String? labOpenWindow({
    String? parentId,
    required String windowType,
    String? label,
    required int startedAtMs,
  }) {
    final ffi = _labOpenWindowFfi;
    if (ffi == null) return null;
    final pidNative = (parentId ?? '').toNativeUtf8();
    final wtNative = windowType.toNativeUtf8();
    final lblNative = (label ?? '').toNativeUtf8();
    try {
      final ptr = ffi(
        _handle,
        parentId != null ? pidNative : nullptr,
        wtNative,
        label != null ? lblNative : nullptr,
        startedAtMs,
      );
      if (ptr == nullptr) return null;
      final windowId = ptr.toDartString();
      _freeString(ptr);
      return windowId;
    } finally {
      malloc.free(pidNative);
      malloc.free(wtNative);
      malloc.free(lblNative);
    }
  }

  /// Close a window in the active lab session.
  void labCloseWindow(String windowId, int endedAtMs) {
    final ffi = _labCloseWindowFfi;
    if (ffi == null) return;
    final native = windowId.toNativeUtf8();
    try {
      ffi(_handle, native, endedAtMs);
    } finally {
      malloc.free(native);
    }
  }

  /// Set protocol-specific values on a lab window.
  void labSetWindowValues(String windowId, String valuesJson) {
    final ffi = _labSetWindowValuesFfi;
    if (ffi == null) return;
    final widNative = windowId.toNativeUtf8();
    final vjNative = valuesJson.toNativeUtf8();
    try {
      ffi(_handle, widNative, vjNative);
    } finally {
      malloc.free(widNative);
      malloc.free(vjNative);
    }
  }

  /// Merge session-level metadata into `session_metadata.extra_data`.
  ///
  /// [patchJson] must be a JSON object at the root.
  /// Returns `null` on success, or an error string on failure.
  String? labMergeSessionExtraData(String patchJson) {
    final ffi = _labMergeSessionExtraDataFfi;
    if (ffi == null) return 'lab merge_session_extra_data symbol not available';
    final native = patchJson.toNativeUtf8();
    try {
      final ptr = ffi(_handle, native);
      if (ptr == nullptr) return null; // success
      final err = ptr.toDartString();
      _freeString(ptr);
      return err;
    } finally {
      malloc.free(native);
    }
  }

  /// Set state-data overrides for a lab window before closing it.
  ///
  /// [overridesJson] should be a JSON object containing optional:
  /// `device_context`, `system_state`, `session_spacing`.
  void labSetWindowStateOverrides(String windowId, String overridesJson) {
    final ffi = _labSetWindowStateOverridesFfi;
    if (ffi == null) return;
    final widNative = windowId.toNativeUtf8();
    final ovNative = overridesJson.toNativeUtf8();
    try {
      ffi(_handle, widNative, ovNative);
    } finally {
      malloc.free(widNative);
      malloc.free(ovNative);
    }
  }

  /// Finalize the lab session and return the complete payload JSON.
  /// Returns `null` if no active session or lab symbols not available.
  String? labFinalize(int endedAtMs) {
    final ffi = _labFinalizeFfi;
    if (ffi == null) return null;
    final ptr = ffi(_handle, endedAtMs);
    if (ptr == nullptr) return null;
    final json = ptr.toDartString();
    _freeString(ptr);
    return json;
  }

  /// Release the native runtime handle. Must be called when the bridge
  /// is no longer needed to avoid leaking native memory.
  void dispose() {
    _runtimeFree(_handle);
  }

  /// Return the native library version string.
  ///
  /// This is a static helper that loads the library solely to read the version.
  /// Returns `null` if the library is unavailable.
  static String? version() {
    try {
      final lib = _loadLibrary();
      if (lib == null) return null;
      final versionFfi = lib
          .lookupFunction<_RuntimeVersionC, _RuntimeVersionDart>(
            'synheart_runtime_version',
          );
      final freeStringFfi = lib
          .lookupFunction<_RuntimeFreeStringC, _RuntimeFreeStringDart>(
            'synheart_runtime_free_string',
          );
      final ptr = versionFfi();
      if (ptr == nullptr) return null;
      final v = ptr.toDartString();
      freeStringFfi(ptr);
      return v;
    } catch (_) {
      return null;
    }
  }
}
