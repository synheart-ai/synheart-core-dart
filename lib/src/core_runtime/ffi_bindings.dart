/// dart:ffi bindings to `synheart_core_runtime` C ABI.
///
/// Loads the native library and resolves `synheart_core_*` symbols.
/// Used by [CoreRuntimeBridge] — not called directly by app code.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'sdk_ffi.dart';

// ── C function typedefs (native + Dart) ─────────────────────────────────

// Handle lifecycle
typedef _NewC = Pointer<Void> Function(Pointer<Utf8> configJson);
typedef _NewDart = Pointer<Void> Function(Pointer<Utf8> configJson);
typedef _FreeC = Void Function(Pointer<Void> handle);
typedef _FreeDart = void Function(Pointer<Void> handle);
typedef _FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef _FreeStringDart = void Function(Pointer<Utf8> ptr);

// Session
typedef _StartSessionC = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _StartSessionDart = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _StopSessionC = Int32 Function(Pointer<Void> handle);
typedef _StopSessionDart = int Function(Pointer<Void> handle);
typedef _CurrentSessionC = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _CurrentSessionDart = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _IsRunningC = Int32 Function(Pointer<Void> handle);
typedef _IsRunningDart = int Function(Pointer<Void> handle);

// Sensor push
typedef _PushRrC = Void Function(Pointer<Void> h, Int64 ts, Double rr);
typedef _PushRrDart = void Function(Pointer<Void> h, int ts, double rr);
typedef _PushHrC = Void Function(Pointer<Void> h, Int64 ts, Double bpm);
typedef _PushHrDart = void Function(Pointer<Void> h, int ts, double bpm);
typedef _EnsurePipelineC = Void Function(Pointer<Void> h);
typedef _EnsurePipelineDart = void Function(Pointer<Void> h);
typedef _TickC = Pointer<Utf8> Function(Pointer<Void> h, Int64 nowMs);
typedef _TickDart = Pointer<Utf8> Function(Pointer<Void> h, int nowMs);
typedef _PushVendorHrvC = Void Function(
    Pointer<Void> h, Int64 ts, Double rmssd, Double sdnn, Double stress, Double recovery);
typedef _PushVendorHrvDart = void Function(
    Pointer<Void> h, int ts, double rmssd, double sdnn, double stress, double recovery);
typedef _PushVendorVitalsC = Void Function(
    Pointer<Void> h, Int64 ts, Double spo2, Double respiration);
typedef _PushVendorVitalsDart = void Function(
    Pointer<Void> h, int ts, double spo2, double respiration);
typedef _PushAccelC =
    Void Function(Pointer<Void> h, Int64 ts, Double x, Double y, Double z);
typedef _PushAccelDart =
    void Function(Pointer<Void> h, int ts, double x, double y, double z);
typedef _PushBehaviorC =
    Void Function(Pointer<Void> h, Int64 ts, Int32 t, Double v);
typedef _PushBehaviorDart =
    void Function(Pointer<Void> h, int ts, int t, double v);
typedef _PushSleepC = Void Function(Pointer<Void> h, Pointer<Utf8> json);
typedef _PushSleepDart = void Function(Pointer<Void> h, Pointer<Utf8> json);
typedef _IngestBatchC =
    Pointer<Utf8> Function(Pointer<Void> h, Pointer<Utf8> json, Int64 now);
typedef _IngestBatchDart =
    Pointer<Utf8> Function(Pointer<Void> h, Pointer<Utf8> json, int now);

// Consent
typedef _ConsentStrC = Int32 Function(Pointer<Void> h, Pointer<Utf8> ct);
typedef _ConsentStrDart = int Function(Pointer<Void> h, Pointer<Utf8> ct);
typedef _HasConsentC = Int32 Function(Pointer<Void> h, Pointer<Utf8> ct);
typedef _HasConsentDart = int Function(Pointer<Void> h, Pointer<Utf8> ct);
typedef _CurrentConsentC = Pointer<Utf8> Function(Pointer<Void> h);
typedef _CurrentConsentDart = Pointer<Utf8> Function(Pointer<Void> h);
typedef _ConsentConfigureCloudC =
    Int32 Function(Pointer<Void> h, Pointer<Utf8> baseUrl, Pointer<Utf8> appId);
