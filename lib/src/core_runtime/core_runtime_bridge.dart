/// Safe Dart wrapper over `synheart_core_runtime` C ABI.
///
/// Replaces the internal storage, crypto, sync, consent, artifact pipeline,
/// and cloud connector logic.
/// Platform-specific code (Keychain, HealthKit, sensors) stays in Flutter plugins.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'package:flutter/foundation.dart';

import '../core/logger.dart';

import '../models/sleep_score.dart';
import 'ffi_bindings.dart';
import 'platform_native_sdk_storage_callbacks.dart';
import 'sdk_ffi.dart';

/// Forwarder installed before `synheart_core_init_logging` (top-level for FFI).
void Function(String line)? synheartRuntimeLogForwarder;

/// Set by [CoreRuntimeBridge.initRuntimeLogging] so the top-level trampoline
/// can release CStrings that the native layer leaks across the async hop.
void Function(Pointer<Utf8> ptr)? _synheartRuntimeLogFree;

/// Decode an FFI-owned C string and free it via [freeFn]. Tolerates malformed
/// UTF-8 so a bad byte never kills the listener isolate. Returns null only if
/// `ptr` is null.
String? _readFfiStringAndFree(
  Pointer<Utf8> ptr,
  void Function(Pointer<Utf8>) freeFn,
) {
  if (ptr == nullptr) return null;
  try {
    return ptr.toDartString();
  } on FormatException {
    final raw = ptr.cast<Uint8>();
    var len = 0;
    while (raw[len] != 0) {
      len++;
    }
    return utf8.decode(raw.asTypedList(len), allowMalformed: true);
  } finally {
    freeFn(ptr);
  }
}

void _synheartRuntimeLogTrampoline(Pointer<Utf8> line, Pointer<Void> userData) {
  final free = _synheartRuntimeLogFree;
  if (free == null) return;
  final text = _readFfiStringAndFree(line, free);
  if (text == null) return;
  final custom = synheartRuntimeLogForwarder;
  if (custom != null) {
    custom(text);
    return;
  }
  if (kDebugMode) {
    debugPrint('[synheart] $text');
  }
}

/// Bridge to the core runtime via FFI.
///
/// Usage:
/// ```dart
/// final bridge = CoreRuntimeBridge.create({
/// 'app_id': 'com.example',
/// 'subject_id': 'sub_abc123',
/// 'mode': 'personal',
/// });
/// final session = bridge?.startSession();
/// bridge?.pushHr(DateTime.now().millisecondsSinceEpoch, 72.0);
/// bridge?.stopSession();
/// bridge?.dispose();
/// ```
class CoreRuntimeBridge {
  CoreRuntimeBridge._(
    this._ffi,
    this._handle, {
    required this.deviceAuthTemporarilyDisabledForSubjectCompat,
  });

  final SynheartCoreFFI _ffi;
  final Pointer<Void> _handle;
  final bool deviceAuthTemporarilyDisabledForSubjectCompat;
  bool _disposed = false;
  Pointer<SynheartSdkCryptoCallbacks>? _sdkCryptoTable;

  /// Default `env_filter` when [initRuntimeLogging] is called with a null/empty filter.
  // static String defaultRuntimeLogEnvFilter = 'info,synheart_core_runtime=debug';
  static String defaultRuntimeLogEnvFilter = 'info';

  static bool _loggingInstalled = false;
  static NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>?
  _logCallable;
  static SynheartCoreFFI? _logFfi;

  /// Initialize Runtime `tracing` once per process (call before [create] if you need
  /// a custom filter or sink). Matches [SDK_LOGGING_INIT.md] / SDK auth sequence §1b.
  ///
  /// Returns `0` on success, `1` if already initialized, negative on failure.
  static int initRuntimeLogging({
    SynheartCoreFFI? ffi,
    String? envFilter,
    void Function(String line)? onLine,
  }) {
    if (_loggingInstalled) return 1;

    final lib = ffi ?? SynheartCoreFFI.load();
    if (lib == null) return -2;
    final chosen = envFilter ?? defaultRuntimeLogEnvFilter;
    Pointer<Utf8> filterArg;
    if (chosen.isEmpty) {
      filterArg = nullptr;
    } else {
      filterArg = chosen.toNativeUtf8();
    }
    try {
      synheartRuntimeLogForwarder = onLine;
      _synheartRuntimeLogFree = lib.coreFreeString;
      _logCallable ??=
          NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>.listener(
            _synheartRuntimeLogTrampoline,
          );
      _logFfi = lib;
      final rc = lib.initLogging(
        filterArg,
        _logCallable!.nativeFunction,
        nullptr,
      );
      if (rc == 0 || rc == 1) {
        _loggingInstalled = true;
      }
      return rc;
    } catch (_) {
      return -3;
    } finally {
      if (filterArg != nullptr) {
        malloc.free(filterArg);
      }
    }
  }

  /// Tear down the host log callback registered by [initRuntimeLogging].
  ///
  /// Hosts MUST call this before the Flutter engine / Dart isolate that
  /// registered the [NativeCallable] is about to be destroyed (app
  /// termination, hot restart, isolate disposal). After this returns the
  /// The runtime guarantees no further invocations of the registered
  /// callback.
  ///
  /// Wire-up for Flutter apps:
  /// ```dart
  /// class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// @override
  /// void didChangeAppLifecycleState(AppLifecycleState state) {
  /// if (state == AppLifecycleState.detached) {
  /// CoreRuntimeBridge.shutdownRuntimeLogging();
  /// }
  /// }
  /// }
  /// ```
  ///
  /// Idempotent: safe to call when logging was never initialised, or
  /// twice in a row. Returns the runtime's shutdown status code:
  /// `0` = OK, `1` = was-not-initialised, `<0` = worker join failed.
  static int shutdownRuntimeLogging() {
    final ffi = _logFfi;
    var rc = 1;
    if (ffi != null) {
      try {
        rc = ffi.shutdownLogging();
      } catch (_) {
        rc = -3;
      }
    }

    // Close the Dart-side callable AFTER the runtime has stopped
    // forwarding events. The runtime's shutdown_logging joins the
    // worker thread, so by this point no thread can be in the middle
    // of calling _logCallable.nativeFunction.
    final callable = _logCallable;
    if (callable != null) {
      try {
        callable.close();
      } catch (_) {
        /* ignore */
      }
      _logCallable = null;
    }
    synheartRuntimeLogForwarder = null;
    _synheartRuntimeLogFree = null;
    _loggingInstalled = false;
    _logFfi = null;
    return rc;
  }

  /// Create a bridge from a config map. Returns null if the native
  /// library is unavailable or config is invalid.
  static CoreRuntimeBridge? create(Map<String, dynamic> config) {
    final ffi = SynheartCoreFFI.load();
    if (ffi == null) return null;

    final runtimeConfig = Map<String, dynamic>.from(config);
    final rawSubjectId = runtimeConfig['subject_id'];
    // Compatibility shim for non-canonical subject IDs.
    if (rawSubjectId is String &&
        rawSubjectId.isNotEmpty &&
        !rawSubjectId.startsWith('sub_')) {
      runtimeConfig['subject_id'] = 'sub_$rawSubjectId';
    }

    // Optional compatibility guard (off by default) for runtimes where
    // device-auth subject derivation is not yet aligned with engine validation.
    final forceDisableDeviceAuth =
        runtimeConfig['_compat_force_disable_device_auth'] == true;
    runtimeConfig.remove('_compat_force_disable_device_auth');

    final deviceAuth = runtimeConfig['device_auth'];
    var deviceAuthForcedOff = false;
    if (forceDisableDeviceAuth && deviceAuth is Map) {
      runtimeConfig['device_auth'] = <String, dynamic>{
        ...deviceAuth.map((k, v) => MapEntry(k.toString(), v)),
        'enabled': false,
      };
      runtimeConfig.remove('client_id');
      deviceAuthForcedOff = true;
    }

    final cJson = jsonEncode(runtimeConfig).toNativeUtf8();
    try {
      final handle = ffi.coreNew(cJson.cast());
      if (handle == nullptr) {
        // Pull Rust's last-error message (set by synheart_core_new on every
        // nullptr return). Falls back to a keys/empty dump for older
        // runtime builds that don't export the symbol.
        String? reason;
        final lastErr = ffi.coreLastError;
        if (lastErr != null) {
          final p = lastErr();
          if (p != nullptr) {
            reason = p.toDartString();
            ffi.coreFreeString(p);
          }
        }
        if (reason != null) {
          SynheartLogger.log(
            '[Synheart FFI] coreNew failed: $reason',
            name: 'synheart.ffi',
          );
        } else {
          // Older runtime build without the last-error symbol — fall back
          // to listing which Dart-side fields look empty so the operator
          // still has something to grep on. Avoids logging values
          // (some are sensitive).
          final emptyFields = <String>[];
          runtimeConfig.forEach((k, v) {
            if (v == null) {
              emptyFields.add('$k=null');
            } else if (v is String && v.isEmpty) {
              emptyFields.add('$k=""');
            }
          });
          SynheartLogger.log(
            '[Synheart FFI] coreNew returned nullptr (no last-error symbol). '
            'keys=${runtimeConfig.keys.toList()} empty=$emptyFields',
            name: 'synheart.ffi',
          );
        }
        return null;
      }
      // §1b: logging after core creation — avoids crash from async
      // NativeCallable.listener trampoline during synchronous coreNew.
      initRuntimeLogging(ffi: ffi);
      return CoreRuntimeBridge._(
        ffi,
        handle,
        deviceAuthTemporarilyDisabledForSubjectCompat: deviceAuthForcedOff,
      );
    } finally {
      malloc.free(cJson);
    }
  }

