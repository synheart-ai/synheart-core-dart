/// Safe Dart wrapper over `synheart_core_runtime` C ABI.
///
/// Replaces the internal storage, crypto, sync, consent, artifact pipeline,
/// and cloud connector logic that was previously implemented in pure Dart.
/// Platform-specific code (Keychain, HealthKit, sensors) stays in Flutter plugins.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'package:flutter/foundation.dart';

import 'ffi_bindings.dart';
import 'sdk_crypto_callbacks.dart';
import 'sdk_ffi.dart';

/// Forwarder installed before `synheart_core_init_logging` (top-level for FFI).
void Function(String line)? synheartRuntimeLogForwarder;

void _synheartRuntimeLogTrampoline(Pointer<Utf8> line, Pointer<Void> userData) {
  if (line == nullptr) return;
  final text = line.toDartString();
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
///   'app_id': 'com.example',
///   'subject_id': 'sub_abc123',
///   'mode': 'personal',
/// });
/// final session = bridge?.startSession();
/// bridge?.pushHr(DateTime.now().millisecondsSinceEpoch, 72.0);
/// bridge?.stopSession();
/// bridge?.dispose();
/// ```
class CoreRuntimeBridge {
  CoreRuntimeBridge._(this._ffi, this._handle);

  final SynheartCoreFFI _ffi;
  final Pointer<Void> _handle;
  bool _disposed = false;
  Pointer<SynheartSdkCryptoCallbacks>? _sdkCryptoTable;

  /// Default `env_filter` when [initRuntimeLogging] is called with a null/empty filter.
  // static String defaultRuntimeLogEnvFilter = 'info,synheart_core_runtime=debug';
  static String defaultRuntimeLogEnvFilter = 'synheart_core_runtime=trace,info';

  static bool _loggingInstalled = false;
  static NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>? _logCallable;

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
      _logCallable ??= NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>.listener(_synheartRuntimeLogTrampoline);
      final rc = lib.initLogging(filterArg, _logCallable!.nativeFunction, nullptr);
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

  /// Create a bridge from a config map. Returns null if the native
  /// library is unavailable or config is invalid.
  static CoreRuntimeBridge? create(Map<String, dynamic> config) {
    final ffi = SynheartCoreFFI.load();
    if (ffi == null) return null;

    // §1b: logging before core runtime bridge is created (idempotent if app called [initRuntimeLogging]).
    initRuntimeLogging(ffi: ffi);

    final json = jsonEncode(config);
    final cJson = json.toNativeUtf8();
    try {
      final handle = ffi.coreNew(cJson.cast());
      if (handle == nullptr) return null;
      return CoreRuntimeBridge._(ffi, handle);
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
  /// Returns `0` on success. On failure, frees the allocated callback table.
  int setSdkCryptoCallbacks(SynheartCoreCryptoCallbacks callbacks) {
    if (_disposed) return -1;
    if (!_ffi.sdkFfi.isAvailable) return -2;
    synheartSdkCryptoAttach(callbacks);
    if (_sdkCryptoTable != null) {
      calloc.free(_sdkCryptoTable!);
      _sdkCryptoTable = null;
    }
    final table = calloc<SynheartSdkCryptoCallbacks>();
    synheartFillSdkCryptoStruct(table);
    final rc = _ffi.sdkFfi.setCryptoCallbacksInvoke(_handle, table);
    if (rc != 0) {
      calloc.free(table);
      synheartSdkCryptoAttach(null);
      return rc;
    }
    _sdkCryptoTable = table;
    return 0;
  }

  /// Register host crypto callbacks natively bypassing Dart trampolines.
  int setSdkCryptoCallbacksRaw(Pointer<SynheartSdkCryptoCallbacks> table) {
    if (_disposed) return -1;
    if (!_ffi.sdkFfi.isAvailable) return -2;
    synheartSdkCryptoAttach(null);
    if (_sdkCryptoTable != null) {
      calloc.free(_sdkCryptoTable!);
    }
    final rc = _ffi.sdkFfi.setCryptoCallbacksInvoke(_handle, table);
    if (rc != 0) {
      calloc.free(table);
      return rc;
    }
    _sdkCryptoTable = table;
    return 0;
  }

  /// §3 — device registration (attestation). [clientId] is the app user id for this session.
  /// Runs on a background isolate so the blocking FFI call doesn't ANR the UI thread.
  Future<Map<String, dynamic>?> sdkRegisterDevice(String clientId) async {
    if (_disposed || _ffi.sdkFfi.registerDevice == null) return null;
    final handleAddr = _handle.address;
    return await Isolate.run(() {
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
      synheartSdkCryptoAttach(null);
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

  // ── Sensor push ──────────────────────────────────────────────────────

  void pushRr(int tsMs, double rrMs) => _ffi.pushRr(_handle, tsMs, rrMs);
  void pushHr(int tsMs, double bpm) => _ffi.pushHr(_handle, tsMs, bpm);
  void pushAccel(int tsMs, double x, double y, double z) =>
      _ffi.pushAccel(_handle, tsMs, x, y, z);
  void pushBehavior(int tsMs, int eventType, double value) =>
      _ffi.pushBehavior(_handle, tsMs, eventType, value);

  void pushSleepStages(String json) {
    _withCString(json, (p) => _ffi.pushSleepStages(_handle, p));
  }

  /// Batch ingest. Returns HSI JSON if a window completed.
  String? ingestBatch(String batchJson, int nowMs) {
    return _withCString(batchJson, (p) {
      return _readAndFree(_ffi.ingestBatch(_handle, p, nowMs));
    });
  }

  // ── Consent ──────────────────────────────────────────────────────────

  bool grantConsent(String type) {
    return _withCString(type, (p) => _ffi.grantConsent(_handle, p) == 0);
  }

  bool revokeConsent(String type) {
    return _withCString(type, (p) => _ffi.revokeConsent(_handle, p) == 0);
  }

  bool hasConsent(String type) {
    return _withCString(type, (p) => _ffi.hasConsent(_handle, p) != 0);
  }

  Map<String, dynamic>? currentConsent() {
    return _callJson(() => _ffi.currentConsent(_handle));
  }

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

  List<dynamic>? getHsiWindows(String sessionId,
      {int startMs = 0, int endMs = 0, int limit = 0}) {
    return _withCString(sessionId, (p) {
      final json = _readAndFree(
          _ffi.getHsiWindows(_handle, p, startMs, endMs, limit));
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

  bool wipeLocalData() => _ffi.wipeLocalData(_handle) == 0;

  int setRetentionDays(int days) => _ffi.setRetentionDays(_handle, days);

  // ── Sync ─────────────────────────────────────────────────────────────

  void setSyncEnabled(bool enabled) =>
      _ffi.setSyncEnabled(_handle, enabled ? 1 : 0);

  Map<String, dynamic>? syncNow() {
    return _callJson(() => _ffi.syncNow(_handle));
  }

  // ── Vendor Events ────────────────────────────────────────────────────

  /// Ingest a canonical vendor event (JSON map from CanonicalWearableEvent.toMap()).
  bool ingestVendorEvent(String eventJson) {
    return _withCString(
        eventJson, (p) => _ffi.ingestVendorEvent(_handle, p) == 0);
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
      return jsonDecode(json) as List<dynamic>;
    });
  }

  /// Get the latest vendor event for a provider + type. Returns JSON map or null.
  Map<String, dynamic>? getLatestVendorEvent(String provider, String type) {
    final pProv = provider.toNativeUtf8();
    final pType = type.toNativeUtf8();
    try {
      final json = _readAndFree(
          _ffi.getLatestVendorEvent(_handle, pProv.cast(), pType.cast()));
      if (json == null) return null;
      return jsonDecode(json) as Map<String, dynamic>;
    } finally {
      malloc.free(pProv);
      malloc.free(pType);
    }
  }

  /// Delete all vendor events for a provider. Returns deleted count, or -1 on error.
  int deleteVendorEventsForProvider(String provider) {
    return _withCString(
        provider, (p) => _ffi.deleteVendorEventsForProvider(_handle, p));
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

  Map<String, dynamic>? flushUploads() {
    return _callJson(() => _ffi.flushUploads(_handle));
  }

  Map<String, dynamic>? uploadMetadata() {
    return _callJson(() => _ffi.uploadMetadata(_handle));
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

  bool requestAccountDeletion() =>
      _ffi.requestAccountDeletion(_handle) == 0;
  bool cancelAccountDeletion() =>
      _ffi.cancelAccountDeletion(_handle) == 0;

  // ── Stream (RAMEN vendor sync) ─────────────────────────────────────

  NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>? _streamCallable;

  /// Start the Rust RAMEN streaming connection.
  ///
  /// [config] must include: `host`, `port`, `app_id`, `device_id`, `user_id`.
  /// Optional: `api_key`, `use_tls`, `providers`, `event_types`.
  int startStream(Map<String, dynamic> config) {
    final json = jsonEncode(config);
    return _withCString(json, (p) => _ffi.streamStart(_handle, p));
  }

  /// Stop the Rust RAMEN streaming connection.
  int stopStream() => _ffi.streamStop(_handle);

  /// Register a callback for RAMEN stream events.
  ///
  /// The [onEvent] function receives raw event JSON for each vendor event.
  /// Uses the same NativeCallable.listener pattern as HSI callback.
  void setStreamCallback(void Function(String eventJson) onEvent) {
    clearStreamCallback();

    void nativeCallback(Pointer<Utf8> jsonPtr, Pointer<Void> _) {
      if (jsonPtr != nullptr) {
        onEvent(jsonPtr.toDartString());
      }
    }

    _streamCallable = NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>
        .listener(nativeCallback);
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
      if (jsonPtr != nullptr) {
        onHsi(jsonPtr.toDartString());
      }
    }

    _hsiCallable = NativeCallable<Void Function(Pointer<Utf8>, Pointer<Void>)>
        .listener(nativeCallback);
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

  /// Start a lab session. Returns null on success, or an error string.
  String? labStart(String protocolJson, int startedAtMs) {
    return _withCString(protocolJson, (p) {
      return _readAndFree(_ffi.labStart(_handle, p, startedAtMs));
    });
  }

  /// Open a window in the active lab session. Returns the window ID.
  String? labOpenWindow(String? parentId, String windowType, String? label, int startedAtMs) {
    final pParent = (parentId ?? '').toNativeUtf8();
    final pType = windowType.toNativeUtf8();
    final pLabel = (label ?? '').toNativeUtf8();
    try {
      return _readAndFree(
        _ffi.labOpenWindow(_handle, pParent.cast(), pType.cast(), pLabel.cast(), startedAtMs),
      );
    } finally {
      malloc.free(pParent);
      malloc.free(pType);
      malloc.free(pLabel);
    }
  }

  /// Close a window in the active lab session.
  bool labCloseWindow(String windowId, int endedAtMs) {
    return _withCString(windowId, (p) => _ffi.labCloseWindow(_handle, p, endedAtMs) == 0);
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

  /// Merge session-level metadata into extra_data. Returns null on success, or error.
  String? labMergeExtraData(String patchJson) {
    return _withCString(patchJson, (p) {
      return _readAndFree(_ffi.labMergeExtraData(_handle, p));
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
    if (ffi == null) return null;
    final ptr = ffi.version();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    ffi.coreFreeString(ptr);
    return str;
  }

  /// Number of HSI frames produced in the current session.
  int frameCount() => _ffi.frameCount(_handle);

  /// Quality value of the last HSI frame, or 0.0 if none.
  double lastQuality() => _ffi.lastQuality(_handle);

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