typedef _ConsentConfigureCloudDart =
    int Function(Pointer<Void> h, Pointer<Utf8> baseUrl, Pointer<Utf8> appId);
typedef _ConsentSubmitFormC =
    Pointer<Utf8> Function(
      Pointer<Void> h,
      Pointer<Utf8> deviceId,
      Pointer<Utf8> platform,
      Pointer<Utf8> userId,
      Pointer<Utf8> formJson,
    );
typedef _ConsentSubmitFormDart =
    Pointer<Utf8> Function(
      Pointer<Void> h,
      Pointer<Utf8> deviceId,
      Pointer<Utf8> platform,
      Pointer<Utf8> userId,
      Pointer<Utf8> formJson,
    );

// Capability
typedef _LoadCapC =
    Int32 Function(Pointer<Void> h, Pointer<Utf8> tj, Pointer<Utf8> s);
typedef _LoadCapDart =
    int Function(Pointer<Void> h, Pointer<Utf8> tj, Pointer<Utf8> s);

// Queries
typedef _JsonReturnC = Pointer<Utf8> Function(Pointer<Void> h);
typedef _JsonReturnDart = Pointer<Utf8> Function(Pointer<Void> h);

// hsi_history list: (handle, since_unix_ms, limit) -> char* (JSON array)
typedef _HsiHistoryListC = Pointer<Utf8> Function(
    Pointer<Void> h, Int64 sinceMs, Int64 limit);
typedef _HsiHistoryListDart = Pointer<Utf8> Function(
    Pointer<Void> h, int sinceMs, int limit);
// hsi_history count: (handle) -> int64 uses the existing _Int64Return* typedefs.
typedef _SessionIdC =
    Pointer<Utf8> Function(Pointer<Void> h, Pointer<Utf8> sid);
typedef _SessionIdDart =
    Pointer<Utf8> Function(Pointer<Void> h, Pointer<Utf8> sid);
typedef _HsiWindowsC =
    Pointer<Utf8> Function(
      Pointer<Void> h,
      Pointer<Utf8> sid,
      Int64 s,
      Int64 e,
      Int32 l,
    );
typedef _HsiWindowsDart =
    Pointer<Utf8> Function(
      Pointer<Void> h,
      Pointer<Utf8> sid,
      int s,
      int e,
      int l,
    );

// Metrics
typedef _RecordMetricC = Int32 Function(Pointer<Void> h, Pointer<Utf8> json);
typedef _RecordMetricDart = int Function(Pointer<Void> h, Pointer<Utf8> json);

// Deletion
typedef _DeleteSessionC = Int32 Function(Pointer<Void> h, Pointer<Utf8> sid);
typedef _DeleteSessionDart = int Function(Pointer<Void> h, Pointer<Utf8> sid);
typedef _WipeC = Int32 Function(Pointer<Void> h);
typedef _WipeDart = int Function(Pointer<Void> h);
typedef _RetentionC = Int64 Function(Pointer<Void> h, Int32 days);
typedef _RetentionDart = int Function(Pointer<Void> h, int days);

// Vendor events
typedef _IngestVendorEventC =
    Int32 Function(Pointer<Void> h, Pointer<Utf8> json);
typedef _IngestVendorEventDart =
    int Function(Pointer<Void> h, Pointer<Utf8> json);
typedef _QueryVendorEventsC =
    Pointer<Utf8> Function(Pointer<Void> h, Pointer<Utf8> queryJson);
typedef _QueryVendorEventsDart =
    Pointer<Utf8> Function(Pointer<Void> h, Pointer<Utf8> queryJson);
typedef _GetLatestVendorEventC =
    Pointer<Utf8> Function(
      Pointer<Void> h,
      Pointer<Utf8> provider,
      Pointer<Utf8> eventType,
    );
typedef _GetLatestVendorEventDart =
    Pointer<Utf8> Function(
      Pointer<Void> h,
      Pointer<Utf8> provider,
      Pointer<Utf8> eventType,
    );