  /// Whether the native library was loaded and the handle is valid.
  bool get isAvailable => !_disposed;

  /// True when this native build exports the full `synheart_core_sdk_*` device-auth ABI.
  bool get sdkDeviceAuthAvailable => !_disposed && _ffi.sdkFfi.isAvailable;

  /// Register host crypto callbacks (§2). Must be called before [sdkRegisterDevice] / proof APIs.
  ///
  /// [table] must point at a caller-owned [SynheartSdkCryptoCallbacks] populated with
  /// process-resolved native function pointers — the bridge takes ownership and frees
  /// it on [dispose] or on the next successful call.
  ///
  /// Returns `0` on success. On failure, frees the provided table.
  int setSdkCryptoCallbacks(Pointer<SynheartSdkCryptoCallbacks> table) {
    if (_disposed) return -1;
    if (!_ffi.sdkFfi.isAvailable) return -2;
    if (_sdkCryptoTable != null) {
      calloc.free(_sdkCryptoTable!);
      _sdkCryptoTable = null;
    }
    final rc = _ffi.sdkFfi.setCryptoCallbacksInvoke(_handle, table);
    if (rc != 0) {
      calloc.free(table);
      return rc;
    }
    _sdkCryptoTable = table;
    return 0;
  }

  /// Attach host-provided secure-storage callbacks so the native core can
  /// persist state (consent tokens, device records, …) across app restarts.
  ///
  /// Resolves `synheart_native_secure_store` / `…_load` / `…_delete` from the
  /// process (iOS) or from `libsynheart_native_crypto.so` (Android) and hands
  /// the function pointers to `synheart_core_set_storage_callbacks`.
  ///
  /// Returns:
  /// - `0` on success,
  /// - `-1` if the runtime is disposed,
  /// - `-2` if `synheart_core_set_storage_callbacks` isn't exported by this
  /// core build,
  /// - `-3` if the native symbols are missing (no storage backend available),
  /// - any other non-zero value the core's FFI returned.
  int setStorageCallbacks() {
    if (_disposed) return -1;
    final setter = _ffi.sdkFfi.setStorageCallbacks;
    if (setter == null) return -2;
    final triple = PlatformNativeSdkStorageCallbacks.tryResolveTriple();
    if (triple == null) return -3;
    return setter(_handle, triple.store, triple.load, triple.delete);
  }