typedef _DeleteVendorEventsC =
    Int64 Function(Pointer<Void> h, Pointer<Utf8> provider);
typedef _DeleteVendorEventsDart =
    int Function(Pointer<Void> h, Pointer<Utf8> provider);

// Sync
typedef _SetSyncC = Void Function(Pointer<Void> h, Int32 enabled);
typedef _SetSyncDart = void Function(Pointer<Void> h, int enabled);
typedef _SyncNowC = Pointer<Utf8> Function(Pointer<Void> h);
typedef _SyncNowDart = Pointer<Utf8> Function(Pointer<Void> h);

// SRM
typedef _LoadSnapshotC = Int32 Function(Pointer<Void> h, Pointer<Utf8> json);
typedef _LoadSnapshotDart = int Function(Pointer<Void> h, Pointer<Utf8> json);

// Cloud
typedef _EnqueueC =
    Void Function(Pointer<Void> h, Pointer<Utf8> json, Int64 ts);
typedef _EnqueueDart =
    void Function(Pointer<Void> h, Pointer<Utf8> json, int ts);
typedef _IntReturnC = Int32 Function(Pointer<Void> h);
typedef _IntReturnDart = int Function(Pointer<Void> h);

// Account
typedef _AccountActionC = Int32 Function(Pointer<Void> h);
typedef _AccountActionDart = int Function(Pointer<Void> h);

// Lab
typedef _LabStartC =
    Pointer<Utf8> Function(
      Pointer<Void> h,
      Pointer<Utf8> protocolJson,
      Int64 startedAtMs,
    );
typedef _LabStartDart =
    Pointer<Utf8> Function(
      Pointer<Void> h,
      Pointer<Utf8> protocolJson,
      int startedAtMs,
    );
typedef _LabOpenWindowC =
    Pointer<Utf8> Function(
      Pointer<Void> h,
      Pointer<Utf8> parentId,
      Pointer<Utf8> windowType,
      Pointer<Utf8> label,
      Int64 startedAtMs,
    );
typedef _LabOpenWindowDart =
    Pointer<Utf8> Function(
      Pointer<Void> h,
      Pointer<Utf8> parentId,
      Pointer<Utf8> windowType,
      Pointer<Utf8> label,
      int startedAtMs,
    );
typedef _LabCloseWindowC =
    Int32 Function(Pointer<Void> h, Pointer<Utf8> windowId, Int64 endedAtMs);
typedef _LabCloseWindowDart =
    int Function(Pointer<Void> h, Pointer<Utf8> windowId, int endedAtMs);
typedef _LabSetWindowValuesC =
    Int32 Function(
      Pointer<Void> h,
      Pointer<Utf8> windowId,
      Pointer<Utf8> valuesJson,
    );
typedef _LabSetWindowValuesDart =
    int Function(
      Pointer<Void> h,
      Pointer<Utf8> windowId,
      Pointer<Utf8> valuesJson,
    );
typedef _LabMergeExtraDataC =
    Pointer<Utf8> Function(Pointer<Void> h, Pointer<Utf8> patchJson);
typedef _LabMergeExtraDataDart =
    Pointer<Utf8> Function(Pointer<Void> h, Pointer<Utf8> patchJson);
typedef _LabSetStateOverridesC =
    Int32 Function(
      Pointer<Void> h,
      Pointer<Utf8> windowId,
      Pointer<Utf8> overridesJson,
    );
typedef _LabSetStateOverridesDart =
    int Function(
      Pointer<Void> h,
      Pointer<Utf8> windowId,
      Pointer<Utf8> overridesJson,
    );
typedef _LabFinalizeC =
    Pointer<Utf8> Function(Pointer<Void> h, Int64 endedAtMs);
typedef _LabFinalizeDart =
    Pointer<Utf8> Function(Pointer<Void> h, int endedAtMs);
typedef _LabAvailableC = Int32 Function(Pointer<Void> h);
typedef _LabAvailableDart = int Function(Pointer<Void> h);

// Diagnostics
typedef _VersionC = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();
typedef _Int64ReturnC = Int64 Function(Pointer<Void> h);
typedef _Int64ReturnDart = int Function(Pointer<Void> h);
typedef _DoubleReturnC = Double Function(Pointer<Void> h);
typedef _DoubleReturnDart = double Function(Pointer<Void> h);

// ── Library loader ──────────────────────────────────────────────────────

/// Resolved FFI bindings for `synheart_core_runtime`.
class SynheartCoreFFI {
  SynheartCoreFFI._(this._lib) : sdkFfi = SynheartSdkFfi.tryBind(_lib);

  final DynamicLibrary _lib;

  /// Optional `synheart_core_sdk_*` device-auth symbols (null fields if absent).
  final SynheartSdkFfi sdkFfi;

  static SynheartCoreFFI? _instance;

  /// Load the native library. Returns null if not found.
  ///
  /// Desktop (macOS/Linux/Windows) lookup order:
  ///   1. `<cwd>/synheart/vendor/runtime/<platform>/<libname>` (installed by
  ///      `synheart install runtime` or `synheart runtime install --from`)
  ///   2. bare `<libname>` (system loader path — DYLD/LD_LIBRARY_PATH, PATH)
  ///
  /// iOS is statically linked (DynamicLibrary.process()). Android loads via
  /// jniLibs/ auto-discovery by the Android loader.
  static SynheartCoreFFI? load() {
    if (_instance != null) return _instance;

    DynamicLibrary? lib;
    try {
      if (Platform.isIOS) {
        lib = DynamicLibrary.process(); // statically linked
      } else if (Platform.isAndroid) {
        lib = DynamicLibrary.open('libsynheart_core_runtime.so');
      } else if (Platform.isMacOS) {
        lib = _openDesktop('macos', 'libsynheart_core_runtime.dylib');
      } else if (Platform.isLinux) {
        lib = _openDesktop('linux', 'libsynheart_core_runtime.so');
      } else if (Platform.isWindows) {
        lib = _openDesktop('windows', 'synheart_core_runtime.dll');
      }
    } catch (_) {
      return null;
    }

    if (lib == null) return null;
    _instance = SynheartCoreFFI._(lib);
    return _instance;
  }

  /// Try `synheart/vendor/runtime/<platform>/<libname>` relative to the
  /// current working directory, then fall back to the bare filename so the
  /// OS loader can resolve it from standard library search paths.
  static DynamicLibrary? _openDesktop(String platform, String libname) {
    final vendored = '${Directory.current.path}'
        '${Platform.pathSeparator}synheart'
        '${Platform.pathSeparator}vendor'
        '${Platform.pathSeparator}runtime'
        '${Platform.pathSeparator}$platform'
        '${Platform.pathSeparator}$libname';
    if (File(vendored).existsSync()) {
      try {
        return DynamicLibrary.open(vendored);
      } catch (_) {
        // fall through to bare lookup
      }
    }
    try {
      return DynamicLibrary.open(libname);
    } catch (_) {
      return null;
    }
  }

  // ── Resolved symbols ────────────────────────────────────────────────