  /// §3 — device registration (attestation). [clientId] is the app user id for this session.
  /// Runs on a background isolate so the blocking FFI call doesn't ANR the UI thread.
  Future<Map<String, dynamic>?> sdkRegisterDevice(String clientId) async {
    if (_disposed || _ffi.sdkFfi.registerDevice == null) return null;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null || ffi.sdkFfi.registerDevice == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final p = clientId.toNativeUtf8();
      try {
        final resPtr = ffi.sdkFfi.registerDevice!(handle, p.cast());
        if (resPtr == nullptr) return null;
        final str = resPtr.toDartString();
        ffi.coreFreeString(resPtr);
        return jsonDecode(str) as Map<String, dynamic>;
      } catch (_) {
        return null;
      } finally {
        malloc.free(p);
      }
    });
  }

  /// §3 / §5 — JSON snapshot from `synheart_core_sdk_device_auth_status`.
  Map<String, dynamic>? sdkDeviceAuthStatus() {
    if (_disposed || _ffi.sdkFfi.deviceAuthStatus == null) return null;
    final out = _readAndFree(_ffi.sdkFfi.deviceAuthStatus!(_handle));
    if (out == null) return null;
    try {
      return jsonDecode(out) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// §4 — compact JWS value for `X-Synheart-Proof` (non-ingest APIs). Use uppercase [method].
  String? buildProofHeader(String method, String absoluteUrl) {
    if (_disposed || _ffi.sdkFfi.buildProofHeader == null) return null;
    final m = method.toNativeUtf8();
    final u = absoluteUrl.toNativeUtf8();
    try {
      return _readAndFree(
        _ffi.sdkFfi.buildProofHeader!(_handle, m.cast(), u.cast()),
      );
    } finally {
      malloc.free(m);
      malloc.free(u);
    }
  }

  /// Release the native handle. Must be called when done.
  void dispose() {
    if (!_disposed) {
      clearStreamCallback();
      clearHsiCallback();
      _ffi.coreFree(_handle);
      if (_sdkCryptoTable != null) {
        calloc.free(_sdkCryptoTable!);
        _sdkCryptoTable = null;
      }
      _disposed = true;
    }
  }

  // ── Session lifecycle ────────────────────────────────────────────────

  /// Start a session. Returns session JSON or null on error.
  Map<String, dynamic>? startSession() {
    return _callJson(() => _ffi.startSession(_handle));
  }

  /// Stop the current session.
  bool stopSession() => _ffi.stopSession(_handle) == 0;

  /// Get the current session as a map, or null.
  Map<String, dynamic>? currentSession() {
    return _callJson(() => _ffi.currentSession(_handle));
  }

  /// Whether a session is running.
  bool get isRunning => _ffi.isRunning(_handle) != 0;

  /// Create the engine pipeline without starting a background tick task.
  /// Used by the ingest buffer which handles ticking via ingestBatch.
  void ensurePipeline() => _ffi.ensurePipeline(_handle);

  // ── Sensor push ──────────────────────────────────────────────────────

  /// Push an RR interval with provider attribution.
  ///
  /// `provider` is forwarded to the engine for Tier-1 routing (only
  /// `'ble_hrm'` qualifies for the breathing detector's Tier-1 series
  /// today). The C-string is allocated and freed inside this call —
  /// the FFI layer copies it on the runtime side, no need to retain.
  void pushRr(int tsMs, double rrMs, {String provider = 'default_sensor'}) {
    final cstr = provider.toNativeUtf8();
    try {
      _ffi.pushRr(_handle, tsMs, rrMs, cstr);
    } finally {
      malloc.free(cstr);
    }
  }

  void pushHr(int tsMs, double bpm) => _ffi.pushHr(_handle, tsMs, bpm);

  // ── Breathing compliance ────────────────────────────────────────────
  // Tier-1 RR pushed via [pushRr] is auto-forwarded to the breathing
  // detector. These setters configure target/window/profile; [breathing
  // EvaluateJson] reads back the current verdict as JSON.

  void breathingSetTargetBpm(double bpm) =>
      _ffi.breathingSetTargetBpm(_handle, bpm);
  void breathingSetWindowSecs(int secs) =>
      _ffi.breathingSetWindowSecs(_handle, secs);
  void breathingSetPopulation(int profile) =>
      _ffi.breathingSetPopulation(_handle, profile);
  Map<String, dynamic>? breathingEvaluateJson() =>
      _callJson(() => _ffi.breathingEvaluate(_handle));
  void breathingReset() => _ffi.breathingReset(_handle);

  /// Advance the pipeline clock. Returns HSI JSON if a window completed.
  String? tick(int nowMs) => _readAndFree(_ffi.tick(_handle, nowMs));

  /// Push vendor-reported HRV metrics (Tier 2).
  /// Pass -1.0 for unavailable fields.
  void pushVendorHrv(
    int tsMs, {
    double rmssd = -1.0,
    double sdnn = -1.0,
    double stress = -1.0,
    double recovery = -1.0,
  }) => _ffi.pushVendorHrv(_handle, tsMs, rmssd, sdnn, stress, recovery);

  /// Push vendor vitals (SpO2, respiration) to lab windows.
  void pushVendorVitals(
    int tsMs, {
    double spo2 = -1.0,
    double respiration = -1.0,
  }) => _ffi.pushVendorVitals(_handle, tsMs, spo2, respiration);

  void pushAccel(int tsMs, double x, double y, double z) =>
      _ffi.pushAccel(_handle, tsMs, x, y, z);
  void pushBehavior(int tsMs, int eventType, double value) =>
      _ffi.pushBehavior(_handle, tsMs, eventType, value);

  // ── Personalization task / workout APIs ─────────────────────────────
  // Discriminants match the engine FFI contract — see
  // synheart-engine personalization API.

  /// Set the active task type. `0=Unknown, 1=Focus, 2=Recovery,
  /// 3=Movement, 4=Conversation`. Prefer the typed [TaskType] enum on
  /// `SynheartCore` over calling this with raw integers.
  void setTaskType(int taskKind) => _ffi.setTaskType(_handle, taskKind);

  /// Push a workout/exercise event with optional vendor scalars.
  /// Workout-kind discriminants: `0=Unknown, 1=Cardio, 2=Strength,
  /// 3=Hiit, 4=LowIntensity, 5=Sport`. Pass `-1.0` for missing vendor
  /// scalars.
  void pushWorkoutEvent(
    int startMs,
    int endMs, {
    int workoutKind = 0,
    double vendorStrain = -1.0,
    double vendorRecovery = -1.0,
  }) => _ffi.pushWorkoutEvent(
    _handle,
    startMs,
    endMs,
    workoutKind,
    vendorStrain,
    vendorRecovery,
  );

  /// Currently active task type discriminant.
  int currentTaskType() => _ffi.currentTaskType(_handle);

  /// Currently active workout kind discriminant.
  int currentWorkoutKind() => _ffi.currentWorkoutKind(_handle);

  /// Set the active focus-kind sub-classification. No effect outside
  /// an active `Focus` task. See [FocusKind] for discriminants.
  void setFocusKind(int focusKind) => _ffi.setFocusKind(_handle, focusKind);

  /// Currently active focus kind discriminant.
  int currentFocusKind() => _ffi.currentFocusKind(_handle);

  /// Last `PersonalizationContext` as JSON. Returns `null` before the
  /// first window has completed. Schema mirrors the Synheart Runtime's
  /// `PersonalizationContext` JSON-serialized form.
  String? personalizationContextJson() =>
      _readAndFree(_ffi.personalizationContextJson(_handle));

  /// Push a longitudinal SRM daily value. Allowed dimensions:
  /// `sleep_need`, `sleep_regularity`, `hrv_rmssd`, `resting_hr`,
  /// `recovery_score`, `deep_sleep_min`, `rem_sleep_min`. Day-index =
  /// epoch-day (`epoch_ms / 86_400_000`). Fidelity: `0`=raw, `1`=summary.
  void srmPushWearableDaily({
    required String dimension,
    required int dayIndex,
    required double value,
    double confidence = 0.85,
    int fidelity = 1,
  }) {
    _withCString(
      dimension,
      (p) => _ffi.srmPushWearableDaily(
        _handle,
        p,
        dayIndex,
        value,
        confidence,
        fidelity,
      ),
    );
  }

  /// Trigger a longitudinal SRM recompute. Call after a batch of
  /// [srmPushWearableDaily] so the next inference window picks up
  /// fresh personal baselines. `triggerType`: `0=Window, 1=AffectedWindow,
  /// 2=Full`.
  void srmTriggerWearableRecompute({
    int triggerType = 0,
    required int asOfDay,
  }) => _ffi.srmTriggerWearableRecompute(_handle, triggerType, asOfDay);

  void pushSleepStages(String json) {
    _withCString(json, (p) => _ffi.pushSleepStages(_handle, p));
  }

  /// Batch ingest. Returns HSI JSON if a window completed.
  String? ingestBatch(String batchJson, int nowMs) {
    return _withCString(batchJson, (p) {
      return _readAndFree(_ffi.ingestBatch(_handle, p, nowMs));
    });
  }

  // ── Batch nightly sleep score ──────────────────────────────────────
  //
  // All methods here marshal UTF-8 and free the returned native strings.
  // See the Synheart Runtime sleep-score integration spec for
  // input/output JSON shapes.

  /// Compute a nightly sleep score (stateless).
  ///
  /// [inputJson] must match `synheart_sleep_score::SleepScoreInput`.
  /// Returns the serialized `SleepScoreResult` or `null` on parse error.
  String? sleepScoreComputeJson(String inputJson) {
    return _withCString(inputJson, (p) {
      return _readAndFree(_ffi.sleepScoreComputeJson(_handle, p));
    });
  }

  /// Same as [sleepScoreComputeJson] but with a caller-supplied
  /// correlation ID attached to tracing events.
  String? sleepScoreComputeJsonTraced(String inputJson, String correlationId) {
    return _withCString(inputJson, (p) {
      return _withCString(correlationId, (cid) {
        return _readAndFree(_ffi.sleepScoreComputeJsonTraced(_handle, p, cid));
      });
    });
  }

  /// Compute a daily Recovery Score (stateless).
  ///
  /// [inputJson] must match `synheart_recovery_score::RecoveryScoreInput`.
  /// Returns the serialized `RecoveryScoreResult` JSON, the literal
  /// string `"null"` when the input had no overnight HR/HRV (sleep-only
  /// recovery is forbidden by design), or `null` on parse failure.
  String? recoveryScoreComputeJson(String inputJson) {
    return _withCString(inputJson, (p) {
      return _readAndFree(_ffi.recoveryScoreComputeJson(_handle, p));
    });
  }

  /// Same as [recoveryScoreComputeJson] but with a caller-supplied
  /// correlation ID attached to tracing events.
  String? recoveryScoreComputeJsonTraced(
    String inputJson,
    String correlationId,
  ) {
    return _withCString(inputJson, (p) {
      return _withCString(correlationId, (cid) {
        return _readAndFree(
          _ffi.recoveryScoreComputeJsonTraced(_handle, p, cid),
        );
      });
    });
  }

  /// Compute a daily Readiness Score.
  ///
  /// [inputJson] must match `synheart_readiness_score::ReadinessScoreInput`.
  /// Returns the serialized `ReadinessScoreResult` JSON, or `null` on
  /// parse failure / runtime not ready.
  String? readinessScoreComputeJson(String inputJson) {
    return _withCString(inputJson, (p) {
      return _readAndFree(_ffi.readinessScoreComputeJson(_handle, p));
    });
  }

  /// Same as [readinessScoreComputeJson] but with a caller-supplied
  /// correlation ID attached to tracing events.
  String? readinessScoreComputeJsonTraced(
    String inputJson,
    String correlationId,
  ) {
    return _withCString(inputJson, (p) {
      return _withCString(correlationId, (cid) {
        return _readAndFree(
          _ffi.readinessScoreComputeJsonTraced(_handle, p, cid),
        );
      });
    });
  }

  /// Queue a batch `SleepScoreResult` JSON to ride the next HSI and
  /// feed the Path-B rolling median. Returns `0` on success.
  int attachSleepScoreJson(String resultJson) {
    return _withCString(
          resultJson,
          (p) => _ffi.attachSleepScoreJson(_handle, p),
        ) ??
        -1;
  }

  /// Attach today's daily Recovery Score (`0.=100`).
  /// Sticky across windows until cleared or
  /// replaced. Returns `0` on success.
  int attachRecoveryScoreToday(int score) {
    final clamped = score < 0 ? 0 : (score > 255 ? 255 : score);
    return _ffi.attachRecoveryScoreToday(_handle, clamped);
  }

  /// Drop today's Recovery Score so personalization Stage 2 reverts to
  /// the per-component composite. Returns `0` on success.
  int clearRecoveryScoreToday() {
    return _ffi.clearRecoveryScoreToday(_handle);
  }

  /// Get the last **live-head** `SleepScore` JSON
  /// (`rulepack://sleep_autonomic_v1`). Null if no window has completed.
  String? lastSleepScoreJson() =>
      _readAndFree(_ffi.lastSleepScoreJson(_handle));

  /// Export the longitudinal SRM snapshot for cross-launch persistence.
  String? exportLongitudinalSnapshot() =>
      _readAndFree(_ffi.exportLongitudinalSnapshot(_handle));

  /// Restore the longitudinal SRM from a prior snapshot.
  /// Returns the engine error code (0 on success).
  int loadLongitudinalSnapshot(String json) {
    return _withCString(
          json,
          (p) => _ffi.loadLongitudinalSnapshot(_handle, p),
        ) ??
        -1;
  }

  /// Get the current wearable reference, including Path-B
  /// `recent_sleep_score_median`. Null if no reference is set.
  String? wearableReferenceJson() =>
      _readAndFree(_ffi.wearableReferenceJson(_handle));

  // ── Typed sleep-score bridge API ───────────────────────────────────

  /// Typed form of [sleepScoreComputeJson]. Returns `null` if the engine
  /// rejected the input or the JSON couldn't be parsed.
  SleepScoreResult? computeSleepScore(SleepScoreInput input) {
    final json = sleepScoreComputeJson(input.toJsonString());
    if (json == null) return null;
    try {
      return SleepScoreResult.fromJsonString(json);
    } catch (_) {
      return null;
    }
  }

  /// Typed form of [sleepScoreComputeJsonTraced].
  SleepScoreResult? computeSleepScoreTraced(
    SleepScoreInput input,
    String correlationId,
  ) {
    final json = sleepScoreComputeJsonTraced(
      input.toJsonString(),
      correlationId,
    );
    if (json == null) return null;
    try {
      return SleepScoreResult.fromJsonString(json);
    } catch (_) {
      return null;
    }
  }

  /// Typed form of [attachSleepScoreJson] — serializes the result
  /// internally. Returns 0 on success.
  int attachSleepScore(SleepScoreResult result) {
    // Round-trip via JSON so we use the same wire format the runtime side
    // expects. SleepScoreResult fields are symmetric with serde.
    final json = jsonEncode({
      'score': result.score,
      'score_normalized': result.scoreNormalized,
      'confidence': result.confidence,
      'path': result.path.wire,
      'mode': result.mode.wire,
      'components': {
        'duration': result.components.duration,
        'quality': result.components.quality,
        'continuity': result.components.continuity,
        'consistency': result.components.consistency,
        'personalization': result.components.personalization,
        'vendor_score': result.components.vendorScore,
        'proxy_hr': result.components.proxyHr,
      },
      'adjustments': {
        'debt_penalty': result.adjustments.debtPenalty,
        'hr_adjustment': result.adjustments.hrAdjustment,
      },
      'effective_weights': {
        'duration': result.effectiveWeights.duration,
        'quality': result.effectiveWeights.quality,
        'continuity': result.effectiveWeights.continuity,
        'consistency': result.effectiveWeights.consistency,
        'personalization': result.effectiveWeights.personalization,
      },
      'reason': result.reason?.wire,
      'prior_night_count': result.priorNightCount,
      'pipeline_version': result.pipelineVersion,
      'model_id': result.modelId,
      'constants_hash': result.constantsHash,
    });
    return attachSleepScoreJson(json);
  }

  /// Typed form of [lastSleepScoreJson] — returns the live-head
  /// SleepScore as raw JSON (path/mode/components/tier/baseline).
  /// The live-head and batch shapes differ; use [computeSleepScore]
  /// for the batch form.
  String? lastSleepScoreRawJson() => lastSleepScoreJson();

  /// Typed form of [wearableReferenceJson] — returns just the Path-B
  /// fields callers usually need (`status`, `recent_sleep_score_median`).
  /// For the full reference, parse the raw JSON yourself.
  WearableReferenceView? wearableReference() {
    final json = wearableReferenceJson();
    if (json == null) return null;
    try {
      return WearableReferenceView.fromJsonString(json);
    } catch (_) {
      return null;
    }
  }

  // ── Consent ──────────────────────────────────────────────────────────

  Future<bool> grantConsent(String type) => _consentMutate(type, grant: true);

  Future<bool> revokeConsent(String type) => _consentMutate(type, grant: false);

  /// Grant or revoke a single consent type. The FFI persists the change and
  /// re-issues/syncs the consent token, which blocks on network I/O — calling
  /// it on the UI isolate froze the main thread and ANR'd (observed stack:
  /// main tid=1 Native … synheart_core_revoke_consent). Run it on a background
  /// isolate, mirroring [sdkRegisterDevice] / [consentSubmitForm]. Callers that
  /// mutate several channels must await these SEQUENTIALLY (not concurrently)
  /// so two mutations never race on the shared native handle.
  Future<bool> _consentMutate(String type, {required bool grant}) async {
    if (_disposed) return false;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return false;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final p = type.toNativeUtf8();
      try {
        final rc = grant
            ? ffi.grantConsent(handle, p.cast())
            : ffi.revokeConsent(handle, p.cast());
        return rc == 0;
      } catch (_) {
        return false;
      } finally {
        malloc.free(p);
      }
    });
  }

  bool hasConsent(String type) {
    return _withCString(type, (p) => _ffi.hasConsent(_handle, p) != 0);
  }

  Map<String, dynamic>? currentConsent() {
    return _callJson(() => _ffi.currentConsent(_handle));
  }

  bool consentConfigureCloud(String baseUrl, String appId) {
    final pBase = baseUrl.toNativeUtf8();
    final pApp = appId.toNativeUtf8();
    try {
      return _ffi.consentConfigureCloud(_handle, pBase.cast(), pApp.cast()) ==
          0;
    } finally {
      malloc.free(pBase);
      malloc.free(pApp);
    }
  }

  Map<String, dynamic>? consentGetEditableForm() {
    return _callJson(() => _ffi.consentGetEditableForm(_handle));
  }

  Future<Map<String, dynamic>?> consentSubmitForm({
    required String deviceId,
    required String platform,
    String? userId,
    required Map<String, dynamic> formJson,
  }) async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    final payload = jsonEncode(formJson);
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final pDevice = deviceId.toNativeUtf8();
      final pPlatform = platform.toNativeUtf8();
      final pUser = userId != null ? userId.toNativeUtf8() : nullptr;
      final pForm = payload.toNativeUtf8();
      try {
        final ptr = ffi.consentSubmitForm(
          handle,
          pDevice.cast(),
          pPlatform.cast(),
          pUser.cast(),
          pForm.cast(),
        );
        if (ptr == nullptr) return null;
        final raw = ptr.toDartString();
        ffi.coreFreeString(ptr);
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return null;
      } finally {
        malloc.free(pDevice);
        malloc.free(pPlatform);
        if (pUser != nullptr) malloc.free(pUser);
        malloc.free(pForm);
      }
    });
  }

  /// Redeem a research-study access + study code, or (when [validateOnly])
  /// preview the pair without redeeming. Returns the runtime's JSON response.
  Future<Map<String, dynamic>?> enrolResearchStudy({
    required String accessCode,
    required String studyCode,
    bool validateOnly = false,
  }) async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final pAccess = accessCode.toNativeUtf8();
      final pStudy = studyCode.toNativeUtf8();
      try {
        final ptr = validateOnly
            ? ffi.validateStudyCodes(handle, pAccess.cast(), pStudy.cast())
            : ffi.enrolStudy(handle, pAccess.cast(), pStudy.cast());
        if (ptr == nullptr) return null;
        final raw = ptr.toDartString();
        ffi.coreFreeString(ptr);
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return null;
      } finally {
        malloc.free(pAccess);
        malloc.free(pStudy);
      }
    });
  }

  /// Withdraw from the device's active research study for this app. No codes
  /// needed — participant + app come from the device's signed cloud credential.
  /// Returns the service response (`{"withdrawn": bool, ...}`) or null.
  Future<Map<String, dynamic>?> withdrawResearchStudy() async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final ptr = ffi.withdrawStudy(handle);
      if (ptr == nullptr) return null;
      try {
        final raw = ptr.toDartString();
        ffi.coreFreeString(ptr);
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    });
  }

  /// Read the device's CURRENT active research-study enrolment for this app —
  /// the authoritative attribution state (same lookup the consent mint uses).
  /// Returns `{enrolled: bool, study: {...}, enrolment: {...}}`. Hosts should
  /// use this to correct a stale local "enrolled" flag.
  Future<Map<String, dynamic>?> researchStudyStatus() async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final ptr = ffi.researchStudyStatus(handle);
      if (ptr == nullptr) return null;
      try {
        final raw = ptr.toDartString();
        ffi.coreFreeString(ptr);
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    });
  }

  /// Request erasure of the data the participant contributed to their study.
  /// [dryRun] returns an inventory preview without deleting; a real request is
  /// accepted asynchronously and carries a `request_id`.
  Future<Map<String, dynamic>?> requestStudyDataDeletion({
    bool dryRun = false,
  }) async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final ptr = ffi.requestStudyDataDeletion(handle, dryRun);
      if (ptr == nullptr) return null;
      try {
        final raw = ptr.toDartString();
        ffi.coreFreeString(ptr);
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    });
  }

  bool consentClearStored() => _ffi.consentClearStored(_handle) == 0;

  Map<String, dynamic>? consentStatus() {
    return _callJson(() => _ffi.consentStatus(_handle));
  }

  Map<String, dynamic>? consentEffectiveState() {
    return _callJson(() => _ffi.consentEffectiveState(_handle));
  }

  bool consentNeedsTokenRefresh() =>
      _ffi.consentNeedsTokenRefresh(_handle) != 0;

  // ── Capabilities ─────────────────────────────────────────────────────

  bool loadCapabilityToken(String tokenJson, String secret) {
    final tj = tokenJson.toNativeUtf8();
    final s = secret.toNativeUtf8();
    try {
      return _ffi.loadCapabilityToken(_handle, tj.cast(), s.cast()) == 0;
    } finally {
      malloc.free(tj);
      malloc.free(s);
    }
  }

  // ── Queries ──────────────────────────────────────────────────────────

  List<dynamic>? listSessions() {
    final json = _readAndFree(_ffi.listSessions(_handle));
    if (json == null) return null;
    return jsonDecode(json) as List<dynamic>;
  }

  String? getSessionSummary(String sessionId) {
    return _withCString(sessionId, (p) {
      return _readAndFree(_ffi.getSessionSummary(_handle, p));
    });
  }

  List<dynamic>? getHsiWindows(
    String sessionId, {
    int startMs = 0,
    int endMs = 0,
    int limit = 0,
  }) {
    return _withCString(sessionId, (p) {
      final json = _readAndFree(
        _ffi.getHsiWindows(_handle, p, startMs, endMs, limit),
      );
      if (json == null) return null;
      return jsonDecode(json) as List<dynamic>;
    });
  }

  Map<String, dynamic>? getStorageUsage() {
    return _callJson(() => _ffi.getStorageUsage(_handle));
  }

  // ── Metrics ──────────────────────────────────────────────────────────

  bool recordMetric(Map<String, dynamic> event) {
    final json = jsonEncode(event);
    return _withCString(json, (p) => _ffi.recordMetric(_handle, p) == 0);
  }

  // ── Deletion ─────────────────────────────────────────────────────────

  bool deleteSession(String sessionId) {
    return _withCString(sessionId, (p) => _ffi.deleteSession(_handle, p) == 0);
  }

  /// Mark a stranded `state='active'` session as closed. Returns true on
  /// success (or when the session was already closed). Used by startup
  /// orphan-session sweeps.
  bool closeOrphanSession(String sessionId) {
    return _withCString(
      sessionId,
      (p) => _ffi.closeOrphanSession(_handle, p) == 0,
    );
  }

  bool wipeLocalData() => _ffi.wipeLocalData(_handle) == 0;

  int setRetentionDays(int days) => _ffi.setRetentionDays(_handle, days);

  // ── Sync ─────────────────────────────────────────────────────────────

  void setSyncEnabled(bool enabled) =>
      _ffi.setSyncEnabled(_handle, enabled ? 1 : 0);

  // ── Ambient capture ─────────────────────────────────────────────────

  /// Toggle the runtime's out-of-session HSI emission gate. When off
  /// (the default), the runtime forwards HSI windows only while a
  /// session is active; when on, it forwards every window. Hosts use
  /// this to drop the FFI fan-out cost on the background-capture
  /// path when the participant has revoked or paused ambient consent.
  void setAmbientCapture(bool enabled) =>
      _ffi.setAmbientCapture(_handle, enabled ? 1 : 0);

  /// Read the runtime's ambient-capture gate. `true` when the gate
  /// is on. Useful for diagnostics — Mirror's own
  /// `AmbientCaptureService` is the source of truth for the
  /// app-side flag.
  bool getAmbientCapture() => _ffi.getAmbientCapture(_handle) != 0;

  Map<String, dynamic>? syncNow() {
    return _callJson(() => _ffi.syncNow(_handle));
  }

  /// Create a new sync-space on the cloud and become its first
  /// device. Returns `{sync_space_id, recovery_key}` — the recovery
  /// key is the SRK fragment the user must store; without it a lost
  /// device cannot rejoin. Returns null when the engine isn't wired.
  Map<String, dynamic>? syncCreateSpace({String? deviceName}) {
    final name = deviceName ?? '';
    return _withCString(name, (p) {
      return _callJson(() => _ffi.syncCreateSpace(_handle, p.cast()));
    });
  }

  /// Generate a short-lived pairing token on the current sync-space.
  /// Returns `{token, expires_in}` — show the token to the user so a
  /// second device can call [syncJoinSpace] with it.
  Map<String, dynamic>? syncGeneratePairing() {
    return _callJson(() => _ffi.syncGeneratePairing(_handle));
  }

  /// Join an existing sync-space using a pairing token from
  /// [syncGeneratePairing]. Returns `{sync_space_id, status}` on
  /// success. The new device becomes the second member of the space
  /// and the next [syncNow] will pull every artifact the originator
  /// has pushed.
  Map<String, dynamic>? syncJoinSpace({
    required String pairingToken,
    String? deviceName,
  }) {
    final name = deviceName ?? '';
    return _withCString(pairingToken, (tokenPtr) {
      return _withCString(name, (namePtr) {
        return _callJson(
          () => _ffi.syncJoinSpace(_handle, tokenPtr.cast(), namePtr.cast()),
        );
      });
    });
  }

  /// Snapshot of the sync-engine state: `{enabled, sync_space_id,
  /// device_count}`. Use for the "paired with N devices" UI line.
  Map<String, dynamic>? syncStatus() {
    return _callJson(() => _ffi.syncStatus(_handle));
  }

  // ── Vendor Events ────────────────────────────────────────────────────

  /// Ingest a canonical vendor event (JSON map from CanonicalWearableEvent.toMap()).
  bool ingestVendorEvent(String eventJson) {
    return _withCString(
      eventJson,
      (p) => _ffi.ingestVendorEvent(_handle, p) == 0,
    );
  }

  /// Query stored vendor events. Returns parsed JSON list, or null on error.
  List<dynamic>? queryVendorEvents({
    String? provider,
    String? type,
    int? startMs,
    int? endMs,
    int limit = 100,
  }) {
    final query = jsonEncode({
      if (provider != null) 'provider': provider,
      if (type != null) 'type': type,
      if (startMs != null) 'start_ms': startMs,
      if (endMs != null) 'end_ms': endMs,
      'limit': limit,
    });
    return _withCString(query, (p) {
      final json = _readAndFree(_ffi.queryVendorEvents(_handle, p));
      if (json == null) return null;
      final list = jsonDecode(json) as List<dynamic>;
      // The runtime persists `payload` as a JSON string (see
      // CanonicalWearableEvent.toMap). Decode it back into a Map so callers
      // receive a fully-decoded event — matches the documented contract on
      // [Synheart.queryVendorEvents].
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final raw = item['payload'];
          if (raw is String && raw.isNotEmpty) {
            try {
              item['payload'] = jsonDecode(raw);
            } catch (_) {
              // Leave as-is; consumers can still inspect the string.
            }
          }
        }
      }
      return list;
    });
  }

  /// Get the latest vendor event for a provider + type. Returns JSON map or null.
  Map<String, dynamic>? getLatestVendorEvent(String provider, String type) {
    final pProv = provider.toNativeUtf8();
    final pType = type.toNativeUtf8();
    try {
      final json = _readAndFree(
        _ffi.getLatestVendorEvent(_handle, pProv.cast(), pType.cast()),
      );
      if (json == null) return null;
      final map = jsonDecode(json) as Map<String, dynamic>;
      // Decode the nested `payload` JSON string for the documented contract.
      final raw = map['payload'];
      if (raw is String && raw.isNotEmpty) {
        try {
          map['payload'] = jsonDecode(raw);
        } catch (_) {
          // Leave as-is.
        }
      }
      return map;
    } finally {
      malloc.free(pProv);
      malloc.free(pType);
    }
  }

  /// Delete all vendor events for a provider. Returns deleted count, or -1 on error.
  int deleteVendorEventsForProvider(String provider) {
    return _withCString(
      provider,
      (p) => _ffi.deleteVendorEventsForProvider(_handle, p),
    );
  }

  // ── SRM / Baselines ──────────────────────────────────────────────────

  String? baselinesJson() => _readAndFree(_ffi.baselinesJson(_handle));
  String? exportSrmSnapshot() => _readAndFree(_ffi.exportSrmSnapshot(_handle));

  bool loadSrmSnapshot(String json) {
    return _withCString(json, (p) => _ffi.loadSrmSnapshot(_handle, p) == 0);
  }

  Map<String, dynamic>? srmOverallStatus() {
    return _callJson(() => _ffi.srmOverallStatus(_handle));
  }

  // ── Cloud ────────────────────────────────────────────────────────────

  void enqueueHsi(String hsiJson, int timestampMs) {
    _withCString(hsiJson, (p) => _ffi.enqueueHsi(_handle, p, timestampMs));
  }

  int get uploadQueueLength => _ffi.uploadQueueLength(_handle);

  /// Wall-clock timestamp (Unix ms) of the most recent successful
  /// ingest upload. Returns null when nothing has uploaded yet in
  /// this process. Hosts use this to render a "Synced / Syncing /
  /// Pending" pill instead of exposing raw queue counts.
  int? get lastIngestSuccessAtMs {
    final ms = _ffi.lastIngestSuccessAtMs(_handle);
    return ms == 0 ? null : ms;
  }

  Map<String, dynamic>? flushUploads() {
    return _callJson(() => _ffi.flushUploads(_handle));
  }

  Map<String, dynamic>? uploadMetadata() {
    return _callJson(() => _ffi.uploadMetadata(_handle));
  }

  // ── HSI history (on-device mirror of uploaded payloads) ─────────────
  //
  // Populated by the ingest connector on HTTP 200, archiving each
  // HSI chunk to the local history mirror. Retention is age-based
  // (default 30 days). Returns empty / 0 when the runtime has no cloud
  // connector configured.

  /// List archived HSI payloads in upload order (oldest first).
  ///
  /// - [since]: filter rows uploaded at or after this instant.
  /// - [limit]: cap the returned count; `null` or `0` means unbounded.
  List<Map<String, dynamic>> hsiHistoryList({DateTime? since, int? limit}) {
    if (_disposed) return const [];
    final sinceMs = since?.millisecondsSinceEpoch ?? 0;
    final lim = (limit ?? 0).clamp(0, 1 << 31);
    final ptr = _ffi.hsiHistoryList(_handle, sinceMs, lim);
    final raw = _readAndFree(ptr);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList(
          growable: false,
        );
      }
    } catch (_) {}
    return const [];
  }

  /// Fetch archived HSI windows from the cloud archive for `[fromMs, toMs]`
  /// (epoch ms). Each map is a full HSI window payload exactly as archived (any
  /// HSI version) — the host parses it with the same path it uses for local
  /// windows. Returns empty on error, when no cloud connector is configured, or
  /// when the native symbol is absent (older vendored lib).
  ///
  /// The FFI call performs blocking network I/O, so it runs on a background
  /// isolate (mirroring [sdkRegisterDevice]) — calling it on the UI isolate
  /// froze the main thread and ANR'd while a request was in flight (e.g. a
  /// pull-to-refresh keyed on a subject the backend never satisfies).
  Future<List<Map<String, dynamic>>> fetchCloudHsiWindows({
    required int fromMs,
    required int toMs,
  }) async {
    if (_disposed) return const [];
    final handleAddr = _handle.address;
    // Guard the symbol lookup + call: a vendored lib that predates this FFI
    // export throws ArgumentError on first `fetchCloudHsi` access. Treat a
    // missing symbol (or any FFI/parse failure) as "no cloud data".
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return const <Map<String, dynamic>>[];
      final handle = Pointer<Void>.fromAddress(handleAddr);
      try {
        final ptr = ffi.fetchCloudHsi(handle, fromMs, toMs);
        if (ptr == nullptr) return const <Map<String, dynamic>>[];
        final raw = ptr.toDartString();
        ffi.coreFreeString(ptr);
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.whereType<Map<String, dynamic>>().toList(
            growable: false,
          );
        }
      } catch (_) {}
      return const <Map<String, dynamic>>[];
    });
  }

  /// Number of archived HSI payloads on-device. Returns `0` on error.
  int hsiHistoryCount() {
    if (_disposed) return 0;
    final n = _ffi.hsiHistoryCount(_handle);
    return n < 0 ? 0 : n;
  }

  /// Wipe on-device HSI history. Intended for user-initiated
  /// "delete my data" flows. Returns true on success.
  bool hsiHistoryClear() {
    if (_disposed) return false;
    return _ffi.hsiHistoryClear(_handle) == 0;
  }

  // ── Wellness Score ───────────────────────────────────────────────────

  /// Get the last Wellness Score as JSON, or null if baselines are not ready.
  String? wellnessJson() => _readAndFree(_ffi.wellnessJson(_handle));

  String? lastFeatures() => _readAndFree(_ffi.lastFeatures(_handle));

  // ── Diagnostics ──────────────────────────────────────────────────────

  String? diagnostics() => _readAndFree(_ffi.diagnostics(_handle));
  int get lastErrorCode => _ffi.lastErrorCode(_handle);
  bool get isRuntimeAvailable => _ffi.isRuntimeAvailable(_handle) != 0;
  bool get isNetworkReachable => _ffi.isNetworkReachable(_handle) != 0;

  // ── Account ──────────────────────────────────────────────────────────

  bool requestAccountDeletion() => _ffi.requestAccountDeletion(_handle) == 0;
  bool cancelAccountDeletion() => _ffi.cancelAccountDeletion(_handle) == 0;

  // ── Customer-facing data deletion (GDPR Article 17) ─────────────────

  /// Request cloud-side deletion of every byte the platform holds for the
  /// currently-bound subject (the value derived from your `client_id` at
  /// register time). Returns the persisted request row as parsed JSON, or
  /// `{"error": "..."}` if the call failed.
  ///
  /// `reason` and `contact` are optional — both land in the audit row
  /// metadata so operators can correlate later. `dryRun=true` exercises the
  /// auth + persistence path without running the actual purge.
  ///
  /// Runs on a background isolate; the underlying HTTPS call can block.
  Future<Map<String, dynamic>?> requestDataDeletion({
    String? reason,
    String? contact,
    bool dryRun = false,
  }) async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final reasonPtr = (reason == null || reason.isEmpty)
          ? nullptr
          : reason.toNativeUtf8();
      final contactPtr = (contact == null || contact.isEmpty)
          ? nullptr
          : contact.toNativeUtf8();
      try {
        final resPtr = ffi.requestDataDeletion(
          handle,
          reasonPtr.cast(),
          contactPtr.cast(),
          dryRun,
        );
        if (resPtr == nullptr) return null;
        final str = resPtr.toDartString();
        ffi.coreFreeString(resPtr);
        return jsonDecode(str) as Map<String, dynamic>;
      } catch (_) {
        return null;
      } finally {
        if (reasonPtr != nullptr) malloc.free(reasonPtr);
        if (contactPtr != nullptr) malloc.free(contactPtr);
      }
    });
  }

  /// Poll the status of a deletion request. `status` transitions through
  /// pending → in_progress → completed (or failed). On success the `result`
  /// field carries per-layer purge stats from the server.
  Future<Map<String, dynamic>?> getDataDeletion(String requestId) async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final idPtr = requestId.toNativeUtf8();
      try {
        final resPtr = ffi.getDataDeletion(handle, idPtr.cast());
        if (resPtr == nullptr) return null;
        final str = resPtr.toDartString();
        ffi.coreFreeString(resPtr);
        return jsonDecode(str) as Map<String, dynamic>;
      } catch (_) {
        return null;
      } finally {
        malloc.free(idPtr);
      }
    });
  }

  // ── Baseline local bridge ──────────────────────────────────────────
  //
  // Cross-device baseline transport rides the existing sync engine
  // (`/v1/sync/`); there's no separate baseline cloud bridge here.

  /// Read the latest locally-persisted baseline envelope per kind
  /// (synchronous on-device SQLite read + decryption — no network).
  /// Returns `{snapshots: [...]}` so the Dart-side facade can parse
  /// envelopes uniformly. Null when the runtime binary doesn't ship
  /// the symbol.
  Future<Map<String, dynamic>?> baselineHydrateLocal() async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final fn = ffi.baselineHydrateLocal;
      if (fn == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      try {
        final resPtr = fn(handle);
        if (resPtr == nullptr) return null;
        final str = resPtr.toDartString();
        ffi.coreFreeString(resPtr);
        return jsonDecode(str) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    });
  }

  /// Encrypt every cached baseline envelope into a passphrase-keyed
  /// offline blob (`.srm.synheart`). Returns the raw bytes ready for
  /// the OS share sheet, or null when the runtime binary doesn't
  /// ship the FFI / no envelopes are cached / the passphrase is
  /// empty.
  Future<Uint8List?> baselineExportOffline({required String passphrase}) async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final fn = ffi.baselineExportOffline;
      if (fn == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final passPtr = passphrase.toNativeUtf8();
      try {
        final resPtr = fn(handle, passPtr.cast());
        if (resPtr == nullptr) return null;
        final str = resPtr.toDartString();
        ffi.coreFreeString(resPtr);
        final decoded = jsonDecode(str) as Map<String, dynamic>;
        if (decoded['error'] is String) return null;
        final b64 = decoded['blob_b64'] as String?;
        if (b64 == null) return null;
        return base64Decode(b64);
      } catch (_) {
        return null;
      } finally {
        malloc.free(passPtr);
      }
    });
  }

  /// Decrypt + import a `.srm.synheart` blob into local storage.
  /// Returns `{imported, skipped, errors, kinds, exporter_device_id,
  /// created_at_ms}`. Null when the runtime binary doesn't ship the
  /// FFI; an `{"error": ...}` map for wrong passphrase / tampered blob.
  Future<Map<String, dynamic>?> baselineImportOffline({
    required String passphrase,
    required Uint8List blob,
  }) async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    final blobB64 = base64Encode(blob);
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final fn = ffi.baselineImportOffline;
      if (fn == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      final passPtr = passphrase.toNativeUtf8();
      final blobPtr = blobB64.toNativeUtf8();
      try {
        final resPtr = fn(handle, passPtr.cast(), blobPtr.cast());
        if (resPtr == nullptr) return null;
        final str = resPtr.toDartString();
        ffi.coreFreeString(resPtr);
        return jsonDecode(str) as Map<String, dynamic>;
      } catch (_) {
        return null;
      } finally {
        malloc.free(passPtr);
        malloc.free(blobPtr);
      }
    });
  }

  /// List recent deletion requests for this caller's org. Mostly useful for
  /// dashboards / audit views; most apps will only call
  /// [requestDataDeletion] + [getDataDeletion].
  Future<Map<String, dynamic>?> listDataDeletions({
    int limit = 20,
    int offset = 0,
  }) async {
    if (_disposed) return null;
    final handleAddr = _handle.address;
    return Isolate.run(() {
      final ffi = SynheartCoreFFI.load();
      if (ffi == null) return null;
      final handle = Pointer<Void>.fromAddress(handleAddr);
      try {
        final resPtr = ffi.listDataDeletions(handle, limit, offset);
        if (resPtr == nullptr) return null;
        final str = resPtr.toDartString();
        ffi.coreFreeString(resPtr);
        return jsonDecode(str) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    });
  }

  // ── Stream (RAMEN vendor sync) ─────────────────────────────────────

  NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>? _streamCallable;

  /// Start the RAMEN streaming connection.
  ///
  /// [config] must include: `host`, `port`, `app_id`, `device_id`, `user_id`.
  /// Optional: `api_key`, `use_tls`, `providers`, `event_types`.
  int startStream(Map<String, dynamic> config) {
    final json = jsonEncode(config);
    return _withCString(json, (p) => _ffi.streamStart(_handle, p));
  }

  /// Stop the RAMEN streaming connection.
  int stopStream() => _ffi.streamStop(_handle);

  /// Register a callback for RAMEN stream events.
  ///
  /// The [onEvent] function receives raw event JSON for each vendor event.
  /// Uses the same NativeCallable.listener pattern as HSI callback.
  void setStreamCallback(void Function(String eventJson) onEvent) {
    clearStreamCallback();

    void nativeCallback(Pointer<Utf8> jsonPtr, Pointer<Void> _) {
      if (jsonPtr == nullptr) return;
      final text = _readFfiStringAndFree(jsonPtr, _ffi.coreFreeString);
      if (text != null) onEvent(text);
    }

    _streamCallable =
        NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>.listener(
          nativeCallback,
        );
    _ffi.setStreamCallback(_handle, _streamCallable!.nativeFunction, nullptr);
  }

  /// Unregister the stream callback.
  void clearStreamCallback() {
    if (_streamCallable != null) {
      _streamCallable!.close();
      _streamCallable = null;
    }
  }

  /// Get the current stream connection state.
  String? streamState() => _readAndFree(_ffi.streamState(_handle));

  // ── HSI state callback ──────────────────────────────────────────────

  NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>? _hsiCallable;

  /// Register a callback for real-time HSI state updates.
  ///
  /// The [onHsi] function is called on each HSI frame (typically 1Hz during
  /// an active session) with the raw JSON string.
  ///
  /// Only one callback can be active. Call [clearHsiCallback] to unregister.
  void setHsiCallback(void Function(String hsiJson) onHsi) {
    clearHsiCallback();

    void nativeCallback(Pointer<Utf8> jsonPtr, Pointer<Void> _) {
      if (jsonPtr == nullptr) return;
      final text = _readFfiStringAndFree(jsonPtr, _ffi.coreFreeString);
      if (text != null) onHsi(text);
    }

    _hsiCallable =
        NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>.listener(
          nativeCallback,
        );
    _ffi.setHsiCallback(_handle, _hsiCallable!.nativeFunction, nullptr);
  }

  /// Unregister the HSI callback.
  void clearHsiCallback() {
    if (_hsiCallable != null) {
      _ffi.clearHsiCallback(_handle);
      _hsiCallable!.close();
      _hsiCallable = null;
    }
  }

  // ── Lab ──────────────────────────────────────────────────────────────

  /// Whether the lab C ABI symbols are available.
  bool get isLabAvailable => _ffi.labAvailable(_handle) != 0;

  /// Start a lab session. Returns `null` on success, or a short error
  /// string identifying the failure code from the runtime.
  ///
  /// The runtime FFI returns `c_int`: `0` on success, `1` on
  /// `"Lab session already active"`, and other small integers for other
  /// validation failures. We surface non-zero codes as
  /// `"lab_start: error code N"` so callers (e.g. Mirror's
  /// `MirrorLabSessionManager`) can distinguish success from failure
  /// without having to interpret the raw integer.
  String? labStart(String protocolJson, int startedAtMs) {
    return _withCString(protocolJson, (p) {
      final rc = _ffi.labStart(_handle, p, startedAtMs);
      if (rc == 0) return null;
      return 'lab_start: error code $rc';
    });
  }

  /// Open a window in the active lab session. Returns the window ID.
  String? labOpenWindow(
    String? parentId,
    String windowType,
    String? label,
    int startedAtMs,
  ) {
    final pParent = (parentId ?? '').toNativeUtf8();
    final pType = windowType.toNativeUtf8();
    final pLabel = (label ?? '').toNativeUtf8();
    try {
      return _readAndFree(
        _ffi.labOpenWindow(
          _handle,
          pParent.cast(),
          pType.cast(),
          pLabel.cast(),
          startedAtMs,
        ),
      );
    } finally {
      malloc.free(pParent);
      malloc.free(pType);
      malloc.free(pLabel);
    }
  }

  /// Close a window in the active lab session.
  bool labCloseWindow(String windowId, int endedAtMs) {
    return _withCString(
      windowId,
      (p) => _ffi.labCloseWindow(_handle, p, endedAtMs) == 0,
    );
  }

  /// Set protocol-specific values on a lab window.
  bool labSetWindowValues(String windowId, String valuesJson) {
    final pId = windowId.toNativeUtf8();
    final pJson = valuesJson.toNativeUtf8();
    try {
      return _ffi.labSetWindowValues(_handle, pId.cast(), pJson.cast()) == 0;
    } finally {
      malloc.free(pId);
      malloc.free(pJson);
    }
  }

  /// Merge session-level metadata into extra_data. Returns null on success,
  /// or `'lab_merge_extra_data: error code N'` when the runtime rejected
  /// the patch (e.g. no active lab session, malformed JSON).
  String? labMergeExtraData(String patchJson) {
    return _withCString(patchJson, (p) {
      final rc = _ffi.labMergeExtraData(_handle, p);
      if (rc == 0) return null;
      return 'lab_merge_extra_data: error code $rc';
    });
  }

  /// Set per-window state-data overrides.
  bool labSetStateOverrides(String windowId, String overridesJson) {
    final pId = windowId.toNativeUtf8();
    final pJson = overridesJson.toNativeUtf8();
    try {
      return _ffi.labSetStateOverrides(_handle, pId.cast(), pJson.cast()) == 0;
    } finally {
      malloc.free(pId);
      malloc.free(pJson);
    }
  }

  /// Finalize the lab session. Returns the complete payload JSON.
  String? labFinalize(int endedAtMs) {
    return _readAndFree(_ffi.labFinalize(_handle, endedAtMs));
  }

  /// Get the last lab export JSON (populated after session end in research mode).
  String? labExportJson() => _readAndFree(_ffi.labExportJson(_handle));

  /// Whether the runtime exports the lab re-enqueue symbol
  /// (`synheart_core_reenqueue_lab_session`, engine v0.8.1+). Older
  /// runtime binaries return false; callers can fall back to running
  /// a fresh session.
  bool get isLabReenqueueAvailable => _ffi.labReenqueueSession != null;

  /// Re-enqueue a previously-finalized lab session JSON for cloud upload.
  ///
  /// Used to retry sessions whose initial upload was dropped on a 4xx
  /// (typically a cloud schema mismatch — the runtime deletes those rows
  /// from the upload queue per `ingest/hsi/connector.rs`). Read the
  /// persisted payload from `lab_payloads` SQLite (or your host-side
  /// equivalent) and pass it back here.
  ///
  /// Return codes mirror the underlying FFI:
  ///   * [LabReenqueueResult.queued] — payload queued; HTTP happens async
  ///   * [LabReenqueueResult.researchNotAllowed] — research consent not granted
  ///   * [LabReenqueueResult.cloudNotConfigured] — no cloud connector
  ///   * [LabReenqueueResult.parseError] — supplied JSON did not parse
  ///   * [LabReenqueueResult.invalidArgument] — null handle / empty JSON
  ///   * [LabReenqueueResult.unsupported] — runtime binary doesn't export
  ///     the symbol; rebuild against engine v0.8.1+
  LabReenqueueResult labReenqueueSession(String sessionJson) {
    final fn = _ffi.labReenqueueSession;
    if (fn == null) return LabReenqueueResult.unsupported;
    final ptr = sessionJson.toNativeUtf8();
    try {
      final code = fn(_handle, ptr);
      return LabReenqueueResult.fromCode(code);
    } finally {
      malloc.free(ptr);
    }
  }

  // ── Lab metadata ───────────────────────────────────────────────────

  /// Whether the runtime exports the lab metadata symbols (older builds may not).
  bool get isLabMetadataAvailable => _ffi.labEnsureMetadata != null;

  /// Build the metadata payload from current config + caller-supplied device
  /// and user info, then upload it if the canonical hash differs from the
  /// cached copy or the dirty flag is set. Returns the active `meta_id`, or
  /// null on error.
  ///
  /// Blocks the calling thread; run this off the UI thread (the bootstrapper
  /// already does so during app start). Both `userInfoJson` and
  /// `deviceExtraJson` may be null.
  String? labEnsureMetadata({
    required String deviceId,
    required String platform,
    required String osVersion,
    String? userInfoJson,
    String? deviceExtraJson,
  }) {
    final fn = _ffi.labEnsureMetadata;
    if (fn == null) return null;
    final pDev = deviceId.toNativeUtf8();
    final pPlat = platform.toNativeUtf8();
    final pOs = osVersion.toNativeUtf8();
    final pUser = (userInfoJson ?? '').toNativeUtf8();
    final pExtra = (deviceExtraJson ?? '').toNativeUtf8();
    try {
      return _readAndFree(
        fn(
          _handle,
          pDev.cast(),
          pPlat.cast(),
          pOs.cast(),
          pUser.cast(),
          pExtra.cast(),
        ),
      );
    } finally {
      malloc.free(pDev);
      malloc.free(pPlat);
      malloc.free(pOs);
      malloc.free(pUser);
      malloc.free(pExtra);
    }
  }

  /// Mark the cached lab metadata as needing re-upload (profile edit, device
  /// swap, app version bump, consent change). The next [labEnsureMetadata]
  /// call will POST regardless of hash.
  bool labMarkMetadataDirty(String reason) {
    final fn = _ffi.labMarkMetadataDirty;
    if (fn == null) return false;
    return _withCString(reason, (p) => fn(_handle, p) == 0);
  }

  /// Cached `meta_id` to stamp on lab sessions, or null if nothing is cached.
  String? labCurrentMetadataId() {
    final fn = _ffi.labCurrentMetadataId;
    if (fn == null) return null;
    return _readAndFree(fn(_handle));
  }

  // ── Build info / Version ────────────────────────────────────────────

  /// All synheart crate versions, target, profile, and features as JSON.
  /// No handle needed — compile-time info.
  static Map<String, dynamic>? buildInfo() {
    final ffi = SynheartCoreFFI.load();
    if (ffi == null) return null;
    final ptr = ffi.buildInfo();
    if (ptr == nullptr) return null;
    final json = ptr.toDartString();
    ffi.coreFreeString(ptr);
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// The native synheart-engine version string, or null.
  static String? version() {
    final ffi = SynheartCoreFFI.load();
    if (ffi == null || ffi.version == null) return null;
    final ptr = ffi.version!();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    ffi.coreFreeString(ptr);
    return str;
  }

  /// Number of HSI frames produced in the current session.
  int frameCount() => _ffi.frameCount(_handle);

  /// Quality value of the last HSI frame, or 0.0 if none.
  double lastQuality() => _ffi.lastQuality?.call(_handle) ?? 0.0;

  // ── Internal helpers ─────────────────────────────────────────────────

  /// Read a C string pointer, convert to Dart String, and free it.
  String? _readAndFree(Pointer<Utf8> ptr) {
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    _ffi.coreFreeString(ptr);
    return str;
  }

  /// Call a function that returns a JSON pointer, parse it as a Map.
  Map<String, dynamic>? _callJson(Pointer<Utf8> Function() fn) {
    final json = _readAndFree(fn());
    if (json == null) return null;
    return jsonDecode(json) as Map<String, dynamic>;
  }

  /// Allocate a native UTF-8 string, call the function, then free it.
  T _withCString<T>(String s, T Function(Pointer<Utf8>) fn) {
    final ptr = s.toNativeUtf8();
    try {
      return fn(ptr.cast());
    } finally {
      malloc.free(ptr);
    }
  }
}

/// Result of a [CoreRuntimeBridge.labReenqueueSession] call. Mirrors
/// the return codes from the underlying
/// `synheart_core_reenqueue_lab_session` FFI.
enum LabReenqueueResult {
  /// Payload queued for upload (HTTP happens async on the same flush
  /// cadence as HSI).
  queued,

  /// Research consent is not granted for this session — caller must
  /// re-prompt or upgrade the consent tier before retrying.
  researchNotAllowed,

  /// No cloud connector is configured (SDK not initialized with
  /// `cloudConfig`).
  cloudNotConfigured,

  /// The supplied JSON did not parse. Treat the row as unrecoverable
  /// without manual intervention.
  parseError,

  /// Null handle or empty `sessionJson` — caller bug.
  invalidArgument,

  /// The currently-linked runtime binary doesn't export the re-enqueue
  /// symbol. Rebuild against engine v0.8.1+ and re-link.
  unsupported;

  /// Decode the FFI return code from
  /// `synheart_core_reenqueue_lab_session`. Unknown codes map to
  /// [parseError] (caller-side defensive default).
  static LabReenqueueResult fromCode(int code) {
    switch (code) {
      case 0:
        return LabReenqueueResult.queued;
      case 1:
        return LabReenqueueResult.researchNotAllowed;
      case 2:
        return LabReenqueueResult.cloudNotConfigured;
      case 3:
        return LabReenqueueResult.parseError;
      case 4:
        return LabReenqueueResult.invalidArgument;
      default:
        return LabReenqueueResult.parseError;
    }
  }
}