  late final initLogging = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<Utf8>,
          Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>?,
          Pointer<Void>,
        ),
        int Function(
          Pointer<Utf8>,
          Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>?,
          Pointer<Void>,
        )
      >('synheart_core_init_logging');

  late final buildInfo = _lib
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'synheart_core_build_info',
      );

  late final coreNew = _lib.lookupFunction<_NewC, _NewDart>(
    'synheart_core_new',
  );
  late final coreFree = _lib.lookupFunction<_FreeC, _FreeDart>(
    'synheart_core_free',
  );
  late final coreFreeString = _lib
      .lookupFunction<_FreeStringC, _FreeStringDart>(
        'synheart_core_free_string',
      );

  late final startSession = _lib
      .lookupFunction<_StartSessionC, _StartSessionDart>(
        'synheart_core_start_session',
      );
  late final stopSession = _lib.lookupFunction<_StopSessionC, _StopSessionDart>(
    'synheart_core_stop_session',
  );
  late final currentSession = _lib
      .lookupFunction<_CurrentSessionC, _CurrentSessionDart>(
        'synheart_core_current_session',
      );
  late final isRunning = _lib.lookupFunction<_IsRunningC, _IsRunningDart>(
    'synheart_core_is_running',
  );

  late final pushRr = _lib.lookupFunction<_PushRrC, _PushRrDart>(
    'synheart_core_push_rr',
  );
  late final pushHr = _lib.lookupFunction<_PushHrC, _PushHrDart>(
    'synheart_core_push_hr',
  );
  late final ensurePipeline =
      _lib.lookupFunction<_EnsurePipelineC, _EnsurePipelineDart>(
        'synheart_core_ensure_pipeline',
      );
  late final tick = _lib.lookupFunction<_TickC, _TickDart>(
    'synheart_core_tick',
  );
  late final pushVendorHrv =
      _lib.lookupFunction<_PushVendorHrvC, _PushVendorHrvDart>(
        'synheart_core_push_vendor_hrv',
      );
  late final pushVendorVitals =
      _lib.lookupFunction<_PushVendorVitalsC, _PushVendorVitalsDart>(
        'synheart_core_push_vendor_vitals',
      );
  late final pushAccel = _lib.lookupFunction<_PushAccelC, _PushAccelDart>(
    'synheart_core_push_accel',
  );
  late final pushBehavior = _lib
      .lookupFunction<_PushBehaviorC, _PushBehaviorDart>(
        'synheart_core_push_behavior',
      );
  late final pushSleepStages = _lib.lookupFunction<_PushSleepC, _PushSleepDart>(
    'synheart_core_push_sleep_stages',
  );
  late final ingestBatch = _lib.lookupFunction<_IngestBatchC, _IngestBatchDart>(
    'synheart_core_ingest_batch',
  );

  late final grantConsent = _lib.lookupFunction<_ConsentStrC, _ConsentStrDart>(
    'synheart_core_grant_consent',
  );
  late final revokeConsent = _lib.lookupFunction<_ConsentStrC, _ConsentStrDart>(
    'synheart_core_revoke_consent',
  );
  late final hasConsent = _lib.lookupFunction<_HasConsentC, _HasConsentDart>(
    'synheart_core_has_consent',
  );
  late final currentConsent = _lib
      .lookupFunction<_CurrentConsentC, _CurrentConsentDart>(
        'synheart_core_current_consent',
      );
  late final consentConfigureCloud = _lib
      .lookupFunction<_ConsentConfigureCloudC, _ConsentConfigureCloudDart>(
        'synheart_core_consent_configure_cloud',
      );
  late final consentGetEditableForm = _lib
      .lookupFunction<_CurrentConsentC, _CurrentConsentDart>(
        'synheart_core_consent_get_editable_form',
      );
  late final consentSubmitForm = _lib
      .lookupFunction<_ConsentSubmitFormC, _ConsentSubmitFormDart>(
        'synheart_core_consent_submit_form',
      );
  late final consentClearStored = _lib
      .lookupFunction<_IntReturnC, _IntReturnDart>(
        'synheart_core_consent_clear_stored',
      );
  late final consentStatus = _lib
      .lookupFunction<_CurrentConsentC, _CurrentConsentDart>(
        'synheart_core_consent_status',
      );
  late final consentEffectiveState = _lib
      .lookupFunction<_CurrentConsentC, _CurrentConsentDart>(
        'synheart_core_consent_effective_state',
      );
  late final consentNeedsTokenRefresh = _lib
      .lookupFunction<_IntReturnC, _IntReturnDart>(
        'synheart_core_consent_needs_token_refresh',
      );

  late final loadCapabilityToken = _lib.lookupFunction<_LoadCapC, _LoadCapDart>(
    'synheart_core_load_capability_token',
  );

  late final listSessions = _lib.lookupFunction<_JsonReturnC, _JsonReturnDart>(
    'synheart_core_list_sessions',
  );
  late final getSessionSummary = _lib
      .lookupFunction<_SessionIdC, _SessionIdDart>(
        'synheart_core_get_session_summary',
      );
  late final getHsiWindows = _lib.lookupFunction<_HsiWindowsC, _HsiWindowsDart>(
    'synheart_core_get_hsi_windows',
  );
  late final getStorageUsage = _lib
      .lookupFunction<_JsonReturnC, _JsonReturnDart>(
        'synheart_core_get_storage_usage',
      );

  late final recordMetric = _lib
      .lookupFunction<_RecordMetricC, _RecordMetricDart>(
        'synheart_core_record_metric',
      );

  late final deleteSession = _lib
      .lookupFunction<_DeleteSessionC, _DeleteSessionDart>(
        'synheart_core_delete_session',
      );
  late final wipeLocalData = _lib.lookupFunction<_WipeC, _WipeDart>(
    'synheart_core_wipe_local_data',
  );
  late final setRetentionDays = _lib
      .lookupFunction<_RetentionC, _RetentionDart>(
        'synheart_core_set_retention_days',
      );

  late final ingestVendorEvent = _lib
      .lookupFunction<_IngestVendorEventC, _IngestVendorEventDart>(
        'synheart_core_ingest_vendor_event',
      );
  late final queryVendorEvents = _lib
      .lookupFunction<_QueryVendorEventsC, _QueryVendorEventsDart>(
        'synheart_core_query_vendor_events',
      );
  late final getLatestVendorEvent = _lib
      .lookupFunction<_GetLatestVendorEventC, _GetLatestVendorEventDart>(
        'synheart_core_get_latest_vendor_event',
      );
  late final deleteVendorEventsForProvider = _lib
      .lookupFunction<_DeleteVendorEventsC, _DeleteVendorEventsDart>(
        'synheart_core_delete_vendor_events_for_provider',
      );

  late final setSyncEnabled = _lib.lookupFunction<_SetSyncC, _SetSyncDart>(
    'synheart_core_set_sync_enabled',
  );
  late final syncNow = _lib.lookupFunction<_SyncNowC, _SyncNowDart>(
    'synheart_core_sync_now',
  );

  late final baselinesJson = _lib.lookupFunction<_JsonReturnC, _JsonReturnDart>(
    'synheart_core_baselines_json',
  );
  late final exportSrmSnapshot = _lib
      .lookupFunction<_JsonReturnC, _JsonReturnDart>(
        'synheart_core_export_srm_snapshot',
      );
  late final loadSrmSnapshot = _lib
      .lookupFunction<_LoadSnapshotC, _LoadSnapshotDart>(
        'synheart_core_load_srm_snapshot',
      );
  late final srmOverallStatus = _lib
      .lookupFunction<_JsonReturnC, _JsonReturnDart>(
        'synheart_core_srm_overall_status',
      );

  late final enqueueHsi = _lib.lookupFunction<_EnqueueC, _EnqueueDart>(
    'synheart_core_enqueue_hsi',
  );
  late final uploadQueueLength = _lib
      .lookupFunction<_IntReturnC, _IntReturnDart>(
        'synheart_core_upload_queue_length',
      );
  late final flushUploads = _lib.lookupFunction<_JsonReturnC, _JsonReturnDart>(
    'synheart_core_flush_uploads',
  );

  // hsi_history: on-device mirror of successfully uploaded HSI payloads.
  // Populated automatically by the ingest connector on HTTP 200; pruned
  // by age (default 30 days). See connector.rs::HSI_HISTORY_RETENTION_MS.
  late final hsiHistoryList = _lib
      .lookupFunction<_HsiHistoryListC, _HsiHistoryListDart>(
        'synheart_core_hsi_history_list',
      );
  late final hsiHistoryCount = _lib
      .lookupFunction<_Int64ReturnC, _Int64ReturnDart>(
        'synheart_core_hsi_history_count',
      );
  late final hsiHistoryClear = _lib
      .lookupFunction<_IntReturnC, _IntReturnDart>(
        'synheart_core_hsi_history_clear',
      );
  late final uploadMetadata = _lib
      .lookupFunction<_JsonReturnC, _JsonReturnDart>(
        'synheart_core_upload_metadata',
      );

  late final wellnessJson = _lib.lookupFunction<_JsonReturnC, _JsonReturnDart>(
    'synheart_core_wellness_json',
  );

  late final lastFeatures = _lib.lookupFunction<_JsonReturnC, _JsonReturnDart>(
    'synheart_core_last_features',
  );
  late final diagnostics = _lib.lookupFunction<_JsonReturnC, _JsonReturnDart>(
    'synheart_core_diagnostics',
  );
  late final lastErrorCode = _lib.lookupFunction<_IntReturnC, _IntReturnDart>(
    'synheart_core_last_error_code',
  );
  late final isRuntimeAvailable = _lib
      .lookupFunction<_IntReturnC, _IntReturnDart>(
        'synheart_core_is_runtime_available',
      );
  late final isNetworkReachable = _lib
      .lookupFunction<_IntReturnC, _IntReturnDart>(
        'synheart_core_is_network_reachable',
      );

  late final requestAccountDeletion = _lib
      .lookupFunction<_AccountActionC, _AccountActionDart>(
        'synheart_core_request_account_deletion',
      );
  late final cancelAccountDeletion = _lib
      .lookupFunction<_AccountActionC, _AccountActionDart>(
        'synheart_core_cancel_account_deletion',
      );

  // HSI callback
  late final setHsiCallback = _lib
      .lookupFunction<
        Void Function(
          Pointer<Void>,
          Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>,
          Pointer<Void>,
        ),
        void Function(
          Pointer<Void>,
          Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>,
          Pointer<Void>,
        )
      >('synheart_core_set_hsi_callback');

  late final clearHsiCallback = _lib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('synheart_core_clear_hsi_callback');

  // Stream (RAMEN vendor sync)
  late final streamStart = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('synheart_core_stream_start');

  late final streamStop = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('synheart_core_stream_stop');

  late final setStreamCallback = _lib
      .lookupFunction<
        Void Function(
          Pointer<Void>,
          Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>,
          Pointer<Void>,
        ),
        void Function(
          Pointer<Void>,
          Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>,
          Pointer<Void>,
        )
      >('synheart_core_set_stream_callback');

  late final streamState = _lib
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)
      >('synheart_core_stream_state');

  // Lab
  late final labStart = _lib.lookupFunction<_LabStartC, _LabStartDart>(
    'synheart_core_lab_start',
  );
  late final labOpenWindow = _lib
      .lookupFunction<_LabOpenWindowC, _LabOpenWindowDart>(
        'synheart_core_lab_open_window',
      );
  late final labCloseWindow = _lib
      .lookupFunction<_LabCloseWindowC, _LabCloseWindowDart>(
        'synheart_core_lab_close_window',
      );
  late final labSetWindowValues = _lib
      .lookupFunction<_LabSetWindowValuesC, _LabSetWindowValuesDart>(
        'synheart_core_lab_set_window_values',
      );
  late final labMergeExtraData = _lib
      .lookupFunction<_LabMergeExtraDataC, _LabMergeExtraDataDart>(
        'synheart_core_lab_merge_extra_data',
      );
  late final labSetStateOverrides = _lib
      .lookupFunction<_LabSetStateOverridesC, _LabSetStateOverridesDart>(
        'synheart_core_lab_set_state_overrides',
      );
  late final labFinalize = _lib.lookupFunction<_LabFinalizeC, _LabFinalizeDart>(
    'synheart_core_lab_finalize',
  );
  late final labAvailable = _lib
      .lookupFunction<_LabAvailableC, _LabAvailableDart>(
        'synheart_core_is_lab_available',
      );
  late final labExportJson = _lib.lookupFunction<_JsonReturnC, _JsonReturnDart>(
    'synheart_core_lab_export_json',
  );

  // Version / frame diagnostics
  late final Pointer<Utf8> Function()? version = () {
    try {
      return _lib.lookupFunction<_VersionC, _VersionDart>(
        'synheart_core_version',
      );
    } catch (_) {
      return null;
    }
  }();
  late final frameCount = _lib.lookupFunction<_Int64ReturnC, _Int64ReturnDart>(
    'synheart_core_frame_count',
  );
  late final double Function(Pointer<Void>)? lastQuality = () {
    try {
      return _lib.lookupFunction<_DoubleReturnC, _DoubleReturnDart>(
        'synheart_core_last_quality',
      );
    } catch (_) {
      return null;
    }
  }();
}
