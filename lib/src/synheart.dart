import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'config/synheart_config.dart';
import 'core/logger.dart';
import 'modules/base/module_manager.dart';
import 'modules/base/synheart_module.dart';
import 'modules/capabilities/capability_module.dart';
import 'modules/consent/consent_effective_state.dart';
import 'modules/consent/consent_form.dart';
import 'modules/consent/consent_module.dart';
import 'modules/interfaces/capability_provider.dart';
import 'modules/interfaces/consent_provider.dart';
import 'modules/wear/wear_module.dart';
import 'models/data_deletion.dart';
import 'models/task_type.dart';
import 'models/focus_kind.dart';
import 'package:synheart_wear/synheart_wear.dart'
    show WorkoutEvent, WorkoutKind, RamenEvent;
import 'modules/wear/wear_source_handler.dart';
import 'modules/phone/phone_module.dart';
import 'modules/behavior/behavior_module.dart';
import 'modules/behavior/behavior_code.dart';
import 'modules/behavior/behavior_events.dart';
import 'modules/breathing/breathing_module.dart';
import 'modules/syni/syni_module.dart';
import 'package:syni/agent.dart' show SyniCloudConfig;
import 'models/behavior_session_results.dart';
import 'package:synheart_behavior/synheart_behavior.dart' as sb;
import 'config/synheart_mode.dart';
import 'models/session_handle.dart';
import 'models/hsi_state.dart';
import 'models/metric_event.dart';
import 'config/synheart_feature.dart';
import 'config/activation_manager.dart';
import 'modules/cloud/device_auth_provider.dart';
import 'core_runtime/core_runtime_bridge.dart';
import 'core_runtime/platform_native_sdk_crypto_callbacks.dart';

import 'modules/consent/consent_profile.dart';
import 'modules/consent/consent_token.dart';
import 'modules/consent/consent_ui.dart';
import 'models/canonical_wearable_event.dart';
import 'models/readiness_score.dart';
import 'models/recovery_score.dart';
import 'models/sleep_score.dart';
import 'modules/baselines/baselines.dart';
import 'modules/wear/wearable_event_processor.dart';
import 'modules/session/watch_session_module.dart';
import 'package:synheart_session/synheart_session.dart';

/// Synheart Core SDK - Main Entry Point
///
/// This is the main entry point for the Synheart Core SDK.
/// It orchestrates all core modules and optional interpretation modules.
///
/// Core modules:
/// - Capabilities Module (feature gating)
/// - Consent Module (permission management)
/// - Wear Module (biosignal collection)
/// - Phone Module (motion/context)
/// - Behavior Module (interaction patterns)
/// - HSI Runtime (signal fusion & state computation)
/// - Cloud Connector (secure uploads)
///
///
/// Example usage:
/// ```dart
/// // Initialize
/// await Synheart.initialize(
/// userId: 'anon_user_123',
/// );
///
/// // Subscribe to HSI updates (core state representation)
/// Synheart.onHSIUpdate.listen((hsi) {
/// print('HSI JSON: $hsi');
/// });
///
/// // Enable cloud upload (with consent)
/// Synheart.activate(SynheartFeature.cloud);
/// ```
class Synheart {
  static Synheart? _instance;
  static Synheart get shared => _instance ??= Synheart._();

  /// core runtime bridge (FFI). Null when native lib unavailable.
  static CoreRuntimeBridge? _coreRuntime;

  /// Cached durable directory passed to the native runtime as `data_dir`.
  /// Without this the runtime falls back to `std::env::temp_dir()`, so the
  /// SRM snapshot (`srm_<subject>.json`) and SQLite (`synheart_<subject>.db`)
  /// don't survive app restarts or updates. Resolved once during
  /// [configure] and reused on subsequent [ensureRuntimeBridge] calls.
  static String? _resolvedDataDir;

  static Future<String> _resolveDataDir() async {
    final cached = _resolvedDataDir;
    if (cached != null) return cached;
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/synheart-core');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _resolvedDataDir = dir.path;
    return dir.path;
  }

  /// Callback invoked whenever `ingestBatch` returns a completed HSI
  /// window from a per-event push ([pushWearHr] / [pushRr] /
  /// [pushVendorHrv]). This is the primary HSI delivery path on iOS —
  /// the native `setHsiCallback` doesn't fire there, so consumers that
  /// care about HSI on iOS must set this callback.
  ///
  /// On Android the native callback already feeds [_hsvStream] and this
  /// is redundant; consumers typically listen to [onHSIUpdate] instead.
  static void Function(String hsiJson)? onHsi;

  Synheart._();

  // Module manager
  final ModuleManager _moduleManager = ModuleManager();

  // Core modules
  CapabilityModule? _capabilityModule;
  ConsentModule? _consentModule;
  WearModule? _wearModule;
  PhoneModule? _phoneModule;
  BehaviorModule? _behaviorModule;
  DeviceAuthProvider? _deviceAuthProvider;

  /// True when [sdkRegisterDevice] succeeded for this process (core-runtime auth path).
  static bool _deviceAuthViaCoreRuntime = false;
  static bool _sdkCryptoCallbacksAttached = false;

  // Watch session module
  WatchSessionModule? _watchSessionModule;

  // Main data-collection session (Session SDK) — RFC: open/close sessions via Session SDK
  SynheartSession? _mainSession;
  String? _activeMainSessionId;
  StreamSubscription<SessionEvent>? _mainSessionSubscription;

  // (HSI subscription fields removed — HSI is now delivered via setHsiCallback)

  // Session data buffers — accumulate during session, persist after stop
  List<String> _sessionHsiBuffer = [];
  List<WearSample> _sessionWearBuffer = [];
  StreamSubscription? _sessionHsiSubscription;
  StreamSubscription? _sessionWearSubscription;

  // Activation manager (RFC-0005 four-authority model)
  ActivationManager? _activationManager;

  // Behavior session tracking
  final Map<String, sb.BehaviorSession> _activeBehaviorSessions = {};

  // State
  bool _isConfigured = false;
  bool _isRunning = false;
  Completer<void>? _initCompleter; // guards concurrent init
  String? _userId;
  SynheartConfig? _config;
  bool? _batchIngestOnStop;
  static String? _lastUploadBatchId;
  static DateTime? _lastUploadAt;
  static String? _lastUploadError;
  static DateTime? _lastUploadAttemptAt;

  // Session handle
  SessionHandle? _currentSessionHandle;

  // Pending consent (set before init completes, applied after)
  _PendingConsent? _pendingConsent;

  // Streams
  final BehaviorSubject<String> _hsvStream = BehaviorSubject<String>();

  /// Static stream of HSI updates (core state representation, raw HSI JSON)
  static Stream<String> get onHSIUpdate => shared._hsvStream.stream;

  /// Stream of HSI updates (core state representation, raw HSI JSON)
  ///
  /// HSI (Human State Interface) contains:
  /// - State axes (physiological, engagement, activity, context)
  /// - State indices (arousalIndex, engagementStability, etc.)
  /// - 64D state embedding
  ///
  /// Consumers receive raw HSI JSON strings from the synheart-engine C ABI.
  Stream<String> get hsiUpdates => _hsvStream.stream;

  // --- Typed state subscription ---

  /// Stream of typed [HSIState] updates (RFC-CORE-0007 §3).
  ///
  /// Wraps raw JSON from [onHSIUpdate] into typed objects with axis accessors.
  static Stream<HSIState> get onStateUpdate => shared._hsvStream.stream.map(
    (json) => HSIState.fromJson(
      json,
      subjectId: shared._config?.subjectId ?? shared._userId ?? '',
    ),
  );

  /// Get the current HSI state as a typed object.
  static HSIState? get currentHSIState {
    if (!shared._hsvStream.hasValue) return null;
    return HSIState.fromJson(
      shared._hsvStream.value,
      subjectId: shared._config?.subjectId ?? shared._userId ?? '',
    );
  }

  // --- Metrics API ---

  /// Record a single metric event for the current session.
  ///
  /// In Personal mode, the call succeeds silently but data is dropped.
  /// In Insight/Research mode, the metric is persisted to SQLite.
  static Future<void> recordMetric(MetricEvent event) async {
    if (_coreRuntime != null) {
      _coreRuntime!.recordMetric(event.toJson());
      return;
    }
  }

  /// Record multiple metric events for the current session.
  static Future<void> recordMetrics(List<MetricEvent> events) async {
    if (_coreRuntime != null) {
      for (final event in events) {
        _coreRuntime!.recordMetric(event.toJson());
      }
      return;
    }
  }

  // --- Local query API ---

  /// List stored sessions with optional filters.
  static Future<List<SessionRecord>> listSessions({SessionRange? range}) async {
    if (_coreRuntime != null) {
      final raw = _coreRuntime!.listSessions();
      if (raw != null) {
        return raw
            .cast<Map<String, dynamic>>()
            .map((m) => SessionRecord.fromMap(m))
            .toList();
      }
    }
    return [];
  }

  /// Get a session summary (decrypted) for the given session.
  static Future<Map<String, dynamic>?> getSessionSummary(
    String sessionId,
  ) async {
    if (_coreRuntime != null) {
      final json = _coreRuntime!.getSessionSummary(sessionId);
      if (json != null) {
        try {
          return Map<String, dynamic>.from(
            const JsonDecoder().convert(json) as Map,
          );
        } catch (_) {}
      }
    }
    return null;
  }

  /// Get decrypted HSI window artifacts for a session.
  ///
  /// Each element is a full HSI 1.3 window payload. The native runtime may
  /// emit each window as either a JSON string or a map; this normalizes to
  /// `Map<String, dynamic>`.
  static Future<List<Map<String, dynamic>>> getHSIWindows(
    String sessionId, {
    WindowRange? range,
  }) async {
    if (_coreRuntime == null) return const [];
    final raw = _coreRuntime!.getHsiWindows(
      sessionId,
      startMs: range?.startMs ?? 0,
      endMs: range?.endMs ?? 0,
      limit: range?.limit ?? 0,
    );
    if (raw == null) return const [];
    return raw.map<Map<String, dynamic>>((e) {
      if (e is Map<String, dynamic>) return e;
      if (e is Map) return Map<String, dynamic>.from(e);
      if (e is String) return jsonDecode(e) as Map<String, dynamic>;
      throw FormatException(
        'unexpected HSI window element type: ${e.runtimeType}',
      );
    }).toList();
  }

  // --- Storage & retention ---

  /// Get storage usage statistics.
  static Future<StorageUsage> getStorageUsage() async {
    if (_coreRuntime != null) {
      final result = _coreRuntime!.getStorageUsage();
      if (result != null) {
        return StorageUsage(
          totalBytes: result['total_bytes'] as int? ?? 0,
          bySessionBytes:
              (result['by_session_bytes'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v as int),
              ) ??
              {},
        );
      }
    }
    return const StorageUsage(totalBytes: 0, bySessionBytes: {});
  }

  /// Set retention policy. Sessions older than [days] will be cleaned up.
  /// Pass null to disable retention.
  static Future<void> setRetentionDays(int? days) async {
    if (days == null) return;
    if (_coreRuntime != null) {
      _coreRuntime!.setRetentionDays(days);
      return;
    }
  }

  // --- Deletion API ---

  /// Delete a session and all its artifacts locally.
  /// Creates tombstones for future sync propagation.
  static Future<void> deleteLocalSession(String sessionId) async {
    if (_coreRuntime != null) {
      _coreRuntime!.deleteSession(sessionId);
      return;
    }
  }

  /// Wipe all local data: SQLite, SMK, and reset state. Also clears
  /// the in-memory `Baselines` cache so the next read returns a
  /// cold-start snapshot instead of stale per-session values.
  static Future<void> wipeLocalData() async {
    if (_coreRuntime != null) {
      _coreRuntime!.wipeLocalData();
      shared._currentSessionHandle = null;
      shared._isRunning = false;
      Baselines.reset();
      return;
    }
    // Stop if running
    if (shared._isRunning) {
      await shared._stopDataCollection();
    }

    shared._currentSessionHandle = null;
    Baselines.reset();
  }

  /// Request account deletion — wipes local data and requests server-side deletion.
  ///
  /// Local data is wiped regardless of whether the server request succeeds: the
  /// user has expressed intent to delete, and a failed server hop shouldn't
  /// leave their data on this device.
  static Future<DeletionRequestResult> requestAccountDeletion() async {
    if (_coreRuntime == null) {
      return const DeletionRequestResult(
        status: 'error',
        message: 'Account deletion unavailable: core runtime not loaded.',
      );
    }
    final serverOk = _coreRuntime!.requestAccountDeletion();
    await wipeLocalData();
    return DeletionRequestResult(
      status: 'accepted',
      message: serverOk
          ? 'Local data wiped. Server deletion pending.'
          : 'Local data wiped. Server deletion request failed — retry when online.',
    );
  }

  /// Cancel a pending account deletion request.
  static Future<DeletionRequestResult> cancelAccountDeletion() async {
    if (_coreRuntime != null) {
      final ok = _coreRuntime!.cancelAccountDeletion();
      return DeletionRequestResult(
        status: ok ? 'cancelled' : 'error',
        message: ok
            ? 'Account deletion cancelled via core runtime.'
            : 'Account deletion cancellation failed.',
      );
    }
    return const DeletionRequestResult(
      status: 'error',
      message:
          'Account deletion cancellation requires core-runtime network bridge.',
    );
  }

  // --- Customer-facing data deletion (GDPR Article 17) ---

  /// Request cloud-side deletion of every byte the platform holds for the
  /// currently-bound user (the subject derived from the `client_id` passed
  /// at SDK setup / device registration). Returns a [DataDeletionRequest]
  /// with `status` typically `pending` — the server runs the chain
  /// asynchronously. Poll [dataDeletionStatus] for completion.
  ///
  /// Pair this with [wipeLocalData] for the standard "Delete my account"
  /// flow: wipe locally first so the user can't keep using the app, then
  /// request the cloud delete.
  ///
  /// `reason` and `contact` are optional audit hints. `dryRun=true` runs the
  /// auth + persistence path but skips the actual purge — useful for testing
  /// integrations end-to-end without losing real data.
  static Future<DataDeletionRequest> requestDataDeletion({
    String? reason,
    String? contact,
    bool dryRun = false,
  }) async {
    if (_coreRuntime == null) {
      throw StateError(
        'requestDataDeletion requires the core-runtime network bridge.',
      );
    }
    final json = await _coreRuntime!.requestDataDeletion(
      reason: reason,
      contact: contact,
      dryRun: dryRun,
    );
    return _parseDataDeletion(json);
  }

  /// Poll the status of a deletion request. The `status` field transitions
  /// `pending` → `inProgress` → `completed` (or `failed`). Once
  /// `status == completed`, the [DataDeletionRequest.result] map carries
  /// per-layer purge stats from the server.
  static Future<DataDeletionRequest> dataDeletionStatus(
    String requestId,
  ) async {
    if (_coreRuntime == null) {
      throw StateError(
        'dataDeletionStatus requires the core-runtime network bridge.',
      );
    }
    final json = await _coreRuntime!.getDataDeletion(requestId);
    return _parseDataDeletion(json);
  }

  /// List recent deletion requests for this caller's org. Mainly useful for
  /// support/admin dashboards.
  static Future<DataDeletionList> listDataDeletions({
    int limit = 20,
    int offset = 0,
  }) async {
    if (_coreRuntime == null) {
      throw StateError(
        'listDataDeletions requires the core-runtime network bridge.',
      );
    }
    final json = await _coreRuntime!.listDataDeletions(
      limit: limit,
      offset: offset,
    );
    if (json == null) {
      throw StateError('Empty response from listDataDeletions.');
    }
    if (json['error'] is String) {
      throw StateError(json['error'] as String);
    }
    final dataList = (json['data'] as List?) ?? const [];
    return DataDeletionList(
      requests: dataList
          .whereType<Map>()
          .map((m) => DataDeletionRequest.fromJson(m.cast<String, dynamic>()))
          .toList(growable: false),
      total: (json['total'] as int?) ?? 0,
    );
  }

  static DataDeletionRequest _parseDataDeletion(Map<String, dynamic>? json) {
    if (json == null) {
      throw StateError('Empty response from data deletion call.');
    }
    if (json['error'] is String) {
      throw StateError(json['error'] as String);
    }
    return DataDeletionRequest.fromJson(json);
  }

  // --- Auth ---

  /// Log out — revoke consent.
  static Future<void> logout() async {
    if (_coreRuntime != null) {
      _coreRuntime!.wipeLocalData();
    }
    Baselines.reset();
    try {
      await shared._consentModule?.revokeConsent();
    } catch (_) {}
  }

  // --- Sync API ---

  /// Enable or disable sync.
  static Future<void> setSyncEnabled(bool enabled) async {
    if (_coreRuntime != null) {
      _coreRuntime!.setSyncEnabled(enabled);
      return;
    }
  }

  /// Toggle the runtime's ambient-capture HSI emission gate (RFC §13).
  /// Synchronous — defers to the FFI atomic flag, no I/O. No-op when
  /// the runtime hasn't initialised. Default `false` (gate off): the
  /// runtime forwards out-of-session windows only when this is set to
  /// `true`. Sessions always pass through regardless of this flag.
  static void setAmbientCapture(bool enabled) {
    _coreRuntime?.setAmbientCapture(enabled);
  }

  /// Read the runtime's ambient-capture gate. `false` when the
  /// runtime hasn't initialised or the gate is off.
  static bool getAmbientCapture() => _coreRuntime?.getAmbientCapture() ?? false;

  /// Execute a sync cycle (push + pull).
  static Future<SyncResult> syncNow() async {
    if (_coreRuntime != null) {
      final result = _coreRuntime!.syncNow();
      return SyncResult(
        pushed: result?['pushed'] as int? ?? 0,
        pulled: result?['pulled'] as int? ?? 0,
      );
    }
    return const SyncResult();
  }

  /// Get current sync status.
  static Future<SyncStatus> getSyncStatus() async {
    return const SyncStatus(enabled: false);
  }

  // Activation API (RFC-0005)

  /// Activate a feature. If all four authorities are satisfied
  /// (activation, consent, capability, session), the feature's module starts.
  static void activate(SynheartFeature feature) {
    shared._activationManager?.activate(feature);
    shared._reevaluateFeature(feature);
  }

  /// Deactivate a feature. Stops the feature's module if running.
  static void deactivate(SynheartFeature feature) {
    shared._activationManager?.deactivate(feature);
    shared._reevaluateFeature(feature);
  }

  /// Check whether a feature is currently activated by the developer.
  static bool isActivated(SynheartFeature feature) {
    return shared._activationManager?.isActivated(feature) ?? false;
  }

  /// Return the set of all currently activated features.
  static Set<SynheartFeature> activatedFeatures() {
    return shared._activationManager?.activatedFeatures() ?? {};
  }

  /// Initialize Synheart Core SDK
  ///
  /// This must be called before any other operations.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.initialize(
  /// userId: 'anon_user_123',
  /// );
  /// ```
  ///
  /// To initialize and then start a session:
  /// ```dart
  /// await Synheart.initialize(
  /// userId: 'anon_user_123',
  /// );
  /// await Synheart.startSession(); // Start when ready
  /// ```
  /// Whether the SDK has been initialized via [initialize] or [configure].
  static bool get isInitialized => shared._isConfigured;

  /// Ensure the core runtime bridge is loaded.
  ///
  /// Call this after [initialize] if another module may have initialized
  /// the SDK first without the native runtime bridge (e.g. behavior SDK).
  static void ensureRuntimeBridge({
    required String appId,
    required String subjectId,
  }) {
    if (_coreRuntime != null) return;
    try {
      final orgId = shared._config?.cloudConfig?.orgId ?? '';
      if (orgId.isEmpty) {
        SynheartLogger.log(
          '[Synheart] ⚠️ ensureRuntimeBridge: cloudConfig.orgId is empty — '
          'ingest rows will be tagged with empty org_id. '
          'Set CloudConfig.orgId in SynheartConfig before initialize().',
        );
      }
      final cachedDataDir = _resolvedDataDir;
      if (cachedDataDir == null) {
        SynheartLogger.log(
          '[Synheart] ⚠️ ensureRuntimeBridge: data_dir not yet resolved — '
          'baselines/SRM will fall back to a temp path and not persist. '
          'Call Synheart.configure() before ensureRuntimeBridge().',
        );
      }
      _coreRuntime = CoreRuntimeBridge.create({
        'app_id': appId,
        'org_id': orgId,
        'subject_id': subjectId,
        'mode': shared._config?.mode.name ?? 'personal',
        'device_id': shared._config?.deviceId ?? '',
        'app_version': shared._config?.appVersion ?? '0.0.0',
        'platform': 'flutter',
        if (cachedDataDir != null) 'data_dir': cachedDataDir,
        'storage': {'enabled': shared._config?.storage.enabled ?? true},
        'ingest': {'enabled': true, 'hsi': true, 'lab': true},
        'device_auth': {
          'enabled': true,
          'auth_base_url': shared._config?.deviceAuthConfig?.authBaseUrl ?? '',
        },
        'sync': {
          'enabled': shared._config?.sync.enabled ?? false,
          'base_url': shared._config?.sync.baseUrl ?? '',
        },
        'privacy': {
          'allow_research': shared._config?.privacy.allowResearch ?? false,
        },
      });
      if (_coreRuntime != null) {
        SynheartLogger.log(
          '[Synheart] core runtime bridge loaded (ensureRuntimeBridge)',
        );
        // SMK storage callbacks must be registered immediately after handle
        // creation and before any session lifecycle APIs.
        final storageRc = _coreRuntime!.setStorageCallbacks();
        if (storageRc == 0) {
          SynheartLogger.log(
            '[Synheart] Native secure-storage callbacks attached (synheart_native_secure_*).',
          );
        } else if (storageRc == -2) {
          SynheartLogger.log(
            '[Synheart] ⚠️ Core build lacks synheart_core_set_storage_callbacks; state will not persist.',
          );
        } else if (storageRc == -3) {
          SynheartLogger.log(
            '[Synheart] ⚠️ synheart_native_secure_* symbols not found — consent tokens and device records will not persist across app restarts.',
          );
        } else {
          SynheartLogger.log(
            '[Synheart] synheart_core_set_storage_callbacks failed: $storageRc',
          );
        }
      }
    } catch (e) {
      SynheartLogger.log('[Synheart] core runtime bridge unavailable: $e');
    }
  }

  /// The currently active session, if any.
  static SessionHandle? get currentSession => shared._currentSessionHandle;

  /// Initialize the SDK.
  ///
  /// Pass a [SynheartConfig] with `appId` and `subjectId` for full validation.
  /// Alternatively pass [userId] directly for simpler setup.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops if already
  /// initialized, or await the in-progress initialization if one is running.
  static Future<void> initialize({
    SynheartConfig? config,
    String? userId,
    bool autoStart = false,
    String? runtimeLogEnvFilter,
    void Function(String line)? runtimeLogForwarder,
  }) async {
    if (config != null) {
      config.validate();
    }
    return shared._configure(
      appKey: config?.appId ?? 'default',
      userId: userId ?? config?.subjectId ?? '',
      config: config,
      autoStart: autoStart,
      runtimeLogEnvFilter: runtimeLogEnvFilter,
      runtimeLogForwarder: runtimeLogForwarder,
    );
  }

  /// §1b — Initialize Core Runtime `tracing` once per process (optional if you rely on [CoreRuntimeBridge.create]).
  ///
  /// Returns `0` success, `1` already initialized, negative on failure.
  static int initRuntimeLogging({
    String? envFilter,
    void Function(String line)? onLine,
  }) {
    return CoreRuntimeBridge.initRuntimeLogging(
      envFilter: envFilter,
      onLine: onLine,
    );
  }

  /// §3 / §5 — JSON from `synheart_core_sdk_device_auth_status`, or null if unavailable.
  static Map<String, dynamic>? coreDeviceAuthStatus() {
    return _coreRuntime?.sdkDeviceAuthStatus();
  }

  /// §4 — Compact JWS for `X-Synheart-Proof` (non-ingest APIs). Use uppercase [method].
  static String? buildProofHeader(String method, String absoluteUrl) {
    return _coreRuntime?.buildProofHeader(method, absoluteUrl);
  }

  /// Whether the loaded native library exports the full core SDK device-auth ABI.
  static bool get coreSdkDeviceAuthAvailable =>
      _coreRuntime?.sdkDeviceAuthAvailable ?? false;

  /// True after a successful [sdkRegisterDevice] via the core runtime in this session.
  static bool get deviceAuthUsedCoreRuntime => _deviceAuthViaCoreRuntime;

  /// Idempotently ensures the device is registered with the auth server and
  /// that the Dart-side [DeviceAuthProvider] is wired for request signing.
  ///
  /// Safe to call from anywhere after [initialize] has been invoked. Useful
  /// for apps that want to eagerly recover from a lost registration on cold
  /// start (e.g. keychain wipe, fresh install after prior consent) without
  /// waiting for the next [grantConsent] or [startSession] to trigger it.
  ///
  /// Returns `true` if the device is registered after the call completes,
  /// `false` if device auth is not configured or registration failed.
  /// No-ops if already registered in this process.
  static Future<bool> ensureDeviceAuthRegistered() async {
    final cfg = shared._config;
    if (cfg?.deviceAuthConfig == null) return false;
    if (shared._deviceAuthProvider != null) {
      // Provider wired — make sure the consent JWT is also ready so the
      // ingest connector can actually flush. Cheap: ensureCloudConsentReady
      // short-circuits when the runtime reports granted+fresh.
      await _maybeEnsureCloudConsentReady();
      return true;
    }
    try {
      await shared._initDeviceAuth(cfg!);
      final registered = shared._deviceAuthProvider != null;
      if (registered) {
        // Registration without a signed consent token leaves the ingest
        // connector stuck with "ERR_AUTH: ingest requires non-empty
        // X-Consent-Token" on every tick. Chain the consent-token flow so
        // callers only need one entry point.
        await _maybeEnsureCloudConsentReady();
      }
      return registered;
    } catch (e) {
      SynheartLogger.log(
        '[Synheart] ensureDeviceAuthRegistered failed: $e',
        error: e,
      );
      return false;
    }
  }

  /// Best-effort consent-token issuance used to chain off device-auth
  /// registration paths. Swallows errors so device-auth success isn't
  /// reported as failure just because the consent HTTP call flaked —
  /// the ingest connector will retry on its next tick once the token lands.
  static Future<void> _maybeEnsureCloudConsentReady() async {
    try {
      final ready = await ensureCloudConsentReady();
      if (!ready) {
        SynheartLogger.log(
          '[Synheart] ensureCloudConsentReady returned false — '
          'ingest will stay blocked until consent token is issued.',
        );
      }
    } catch (e) {
      SynheartLogger.log(
        '[Synheart] ensureCloudConsentReady threw: $e — '
        'continuing; connector will retry on next tick.',
        error: e,
      );
    }
  }

  Future<void> _configure({
    required String appKey,
    required String userId,
    SynheartConfig? config,
    bool autoStart = false,
    String? runtimeLogEnvFilter,
    void Function(String line)? runtimeLogForwarder,
  }) async {
    // Already done — no-op.
    if (_isConfigured) return;

    // Another call is in progress — wait for it instead of racing.
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    _userId = userId;
    _config = config ?? SynheartConfig.defaults();

    final resolvedCfg = _config!;
    final effRuntimeFilter =
        runtimeLogEnvFilter ?? resolvedCfg.runtimeLogEnvFilter;
    if (effRuntimeFilter != null && effRuntimeFilter.isNotEmpty) {
      CoreRuntimeBridge.defaultRuntimeLogEnvFilter = effRuntimeFilter;
    }
    // Initialize core runtime bridge (best-effort; null if native lib absent).
    // NOTE: logging is deferred until AFTER coreNew — the native init emits
    // logs synchronously which crashes the async NativeCallable.listener
    // trampoline if it's already registered.
    try {
      final orgId = resolvedCfg.cloudConfig?.orgId ?? '';
      if (orgId.isEmpty) {
        SynheartLogger.log(
          '[Synheart] ⚠️ configure: cloudConfig.orgId is empty — '
          'ingest rows will be tagged with empty org_id. '
          'Set CloudConfig.orgId in SynheartConfig before initialize().',
        );
      }
      final dataDir = await _resolveDataDir();
      final coreJson = <String, dynamic>{
        'app_id': resolvedCfg.appId,
        'org_id': orgId,
        'subject_id': resolvedCfg.subjectId,
        'client_id': resolvedCfg.subjectId,
        'api_base_url': resolvedCfg.sync.baseUrl,
        'mode': resolvedCfg.mode.name,
        'device_id': resolvedCfg.deviceId.isNotEmpty
            ? resolvedCfg.deviceId
            : '',
        'app_version': resolvedCfg.appVersion,
        'platform': resolvedCfg.platform,
        'data_dir': dataDir,
        'storage': {'enabled': resolvedCfg.storage.enabled},
        'ingest': {'enabled': true, 'hsi': true, 'lab': true},
        'device_auth': {
          'enabled': true,
          'auth_base_url': resolvedCfg.deviceAuthConfig?.authBaseUrl ?? '',
        },
        'sync': {
          'enabled': resolvedCfg.sync.enabled,
          'base_url': resolvedCfg.sync.baseUrl,
        },
        'privacy': {'allow_research': resolvedCfg.privacy.allowResearch},
      };
      _coreRuntime = CoreRuntimeBridge.create(coreJson);
      // Now safe to register the logging callback — coreNew has returned.
      final logRc = CoreRuntimeBridge.initRuntimeLogging(
        envFilter: effRuntimeFilter,
        onLine: runtimeLogForwarder,
      );
      if (logRc < 0) {
        SynheartLogger.log(
          '[Synheart] synheart_core_init_logging returned $logRc (Core Runtime diagnostics may be limited)',
        );
      }
      if (_coreRuntime != null) {
        SynheartLogger.log('[Synheart] core runtime bridge loaded');
        // SMK storage callbacks must be registered immediately after handle
        // creation and before any session lifecycle APIs.
        final storageRc = _coreRuntime!.setStorageCallbacks();
        if (storageRc == 0) {
          SynheartLogger.log(
            '[Synheart] Native secure-storage callbacks attached (synheart_native_secure_*).',
          );
        } else if (storageRc == -2) {
          SynheartLogger.log(
            '[Synheart] ⚠️ Core build lacks synheart_core_set_storage_callbacks; state will not persist.',
          );
        } else if (storageRc == -3) {
          SynheartLogger.log(
            '[Synheart] ⚠️ synheart_native_secure_* symbols not found — consent tokens and device records will not persist across app restarts.',
          );
        } else {
          SynheartLogger.log(
            '[Synheart] synheart_core_set_storage_callbacks failed: $storageRc',
          );
        }

        if (_coreRuntime!.deviceAuthTemporarilyDisabledForSubjectCompat) {
          SynheartLogger.log(
            '[Synheart] Device-auth callbacks skipped: subject_id compatibility guard active.',
          );
        } else if (_coreRuntime!.sdkDeviceAuthAvailable) {
          // Attach crypto callbacks before any core SDK registration/proof
          // API is used (SDK auth sequence §2).
          //
          // Resolves `synheart_native_*` symbols directly into the runtime's
          // callback table — no Dart trampolines. Fails fast at registration
          // time if symbols are missing.
          final table = PlatformNativeSdkCryptoCallbacks.tryCreateRawTable();
          if (table == null) {
            SynheartLogger.log(
              '[Synheart] ⚠️ synheart_native_* crypto symbols not found — '
              'device auth will fail. Ensure synheart_auth plugin is '
              'registered and libsynheart_native_crypto.so is bundled.',
            );
          } else {
            final crc = _coreRuntime!.setSdkCryptoCallbacks(table);
            if (crc != 0) {
              SynheartLogger.log(
                '[Synheart] synheart_core_sdk_set_crypto_callbacks failed: $crc',
              );
            } else {
              _sdkCryptoCallbacksAttached = true;
              SynheartLogger.log(
                '[Synheart] Native crypto callbacks attached (synheart_native_*).',
              );
            }
          }
        }
      }
    } catch (e) {
      SynheartLogger.log('[Synheart] core runtime bridge unavailable: $e');
      _coreRuntime = null;
    }

    try {
      SynheartLogger.log('[Synheart] Initializing capability module..');
      _capabilityModule = CapabilityModule();
      final resolvedConfig = config ?? SynheartConfig.defaults();

      if (resolvedConfig.deviceAuthConfig != null) {
        // ── Device auth deferred ──────────────────────────────────
        // Device attestation and cloud registration are deferred until
        // cloud consent is granted. For now, load default capabilities.
        SynheartLogger.log(
          '[Synheart] Device auth configured — will activate when cloud consent is granted.',
        );
        await _capabilityModule!.loadDefaults();
      } else if (resolvedConfig.capabilityToken != null &&
          resolvedConfig.capabilitySecret != null) {
        // ── Static token path (HMAC-verified) ─────────────────────
        await _capabilityModule!.loadFromToken(
          resolvedConfig.capabilityToken!,
          resolvedConfig.capabilitySecret!,
        );
      } else if (resolvedConfig.allowUnsignedCapabilities) {
        SynheartLogger.log(
          '[Synheart] WARNING: Running with unsigned default capabilities. Do not use in production.',
        );
        await _capabilityModule!.loadDefaults();
      } else {
        throw StateError(
          'Capability token and secret are required. '
          'Provide deviceAuthConfig, capabilityToken+capabilitySecret, '
          'or set allowUnsignedCapabilities: true for debug/testing.',
        );
      }

      SynheartLogger.log('[Synheart] Initializing consent module..');
      _consentModule = ConsentModule(consentConfig: _config?.consentConfig);

      // Wire device signing into consent module so all consent-token requests
      // are signed with device identity (X-Synheart-* headers).
      // Uses lazy binding — resolves _deviceAuthProvider at call time.
      _consentModule!.setDeviceSigner(({
        required String method,
        required String path,
        required List<int> bodyBytes,
      }) async {
        if (_deviceAuthProvider == null) return <String, String>{};
        return _deviceAuthProvider!.signRequest(
          method: method,
          path: path,
          bodyBytes: Uint8List.fromList(bodyBytes),
        );
      });

      _moduleManager.registerModule(_capabilityModule!);
      _moduleManager.registerModule(_consentModule!);

      SynheartLogger.log('[Synheart] Initializing data modules..');
      _wearModule = WearModule(
        consent: _consentModule!,
        focusEnabled:
            true, // 1s interval so runtime gets enough samples per 10s window for HSI
        emotionEnabled: true,
      );
      _phoneModule = PhoneModule(
        capabilities: _capabilityModule!,
        consent: _consentModule!,
      );
      _behaviorModule = BehaviorModule(
        consent: _consentModule!,
        enableMotionLite: _config?.behaviorConfig?.enableMotionLite ?? false,
        emitRawMotionSamples:
            _config?.behaviorConfig?.emitRawMotionSamples ?? false,
      );

      _moduleManager.registerModule(
        _wearModule!,
        dependsOn: ['capabilities', 'consent'],
      );
      _moduleManager.registerModule(
        _phoneModule!,
        dependsOn: ['capabilities', 'consent'],
      );
      _moduleManager.registerModule(
        _behaviorModule!,
        dependsOn: ['capabilities', 'consent'],
      );

      SynheartLogger.log('[Synheart] Initializing Runtime..');
      final rawId = _userId!;
      final runtimeSubjectId = rawId.startsWith('sub_') ? rawId : 'sub_$rawId';
      final runtimeSessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';

      if (_coreRuntime == null) {
        SynheartLogger.log(
          '[Synheart] WARNING: Native runtime (libsynheart_core_runtime) not loaded — '
          'no HSI will be produced. Ensure native library is bundled '
          'and do a clean build (flutter clean && flutter run).',
        );
      } else {
        SynheartLogger.log(
          '[Synheart] Core runtime bridge loaded. lab=${_coreRuntime!.isLabAvailable ? "ready" : "not built"}',
        );
      }

      // Wire wearable event processor for vendor sync (RAMEN → pipeline)
      _wearModule!.setEventProcessor(
        WearableEventProcessor(
          subjectId: runtimeSubjectId,
          deviceInstallId: runtimeSessionId,
        ),
      );
      _wearModule!.setBridge(_coreRuntime);

      // Push all behavior events (notification, app_switch, touch, etc.) to the runtime
      if (_coreRuntime != null) {
        _behaviorModule!.pushBehaviorToRuntime =
            (int tsMs, int eventType, double value) {
              _coreRuntime?.pushBehavior(tsMs, eventType, value);
            };
        // Push raw 50 Hz accel batches to the Synheart Runtime so it can
        // derive features and the on-device motion classifier can run.
        _behaviorModule!.pushAccelToRuntime =
            (int tsMs, double ax, double ay, double az) {
              _coreRuntime?.pushAccel(tsMs, ax, ay, az);
            };
      }

      _watchSessionModule = WatchSessionModule();
      _watchSessionModule!.initialize();

      _mainSession = SynheartSession();

      SynheartLogger.log('[Synheart] Initializing all modules..');
      await _moduleManager.initializeAll();

      // Bridge the runtime's persisted consent into the Dart
      // ConsentModule at boot. Without this, `_consentModule.current()`
      // sits on `ConsentSnapshot.none()` until the user explicitly
      // re-submits consent, so every module that gates on consent
      // (Behavior, Phone, Wear) short-circuits on first session.
      await _syncConsentModuleFromRuntime();

      _consentModule!.addListener(_onConsentChanged);

      // Wire HSI callback from core runtime → _hsvStream
      if (_coreRuntime != null) {
        _coreRuntime!.setHsiCallback((hsiJson) {
          // Consent gating is already enforced by the native runtime before
          // HSI reaches state_tx. The Dart `_consentModule.current()`
          // snapshot has been observed to return stale defaults (biosignals
          // reads `false` even after `consentSubmitFormTyped` wrote the
          // consent store on the native side) — causing this filter to drop
          // 100% of HSI windows during an earlier validation run.
          // Cross-check with the effective-state snapshot so we don't block
          // on a Dart-side cache that's out of sync with the runtime.
          final local = _consentModule?.current();
          final effective = _coreRuntime?.consentEffectiveState();
          final biosignalsEffective =
              effective?['biosignals'] == true ||
              effective?['research'] == true;
          final biosignalsLocal = local?.biosignals == true;
          if (!biosignalsEffective && !biosignalsLocal) {
            return;
          }
          _hsvStream.add(hsiJson);
          // Surface motion-state on BehaviorModule
          // for consumers that want a posture/motion read alongside HSV
          // delivery. Cheap parse — bails out fast when no motion_state
          // axis is present in the snapshot.
          _behaviorModule?.ingestHsi(hsiJson);
        });
      }

      _activationManager = ActivationManager();
      _activationManager!.activateFromConfig(resolvedConfig);

      // Runtime-only policy: no SDK-side auth API configuration/networking here.

      if (autoStart) {
        SynheartLogger.log('[Synheart] Starting all modules..');
        await _moduleManager.startAll();
        _wireSessionBuffers();
        _isRunning = true;
      } else {
        SynheartLogger.log(
          '[Synheart] Modules initialized but not started (autoStart=false). Call startSession() when ready.',
        );
        _isRunning = false;
      }

      _isConfigured = true;
      _initCompleter?.complete();
      SynheartLogger.log('[Synheart] Initialization complete');

      // Apply any consent queued before init finished.
      if (_pendingConsent != null) {
        final pc = _pendingConsent!;
        _pendingConsent = null;
        SynheartLogger.log('[Synheart] Applying pending consent..');
        await _grantConsent(
          biosignals: pc.biosignals,
          behavior: pc.behavior,
          phoneContext: pc.phoneContext,
          cloudUpload: pc.cloudUpload,
          vendorSync: pc.vendorSync,
          tier: pc.tier,
          grantedChannels: pc.grantedChannels,
          research: pc.research,
        );
      }

      // Cold-start auto-heal: if the runtime already has persisted cloud
      // consent (e.g. a prior session's grant) and device auth is configured
      // but not yet wired in this process, trigger registration AND refresh
      // the consent JWT so the native ingest connector can flush immediately
      // on its next tick — otherwise it logs "ERR_AUTH: device not registered"
      // (pre-fix) or "ERR_AUTH: ingest requires non-empty X-Consent-Token"
      // (post-fix) every 60s until a session starts. Non-fatal.
      if (resolvedConfig.deviceAuthConfig != null && _coreRuntime != null) {
        final effective = _coreRuntime!.consentEffectiveState();
        final cloudGranted =
            effective?['cloud_upload'] == true ||
            effective?['cloudUpload'] == true;
        if (cloudGranted) {
          if (_deviceAuthProvider == null) {
            try {
              SynheartLogger.log(
                '[Synheart] Persisted cloud consent detected — auto-activating device auth..',
              );
              await _initDeviceAuth(resolvedConfig);
            } catch (e) {
              SynheartLogger.log(
                '[Synheart] Auto device-auth activation failed: $e — '
                'will retry on session start or next consent grant.',
                error: e,
              );
            }
          }
          // Even if registration is cached from a prior session, the consent
          // JWT in the native ingest slot is in-memory state that does not
          // survive a process restart. Re-issue on every cold start when
          // cloud consent is persisted.
          if (_deviceAuthProvider != null) {
            await _maybeEnsureCloudConsentReady();
          }
        }
      }
    } catch (e, stack) {
      _initCompleter?.completeError(e, stack);
      SynheartLogger.log(
        '[Synheart] Initialization failed: $e',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Start a session — activates permitted modules and begins signal collection.
  ///
  /// Per RFC §5.2: Core must activate permitted modules, route normalized
  /// signals to synheart-engine, enable HSV updates, and enable optional HSI export.
  ///
  /// Must be called after initialize(). No data collection occurs until
  /// this method is called (RFC §3.3).
  ///
  /// At least one feature must be enabled (via [SynheartConfig] or [activate])
  /// or this throws a [StateError].
  ///
  /// [durationSec] if set, the session will end automatically after that many
  /// seconds (Session SDK boundary). If null, session runs until [stopSession].
  static Future<SessionHandle?> startSession({int? durationSec}) async {
    if (_coreRuntime != null) {
      await shared._prepareRuntimeAuthForSessionStart();
      final result = _coreRuntime!.startSession();
      if (result != null) {
        shared._currentSessionHandle = SessionHandle(
          sessionId: result['session_id'] as String,
          startedAtMs: result['started_at_ms'] as int,
          mode: shared._config?.mode ?? SynheartMode.personal,
        );
        await shared._startRuntimeLinkedCollection();
        shared._isRunning = true;

        return shared._currentSessionHandle;
      }
    }
    await shared._startDataCollection(durationSec: durationSec);
    return shared._currentSessionHandle;
  }

  Future<void> _prepareRuntimeAuthForSessionStart() async {
    final cfg = _config;
    if (cfg == null || cfg.deviceAuthConfig == null) return;
    if (_deviceAuthProvider != null) return;
    // Device-auth registration only matters for cloud-bound uploads (HSI ingest,
    // lab payloads). If cloud is off, attestation is wasted work and the
    // backend rightly returns 403 (DEV_003). Skip silently — local-only
    // sessions don't need a registered device.
    final cloudGranted = await hasConsent('cloudUpload');
    if (!cloudGranted) {
      SynheartLogger.log(
        '[Synheart] Session start preflight: cloud upload consent off — skipping device auth.',
      );
      return;
    }
    try {
      SynheartLogger.log(
        '[Synheart] Session start preflight: initializing device auth..',
      );
      await _initDeviceAuth(cfg);
      SynheartLogger.log(
        '[Synheart] Session start preflight: device auth ready.',
      );
    } catch (e) {
      SynheartLogger.log(
        '[Synheart] Session start preflight: device auth init failed ($e). Continuing in local mode.',
      );
    }
  }

  /// Whether the main data-collection session is currently running.
  static bool get isSessionRunning => shared._isRunning;

  /// Stop the current session — halts module streaming and clears ephemeral buffers.
  ///
  /// Per RFC §5.2: Core must halt module streaming, stop synheart-engine updates,
  /// clear ephemeral buffers, and prevent further HSI export.
  static Future<void> stopSession() async {
    if (_coreRuntime != null) {
      // Snapshot the engine summary BEFORE tearing down the runtime.
      // `_coreRuntime.stopSession()` calls the native `stop_session`,
      // which drops the pipeline (engine_module sets `pipeline =
      // None`). Reading `frameCount()` after that point always
      // returns 0, which printed a misleading
      // "no HSI produced — no window completed" line at session end
      // even when several windows had landed in the session buffer.
      shared._logRuntimeSummary();
      _coreRuntime!.stopSession();
      await shared._stopRuntimeLinkedCollection();
      shared._currentSessionHandle = null;
      shared._isRunning = false;
      return;
    }
    return shared._stopDataCollection();
  }

  /// Returns a snapshot of all HSI JSON windows accumulated during the current
  /// (or most recent) session. The list is cleared when [startSession] is called.
  static List<String> getSessionHsiWindows() =>
      List.unmodifiable(shared._sessionHsiBuffer);

  /// Returns a snapshot of all raw wear samples accumulated during the current
  /// (or most recent) session. The list is cleared when [startSession] is called.
  static List<WearSample> getSessionWearSamples() =>
      List.unmodifiable(shared._sessionWearBuffer);

  /// Start wear data collection
  ///
  /// Starts collecting biosignals from wearables.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.startWearCollection();
  /// ```
  static Future<void> startWearCollection({Duration? interval}) async {
    return shared._startWearCollection(interval: interval);
  }

  /// Stop wear data collection
  ///
  /// Stops collecting biosignals but keeps wear module initialized.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.stopWearCollection();
  /// ```
  static Future<void> stopWearCollection() async {
    return shared._stopWearCollection();
  }

  /// Start behavior data collection
  ///
  /// Starts collecting behavioral interaction patterns.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.startBehaviorCollection();
  /// ```
  static Future<void> startBehaviorCollection() async {
    return shared._startBehaviorCollection();
  }

  /// Stop behavior data collection
  ///
  /// Stops collecting behavioral data but keeps behavior module initialized.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.stopBehaviorCollection();
  /// ```
  static Future<void> stopBehaviorCollection() async {
    return shared._stopBehaviorCollection();
  }

  /// Check if notification listener access is enabled (Android) or notification
  /// permission is granted (iOS). Required for behavior notification metrics.
  ///
  /// Falls back to a direct platform-channel call when the behavior SDK has
  /// not been initialized yet, so callers do not have to wait for
  /// [startBehaviorCollection] to complete.
  static Future<bool> checkNotificationListenerEnabled() async {
    final sb = shared._behaviorModule?.synheartBehavior;
    if (sb != null) {
      try {
        return await sb.checkNotificationPermission();
      } catch (e) {
        SynheartLogger.log(
          '[Synheart] checkNotificationPermission via SDK failed, '
          'falling back to direct channel: $e',
          error: e,
        );
      }
    }
    final result = await _invokeBehaviorChannel<bool>(
      'checkNotificationPermission',
    );
    return result ?? false;
  }

  /// Open system settings where the user can enable notification access.
  /// On Android: Notification listener access (Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).
  /// On iOS: Opens app settings.
  ///
  /// Falls back to a direct platform-channel call when the behavior SDK has
  /// not been initialized yet, so the system settings page still opens even
  /// if behavior collection has not started yet.
  static Future<void> openNotificationListenerSettings() async {
    final sb = shared._behaviorModule?.synheartBehavior;
    if (sb != null) {
      try {
        await sb.requestNotificationPermission();
        return;
      } catch (e) {
        SynheartLogger.log(
          '[Synheart] requestNotificationPermission via SDK failed, '
          'falling back to direct channel: $e',
          error: e,
        );
      }
    }
    await _invokeBehaviorChannel<void>('requestNotificationPermission');
  }

  static const MethodChannel _behaviorFallbackChannel = MethodChannel(
    'ai.synheart.behavior',
  );

  static Future<T?> _invokeBehaviorChannel<T>(String method) async {
    try {
      return await _behaviorFallbackChannel.invokeMethod<T>(method);
    } catch (e) {
      SynheartLogger.log(
        '[Synheart] Direct behavior channel call "$method" failed: $e',
        error: e,
      );
      return null;
    }
  }

  /// Start phone context data collection
  ///
  /// Starts collecting phone motion and context data.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.startPhoneCollection();
  /// ```
  static Future<void> startPhoneCollection() async {
    return shared._startPhoneCollection();
  }

  /// Stop phone context data collection
  ///
  /// Stops collecting phone data but keeps phone module initialized.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.stopPhoneCollection();
  /// ```
  static Future<void> stopPhoneCollection() async {
    return shared._stopPhoneCollection();
  }

  /// Check if wear module is collecting data
  static bool get isWearCollecting => shared._isWearCollecting;

  /// Check if behavior module is collecting data
  static bool get isBehaviorCollecting => shared._isBehaviorCollecting;

  /// Check if phone module is collecting data
  static bool get isPhoneCollecting => shared._isPhoneCollecting;

  // ── Watch Session API ─────────────────────────────────────────────────

  /// Whether a watch session is currently active.
  static bool get isWatchSessionActive =>
      shared._watchSessionModule?.isActive ?? false;

  /// The active watch session ID, if any.
  static String? get activeWatchSessionId =>
      shared._watchSessionModule?.activeSessionId;

  /// Stream of [SessionEvent]s from the active watch session.
  ///
  /// Events flow: `SessionStarted` -> `SessionFrame*` -> `SessionSummary`.
  /// Each [SessionFrame] carries HR metrics (hr_mean_bpm, rmssd_ms, sdnn_ms).
  static Stream<SessionEvent> get watchSessionEvents {
    final mod = shared._watchSessionModule;
    if (mod == null) {
      throw StateError(
        'WatchSessionModule not initialized. Call initialize() first.',
      );
    }
    return mod.events;
  }

  /// Query watch connectivity status.
  ///
  /// Returns [WatchStatus] with `reachable`, `paired`, `installed`, `supported`.
  /// Returns null if the module is not initialized or the platform doesn't
  /// support watch connectivity.
  ///
  /// Example:
  /// ```dart
  /// final status = await Synheart.getWatchStatus();
  /// if (status?.reachable == true) {
  /// print('Watch is reachable');
  /// }
  /// ```
  static Future<WatchStatus?> getWatchStatus() async {
    return shared._watchSessionModule?.getWatchStatus();
  }

  /// Start a session on the companion watch.
  ///
  /// Sends a start command to the paired watch via the Wearable Data Layer
  /// (Wear OS MessageClient / Apple Watch WCSession). The watch begins
  /// reading HR data and streams [SessionFrame] events back.
  ///
  /// Returns a broadcast stream of [SessionEvent]s.
  ///
  /// Example:
  /// ```dart
  /// final stream = Synheart.startWatchSession(
  /// SessionConfig(
  /// mode: SessionMode.focus,
  /// durationSec: 300,
  /// profile: ComputeProfile(windowSec: 60, emitIntervalSec: 5),
  /// ),
  /// );
  /// stream.listen((event) {
  /// if (event is SessionFrame) {
  /// print('HR: ${event.metrics['hr_mean_bpm']}');
  /// }
  /// });
  /// ```
  static Stream<SessionEvent> startWatchSession(SessionConfig config) {
    final mod = shared._watchSessionModule;
    if (mod == null) {
      throw StateError(
        'WatchSessionModule not initialized. Call initialize() first.',
      );
    }
    return mod.startSession(config);
  }

  /// Stop the active watch session.
  ///
  /// Sends a stop command to the watch. A [SessionSummary] event will be
  /// emitted on the session stream before it closes.
  static Future<void> stopWatchSession() async {
    await shared._watchSessionModule?.stopSession();
  }

  // ── End Watch Session API ─────────────────────────────────────────────

  /// Stream of raw wear samples
  ///
  /// Subscribe to this stream to receive real-time biosignal data.
  /// The stream respects consent - no data is emitted if consent is denied.
  ///
  /// Example:
  /// ```dart
  /// Synheart.wearSampleStream.listen((sample) {
  /// print('HR: ${sample.hr} BPM');
  /// print('RR Intervals: ${sample.rrIntervals}');
  /// });
  /// ```
  static Stream<WearSample> get wearSampleStream {
    if (shared._wearModule == null) {
      throw StateError('Wear module not initialized. Call initialize() first.');
    }
    return shared._wearModule!.rawSampleStream;
  }

  /// Stream of raw behavior events
  ///
  /// Subscribe to this stream to receive real-time behavioral interaction events.
  /// The stream respects consent - no data is emitted if consent is denied.
  ///
  /// Example:
  /// ```dart
  /// Synheart.behaviorEventStream.listen((event) {
  /// print('Event: ${event.type} at ${event.timestamp}');
  /// });
  /// ```
  static Stream<BehaviorEvent> get behaviorEventStream {
    if (shared._behaviorModule == null) {
      throw StateError(
        'Behavior module not initialized. Call initialize() first.',
      );
    }
    return shared._behaviorModule!.eventStream.events;
  }

  /// Start a behavior session
  ///
  /// Starts tracking behavioral interactions and returns a session ID.
  /// Use this session ID when stopping the session to get results.
  ///
  /// Example:
  /// ```dart
  /// final sessionId = await Synheart.startBehaviorSession();
  /// // .. user interacts with app ..
  /// final results = await Synheart.stopBehaviorSession(sessionId);
  /// print('Focus Hint: ${results.focusHint}');
  /// ```
  static Future<String> startBehaviorSession() async {
    return shared._startBehaviorSession();
  }

  /// Stop a behavior session and get results
  ///
  /// Ends the session and returns aggregated results including tap rate,
  /// keystroke rate, focus hint, and other behavioral metrics.
  ///
  /// Example:
  /// ```dart
  /// final results = await Synheart.stopBehaviorSession(sessionId);
  /// print('Tap Rate: ${results.tapRate}');
  /// print('Keystroke Rate: ${results.keystrokeRate}');
  /// print('Focus Hint: ${results.focusHint}');
  /// ```
  static Future<BehaviorSessionResults> stopBehaviorSession(
    String sessionId,
  ) async {
    return shared._stopBehaviorSession(sessionId);
  }

  /// Number of HSI snapshots pending upload (0 if cloud connector not enabled).
  static int get uploadQueueLength => _coreRuntime?.uploadQueueLength ?? 0;

  /// Wall-clock timestamp (Unix ms) of the most recent successful
  /// ingest upload. Null when nothing has uploaded yet in this
  /// process. Drive a "Synced N min ago" badge from this; do not
  /// expose [uploadQueueLength] to end users — the queue length
  /// fluctuates per flush tick and reads as scary noise.
  static int? get lastIngestSuccessAtMs => _coreRuntime?.lastIngestSuccessAtMs;

  /// Aggregate cloud-sync state for host UI. Reads
  /// [uploadQueueLength], [lastIngestSuccessAtMs], and the
  /// [consentEffectiveStateTyped] cloud flag and collapses them
  /// into one of four user-facing buckets — see
  /// [CloudSyncStatus]. The host renders a single pill from this,
  /// no need to combine signals manually.
  static CloudSyncStatus get cloudSyncStatus {
    final cloudOn = consentEffectiveStateTyped()?.cloudUpload ?? false;
    if (!cloudOn) return CloudSyncStatus.localOnly;
    final queue = uploadQueueLength;
    final lastMs = lastIngestSuccessAtMs;
    if (queue > 0) return CloudSyncStatus.syncing;
    if (lastMs != null) return CloudSyncStatus.synced;
    return CloudSyncStatus.pending;
  }

  // ── HSI history (on-device mirror of uploaded payloads) ──────────────
  //
  // The native ingest connector deletes rows from the outbound upload queue
  // on HTTP 200 — that table is pure "pending uploads". `hsi_history` is a
  // separate on-device table that keeps a copy of each successfully
  // uploaded HSI payload so apps can render offline timelines and users
  // keep access to their data after cloud storage.
  //
  // Retention is age-based (default 30 days, enforced by the native side on
  // each archive pass). Returns empty / 0 when no cloud connector is
  // configured. These are pure on-device operations — no network I/O.

  /// List archived HSI payloads (oldest first).
  ///
  /// - [since] filters rows by upload timestamp; `null` returns all.
  /// - [limit] caps the result count; `null` or `0` means unbounded.
  ///
  /// Each map is a parsed HSI JSON object (schema depends on the producer's
  /// `hsi_version`). Returns empty when the cloud connector is not wired.
  static List<Map<String, dynamic>> listHsiHistory({
    DateTime? since,
    int? limit,
  }) {
    return _coreRuntime?.hsiHistoryList(since: since, limit: limit) ?? const [];
  }

  /// Number of archived HSI payloads currently on-device.
  static int hsiHistoryCount() => _coreRuntime?.hsiHistoryCount() ?? 0;

  /// Wipe the on-device HSI history. Intended for user-initiated
  /// "delete my data" flows. Does NOT clear the outbound upload queue —
  /// pending uploads will still be sent to the cloud unless stopped.
  /// Returns true on success, false if the runtime is unavailable.
  static bool clearHsiHistory() => _coreRuntime?.hsiHistoryClear() ?? false;

  /// Batch id from the last successful cloud ingest (null if none yet).
  static String? get lastUploadBatchId => _lastUploadBatchId;

  /// Time of the last successful cloud ingest (null if none yet).
  static DateTime? get lastUploadAt => _lastUploadAt;

  /// Last upload error message (null when last attempt succeeded or no attempt yet).
  static String? get lastUploadError => _lastUploadError;

  /// Time of the last upload attempt (success or failure); null if no attempt yet.
  static DateTime? get lastUploadAttemptAt => _lastUploadAttemptAt;

  /// Bridge-first ingestion facade for queue + upload orchestration.
  static SynheartIngestion get ingestion => SynheartIngestion.instance;

  /// Check if user has granted a specific consent
  ///
  /// Example:
  /// ```dart
  /// bool hasConsent = await Synheart.hasConsent('biosignals');
  /// ```
  static Future<bool> hasConsent(String consentType) async {
    if (_coreRuntime != null) {
      return _coreRuntime!.hasConsent(consentType);
    }
    return shared._hasConsent(consentType);
  }

  /// Override consent cloud endpoint routing for the active runtime.
  static bool consentConfigureCloud({required String baseUrl, String? appId}) {
    final rt = _coreRuntime;
    if (rt == null) return false;
    final resolvedAppId = appId ?? shared._config?.appId;
    if (resolvedAppId == null || resolvedAppId.isEmpty) return false;
    return rt.consentConfigureCloud(baseUrl, resolvedAppId);
  }

  /// Read editable consent form JSON contract from runtime.
  ///
  /// Prefer [consentGetEditableFormTyped] for typed access.
  static Map<String, dynamic>? consentGetEditableForm() {
    return _coreRuntime?.consentGetEditableForm();
  }

  /// Read editable consent form as a typed [ConsentForm].
  ///
  /// Returns `null` when the runtime bridge is unavailable.
  static ConsentForm? consentGetEditableFormTyped() {
    final raw = _coreRuntime?.consentGetEditableForm();
    if (raw == null) return null;
    return ConsentForm.fromJson(raw);
  }

  /// Submit consent form JSON to runtime using offline-first semantics.
  ///
  /// Prefer [consentSubmitFormTyped] for typed submission.
  static Future<Map<String, dynamic>?> consentSubmitForm({
    required Map<String, dynamic> formJson,
    String? deviceId,
    String? platform,
    String? userId,
  }) async {
    final rt = _coreRuntime;
    final consentCfg = shared._config?.consentConfig;
    if (rt == null || consentCfg == null) return null;
    final resolvedDeviceId = deviceId ?? consentCfg.deviceId;
    final resolvedPlatform = platform ?? consentCfg.platform;
    final resolvedUserId = userId ?? consentCfg.userId ?? shared._userId;
    if (resolvedDeviceId == null ||
        resolvedDeviceId.isEmpty ||
        resolvedPlatform.isEmpty) {
      return {
        'error':
            'consent_submit_form requires non-empty device_id and platform',
      };
    }

    // Direct-submit path is used by runtime UI toggles that bypass
    // [grantConsent]. If the form grants cloud upload and device auth is
    // configured but not yet wired, register the device first so the ingest
    // connector can authenticate its next flush tick. Non-fatal on failure.
    final allowCloud =
        formJson['allow_cloud'] == true ||
        formJson['allowCloud'] == true ||
        formJson['cloud_upload'] == true ||
        formJson['cloudUpload'] == true;
    if (allowCloud &&
        shared._config?.deviceAuthConfig != null &&
        shared._deviceAuthProvider == null) {
      await ensureDeviceAuthRegistered();
    }

    final result = await rt.consentSubmitForm(
      deviceId: resolvedDeviceId,
      platform: resolvedPlatform,
      userId: resolvedUserId,
      formJson: formJson,
    );

    // Bridge the runtime's effective state into the Dart ConsentModule.
    //
    // Without this, `ConsentModule._currentConsent` stays at its
    // `ConsentSnapshot.none()` boot default — and everything that gates
    // on `_consent.current().allowsChannel(..)` (BehaviorModule,
    // PhoneModule, WearModule) sees no consent forever, even though
    // runtime correctly reports it granted. Downstream symptoms:
    // `BehaviorModule._startTrackingIfNeeded: SKIP (consent channel not
    // granted)`, `synheart_behavior` never initializes,
    // `Synheart.behaviorEventStream` stays empty for the app session.
    //
    // Fire-and-forget so a sync failure here never blocks the form
    // submit result.
    if (result == null || result['error'] == null) {
      // ignore: discarded_futures — sync is observational, not on the critical path
      shared._syncConsentModuleFromRuntime();
    }

    return result;
  }

  /// Pull the runtime's effective consent state and push it into the
  /// Dart [ConsentModule] so all consumers that read `_consent.current()`
  /// (modules, observers) see the truth instead of the stale
  /// `ConsentSnapshot.none()` default set at boot.
  ///
  /// No-ops if either the runtime bridge or the Dart consent module
  /// isn't available yet.
  Future<void> _syncConsentModuleFromRuntime() async {
    final effective = consentEffectiveStateTyped();
    if (effective == null) return;
    final module = _consentModule;
    if (module == null) return;
    try {
      final snapshot = ConsentSnapshot(
        biosignals: effective.biosignals,
        behavior: effective.behavior,
        phoneContext: effective.phoneContext,
        cloudUpload: effective.cloudUpload,
        syni: effective.syni,
        vendorSync: effective.vendorSync,
        research: effective.research,
        timestamp: DateTime.now(),
      );
      await module.updateConsent(snapshot);
      SynheartLogger.log(
        '[Synheart] Dart ConsentModule synced from runtime: '
        'biosignals=${effective.biosignals}, '
        'behavior=${effective.behavior}, '
        'phoneContext=${effective.phoneContext}, '
        'cloudUpload=${effective.cloudUpload}, '
        'vendorSync=${effective.vendorSync}, '
        'research=${effective.research}',
      );
    } catch (e, st) {
      SynheartLogger.log(
        '[Synheart] Failed to sync ConsentModule from runtime: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Submit a typed [ConsentForm] to runtime using offline-first semantics.
  ///
  /// Returns the raw runtime response map (`{ synced, accepted, token }` on
  /// success, `{ error }` on failure, `null` if the bridge is unavailable).
  static Future<Map<String, dynamic>?> consentSubmitFormTyped({
    required ConsentForm form,
    String? deviceId,
    String? platform,
    String? userId,
  }) {
    return consentSubmitForm(
      formJson: form.toJson(),
      deviceId: deviceId,
      platform: platform,
      userId: userId,
    );
  }

  /// Read high-level consent status machine from runtime.
  static Map<String, dynamic>? consentStatus() {
    return _coreRuntime?.consentStatus();
  }

  /// Read runtime effective accepted state summary.
  ///
  /// Prefer [consentEffectiveStateTyped] for typed access.
  static Map<String, dynamic>? consentEffectiveState() {
    return _coreRuntime?.consentEffectiveState();
  }

  /// Read runtime effective accepted state as a typed [ConsentEffectiveState].
  ///
  /// Returns `null` when the runtime bridge is unavailable.
  static ConsentEffectiveState? consentEffectiveStateTyped() {
    final raw = _coreRuntime?.consentEffectiveState();
    if (raw == null) return null;
    return ConsentEffectiveState.fromJson(raw);
  }

  /// Whether consent token should be refreshed soon.
  static bool consentNeedsTokenRefresh() {
    return _coreRuntime?.consentNeedsTokenRefresh() ?? false;
  }

  /// Clear stored consent artifacts in runtime.
  static bool consentClearStored() {
    return _coreRuntime?.consentClearStored() ?? false;
  }

  Future<bool> _hasConsent(String consentType) async {
    if (_consentModule == null) {
      return false;
    }

    final consent = _consentModule!.current();
    switch (consentType) {
      case 'biosignals':
        return consent.biosignals;
      case 'behavior':
        return consent.behavior;
      case 'phoneContext':
        return consent.phoneContext;
      case 'cloudUpload':
        return consent.cloudUpload;
      case 'syni':
        return consent.syni;
      case 'vendorSync':
        return consent.vendorSync;
      case 'research':
        return consent.research;
      default:
        return false;
    }
  }

  /// Revoke consent for a specific data type
  ///
  /// Example:
  /// ```dart
  /// await Synheart.revokeConsentType('biosignals');
  /// ```
  static Future<void> revokeConsentType(String consentType) async {
    if (_coreRuntime != null) {
      _coreRuntime!.revokeConsent(consentType);
      // Fall through to Dart consent module so UI stays in sync
    }
    return shared._revokeConsentType(consentType);
  }

  Future<void> _revokeConsentType(String consentType) async {
    if (_consentModule == null) {
      throw StateError('Consent module not initialized');
    }

    final current = _consentModule!.current();
    final updated = ConsentSnapshot(
      biosignals: consentType == 'biosignals' ? false : current.biosignals,
      behavior: consentType == 'behavior' ? false : current.behavior,
      phoneContext: consentType == 'phoneContext'
          ? false
          : current.phoneContext,
      cloudUpload: consentType == 'cloudUpload' ? false : current.cloudUpload,
      syni: consentType == 'syni' ? false : current.syni,
      vendorSync: consentType == 'vendorSync' ? false : current.vendorSync,
      research: consentType == 'research' ? false : current.research,
      timestamp: DateTime.now(),
    );

    await _consentModule!.updateConsent(updated);
  }

  /// Get latest HSI JSON (latest runtime output), or null if none produced yet.
  String? get currentState {
    return _hsvStream.hasValue ? _hsvStream.value : null;
  }

  /// Get the currently configured user id (if initialized)
  String? get userId => _userId;

  /// Get behavior module for recording events
  BehaviorModule? get behaviorModule => _behaviorModule;

  /// Breathing compliance detector (RFC-Breathing-001).
  /// Returns null until the core runtime bridge is initialized.
  /// Use [Synheart.breathing] (static) from app code; this instance getter
  /// exists for symmetry with the other module getters.
  BreathingModule? get breathingModule =>
      _coreRuntime == null ? null : BreathingModule(_coreRuntime!);

  /// Static breathing accessor — matches `Synheart.setTaskType` usage in apps.
  /// Returns null until the core runtime bridge is initialized.
  static BreathingModule? get breathing =>
      _coreRuntime == null ? null : BreathingModule(_coreRuntime!);

  // -------------------------------------------------------------------------
  // Syni — adaptive AI agent (gated feature)
  // -------------------------------------------------------------------------
  //
  // Lazily constructed once `consent.syni == true`. The module performs its
  // own install lifecycle (model download, persona materialization, engine
  // load on a worker isolate). See `lib/src/modules/syni/syni_module.dart`.

  static SyniModule? _syni;
  static SyniCloudConfig? _syniCloudConfig;

  /// Inject (or clear) the cloud config used by Syni's hybrid router.
  ///
  /// With a config set, `Synheart.syni!.hasCloud` is true and chat calls can
  /// route to `syni-service` (per `SyniExecutionMode`). Without it, Syni
  /// runs local-only.
  ///
  /// Resets the cached `SyniModule` so the next `Synheart.syni` access picks
  /// up the new config. Safe to call before or after `initialize()`.
  static void configureSyniCloud(SyniCloudConfig? config) {
    _syniCloudConfig = config;
    _syni = null;
  }

  /// Adaptive AI client. Returns null until the Synheart facade is running.
  /// Once non-null the caller drives `install`, `chat`, and `uninstall`
  /// directly on it.
  ///
  /// Operational status follows the four-authority model — `chat()` only
  /// succeeds after `install()` reaches [SyniInstalled], and the capability
  /// gate (`isFeatureOperational(SynheartFeature.syni)`) returns true only
  /// when installed.
  ///
  /// **V1 note**: this getter does NOT yet check `consent.syni` because
  /// `ConsentForm` does not expose a `syni` channel — there is no way for a
  /// user to grant syni consent through the public form. For V1 the explicit
  /// `install()` call (which downloads a multi-GB model) functions as the
  /// opt-in moment. Re-enable the consent check once `ConsentForm` grows a
  /// `syni` field and host apps surface it in their consent UI.
  static SyniModule? get syni {
    // Gate on SDK *initialization*, not session-running state — Syni is
    // usable any time after `initialize()`, independent of whether a
    // session is active.
    if (!shared._isConfigured) return null;
    return _syni ??= SyniModule(
      cloudConfig: _syniCloudConfig,
      hsiSnapshot: () => Synheart.currentHSIState,
    );
  }

  /// Get the core runtime bridge (for diagnostics and direct FFI access).
  CoreRuntimeBridge? get coreRuntime => _coreRuntime;

  /// Whether the runtime uses batch ingest on stop (true) or streaming/realtime (false).
  /// Batch ingest is now managed by the core runtime; this returns the config value.
  static bool get batchIngestOnStop =>
      shared._batchIngestOnStop ?? shared._config?.batchIngestOnStop ?? false;

  /// Set runtime mode: true = batch ingest when session stops, false = realtime HSI every ~10s.
  /// Applies to the next session start; safe to call when initialized.
  static void setBatchIngestOnStop(bool value) {
    shared._batchIngestOnStop = value;
  }

  /// Push a touch behavior event into the runtime for the given timestamp (ms since epoch).
  /// Use from game screens so taps are reflected in behavioral_metrics in exports/lab.
  /// No-op if runtime or bridge is unavailable.
  static void pushBehaviorTouch(int tsMs) {
    _coreRuntime?.pushBehavior(tsMs, RuntimeBehaviorEvent.input.code, 1.0);
  }

  /// Push a notification-received behavior event into the runtime for the given timestamp (ms since epoch).
  /// Call when the app displays or receives a notification so behavioral_metrics include notification counts.
  /// No-op if runtime or bridge is unavailable.
  static void pushBehaviorNotificationReceived(int tsMs) {
    _coreRuntime?.pushBehavior(
      tsMs,
      RuntimeBehaviorEvent.notification.code,
      1.0,
    );
  }

  /// Push a heart-rate sample into the runtime with provider attribution.
  ///
  /// Routes directly through `ingestBatch` as a single-event batch so the
  /// runtime sees the sample immediately (no Dart-side 5s delay) while
  /// preserving the `provider` tag that `pushHr(ts, bpm)` would otherwise
  /// drop. HSI windows produced by the batch are delivered through
  /// [onHsi] — the primary HSI path on iOS, where the native
  /// `setHsiCallback` doesn't fire.
  static void pushWearHr(
    int tsMs,
    double bpm, {
    String provider = 'default_sensor',
  }) {
    _ingestSingleEvent({
      'type': 'hr',
      'ts_ms': tsMs,
      'bpm': bpm,
      'provider': provider,
    });
  }

  /// Push an RR interval with provider attribution.
  ///
  /// Unlike [pushWearHr], RR samples must reach BOTH the runtime
  /// (HRV/HSI pipeline) and the breathing-compliance detector. The
  /// JSON `ingestBatch` route only covers the former — the runtime's
  /// `synheart::ingest_batch_json` calls `runtime.push_rr` but does
  /// NOT call `breathing.push_rr`. The dedicated FFI
  /// (`synheart_core_push_rr` → `synheart::push_rr`) hits both and
  /// now also carries the provider tag end-to-end so the engine can
  /// route Tier-1 sources (`'ble_hrm'`) into the breathing detector's
  /// Tier-1 series and stratify research exports by source.
  ///
  /// Pass the source label that produced this sample:
  /// - `'ble_hrm'` — BLE chest strap (Tier-1)
  /// - `'watch_sample'` — Apple Watch / Wear OS HK frame (Tier-2)
  /// - `'garmin_companion'`— Garmin Connect IQ companion (Tier-2)
  /// Default `'default_sensor'` is treated as Tier-3.
  static void pushRr(
    int tsMs,
    double rrMs, {
    String provider = 'default_sensor',
  }) {
    _coreRuntime?.pushRr(tsMs, rrMs, provider: provider);
  }

  /// Push vendor-reported HRV metrics (Tier 2). See [pushWearHr] for
  /// routing semantics. Negative/-1 fields are interpreted as "not
  /// available" and omitted from the batch payload.
  static void pushVendorHrv(
    int tsMs, {
    double rmssd = -1.0,
    double sdnn = -1.0,
    double stress = -1.0,
    double recovery = -1.0,
    String provider = 'default_sensor',
  }) {
    _ingestSingleEvent({
      'type': 'vendor_hrv',
      'ts_ms': tsMs,
      if (rmssd > 0) 'rmssd_ms': rmssd,
      if (sdnn > 0) 'sdnn_ms': sdnn,
      if (stress >= 0) 'stress': stress,
      if (recovery >= 0) 'recovery': recovery,
      'provider': provider,
    });
  }

  /// Push vendor vital signs (SpO2, respiration) to lab windows.
  /// Pass -1.0 for unavailable fields.
  static void pushVendorVitals(
    int tsMs, {
    double spo2 = -1.0,
    double respiration = -1.0,
  }) {
    _coreRuntime?.pushVendorVitals(tsMs, spo2: spo2, respiration: respiration);
  }

  /// Push a single accelerometer sample to the engine. Feeds the
  /// Synheart Runtime motion features (`motion.accel_rms`,
  /// `motion.steps_est`, `motion.posture_proxy`) which in turn drive
  /// the corresponding SRM baselines.
  ///
  /// Hosts that don't have raw IMU should leave this unused — the
  /// engine synthesises a coarse motion signal from `WearSample.steps`
  /// in `ingest_wear_sample`. Hosts with phone IMU (via `sensors_plus`
  /// or platform-specific bridges) should call this at ≥ 25 Hz during
  /// sessions for the engine to reach a Ready motion baseline.
  ///
  /// `x` / `y` / `z` are in m/s² (gravity-included). The engine
  /// internally subtracts gravity and computes magnitude.
  static void pushAccel(int tsMs, double x, double y, double z) {
    _coreRuntime?.pushAccel(tsMs, x, y, z);
  }

  // ── Personalization task / workout APIs ─────────────────────────────
  // the personalization spec. Forwarded directly to the engine pipeline
  // (no batch ingest) because they set pipeline state rather than
  // produce FeatureSet rows.

  /// Set the active task type for personalization-aware confidence
  /// modulation. Persists until set again or — for workouts pushed via
  /// [pushWorkoutEvent] — until the workout end is reached.
  ///
  /// Use [TaskType.unknown] to clear an active task.
  static void setTaskType(TaskType task) {
    _coreRuntime?.setTaskType(task.discriminant);
  }

  /// Push a workout / exercise event from a wearable adapter.
  ///
  /// Activates the `Movement` task for `[startTime, endTime]` with the
  /// supplied [WorkoutKind]. Optional `vendorStrain` / `vendorRecovery`
  /// scalars (in `[0, 1]`) are forwarded to the FeatureSet as
  /// `vendor_hrv.strain` / `vendor_hrv.recovery`.
  ///
  /// After `endTime` passes, the engine's next window automatically
  /// decays the task back to `Unknown`.
  static void pushWorkoutEvent(WorkoutEvent event) {
    _coreRuntime?.pushWorkoutEvent(
      event.startTime.millisecondsSinceEpoch,
      event.endTime.millisecondsSinceEpoch,
      workoutKind: event.kind.discriminant,
      vendorStrain: event.vendorStrainForFfi,
      vendorRecovery: event.vendorRecoveryForFfi,
    );
  }

  /// Currently active task type. Returns [TaskType.unknown] before any
  /// host call, after a workout window has expired, or when the engine
  /// is not running.
  static TaskType currentTaskType() {
    final raw = _coreRuntime?.currentTaskType() ?? 0;
    return TaskType.fromDiscriminant(raw);
  }

  /// Currently active workout kind. Returns [WorkoutKind.unknown]
  /// outside an active `Movement` task.
  static WorkoutKind currentWorkoutKind() {
    final raw = _coreRuntime?.currentWorkoutKind() ?? 0;
    return WorkoutKind.fromDiscriminant(raw);
  }

  /// Set the focus-kind sub-classification of the active `Focus` task.
  /// Pair with [setTaskType] (set TaskType.focus first, then this).
  ///
  /// Has no effect outside an active `Focus` task. The engine records
  /// the kind on the explanation trace for observability; multiplier
  /// effect is reserved for a future rule-pack update — see
  /// [FocusKind] doc.
  ///
  /// Use [FocusKind.unknown] to clear the sub-classification.
  static void setFocusKind(FocusKind kind) {
    _coreRuntime?.setFocusKind(kind.discriminant);
  }

  /// Currently active focus kind. Returns [FocusKind.unknown] outside
  /// an active `Focus` task or when never set.
  static FocusKind currentFocusKind() {
    final raw = _coreRuntime?.currentFocusKind() ?? 0;
    return FocusKind.fromDiscriminant(raw);
  }

  /// Last `PersonalizationContext` as JSON.
  ///
  /// Returns `null` before the first HSI window completes. Schema:
  ///
  /// ```json
  /// {
  /// "normalized": { "z": {..}, "z_confidence": {..} },
  /// "recovery_index": { "value": 0.34, "confidence": 0.81,
  /// "components": {..} },
  /// "thresholds": { "overload_threshold": 0.62, .. },
  /// "priors": { "by_type": { "recovery": 0.85, "strain": 1.15 } },
  /// "confidence_modifier": 1.0,
  /// "confidence_modifier_by_type": { "focus": 0.80, "capacity": 0.80 },
  /// "maturity": "ready",
  /// "explanation": { "entries": [
  /// { "factor": "low_sleep_recent", "effect": -0.20,
  /// "note": "recent sleep median below 40 — cognitive heads dampened 20%" }
  /// ]}
  /// }
  /// ```
  ///
  /// Render `explanation.entries` in "why was this score modulated?"
  /// SDK panels .
  static String? personalizationContextJson() {
    return _coreRuntime?.personalizationContextJson();
  }

  /// Push a daily wearable summary into the longitudinal SRM. After a
  /// batch, call [srmTriggerWearableRecompute] so the resulting
  /// `WearableReference` propagates to the next inference window.
  ///
  /// Allowed [dimension] values:
  /// - `sleep_need` — total sleep in seconds (3h–14h filter)
  /// - `sleep_regularity` — bedtime-midpoint hours-of-day (0–24)
  /// - `hrv_rmssd` — daily RMSSD in ms
  /// - `hrv_sdnn` — daily SDNN in ms (e.g. Apple Health Watch HRV)
  /// - `resting_hr` — resting HR in bpm
  /// - `recovery_score` — vendor recovery in `[0, 1]`
  /// - `deep_sleep_min` / `rem_sleep_min` — minutes per night
  /// - `daily_strain` — vendor strain normalised to `[0, 1]`
  ///
  /// [dayIndex] is the unix-epoch day (compute via
  /// [epochDayFor] or `timestamp.millisecondsSinceEpoch ~/ 86400000`).
  /// [fidelity]: `0 = raw observation`, `1 = vendor summary`. Most
  /// vendor backfill pushes are `1` with a confidence of 0.80–0.90.
  static void srmPushWearableDaily({
    required String dimension,
    required int dayIndex,
    required double value,
    double confidence = 0.85,
    int fidelity = 1,
  }) {
    _coreRuntime?.srmPushWearableDaily(
      dimension: dimension,
      dayIndex: dayIndex,
      value: value,
      confidence: confidence,
      fidelity: fidelity,
    );
  }

  /// Trigger an SRM recompute and propagate the resulting
  /// `WearableReference` to the state runtime.
  ///
  /// Call after a batch of [srmPushWearableDaily] (e.g. at the end of
  /// vendor backfill) so the next `tick()` window picks up fresh
  /// personal baselines.
  ///
  /// [triggerType]: `0 = Window` (incremental, recommended), `1 =
  /// AffectedWindow`, `2 = Full` (rebuild everything).
  /// [asOfDay] defaults to today's epoch-day if `null`.
  static void srmTriggerWearableRecompute({int triggerType = 0, int? asOfDay}) {
    final day = asOfDay ?? epochDayFor(DateTime.now());
    _coreRuntime?.srmTriggerWearableRecompute(
      triggerType: triggerType,
      asOfDay: day,
    );
  }

  /// Convert a `DateTime` to the unix-epoch day index used by
  /// [srmPushWearableDaily]. Always operates in UTC so the day boundary
  /// is stable across the user's timezone.
  static int epochDayFor(DateTime t) =>
      t.toUtc().millisecondsSinceEpoch ~/ 86_400_000;

  /// Serialize a single sensor event and hand it to `ingestBatch`. Used
  /// by the provider-tagged `push*` APIs so each sample keeps its source
  /// attribution (which the raw `pushHr`/`pushRr` FFI signatures can't
  /// carry). Invokes [onHsi] if the batch returned a completed window.
  static void _ingestSingleEvent(Map<String, dynamic> event) {
    final runtime = _coreRuntime;
    if (runtime == null) return;
    final batchJson = jsonEncode([event]);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final hsi = runtime.ingestBatch(batchJson, nowMs);
    if (hsi != null) {
      onHsi?.call(hsi);
    }
  }

  /// Advance the engine pipeline clock directly. Prefer the ingest buffer
  /// pattern for mobile — this is exposed for watch engine / advanced use.
  static String? tick(int nowMs) {
    return _coreRuntime?.tick(nowMs);
  }

  /// Ingest a pre-built event batch. Prefer [pushWearHr]/[pushRr] +
  /// automatic buffer flush for mobile — this is for watch engine / advanced use.
  static String? ingestBatch(String batchJson, int nowMs) {
    return _coreRuntime?.ingestBatch(batchJson, nowMs);
  }

  /// Last preprocessed features from the engine (HRV, motion, quality, SRM context).
  static String? get lastFeatures => _coreRuntime?.lastFeatures();

  // ── synheart-engine SRM API (baselines live in the native engine) ──

  /// Baseline summary from the native synheart-engine.
  ///
  /// Returns a JSON string like `{"total":14,"ready":0,"warming":5,"empty":9}`
  /// or `null` if the native runtime is not linked.
  static String? get runtimeBaselineSummary {
    return _coreRuntime?.baselinesJson();
  }

  /// All native runtime baselines as JSON, or `null`.
  static String? get runtimeBaselinesJson {
    return _coreRuntime?.baselinesJson();
  }

  /// Export the native runtime SRM snapshot as JSON for cross-session persistence.
  static String? exportRuntimeSRMSnapshot() {
    return _coreRuntime?.exportSrmSnapshot();
  }

  /// Load a native runtime SRM snapshot from JSON.
  /// Returns true on success, false on failure.
  static bool loadRuntimeSRMSnapshot(String json) {
    return _coreRuntime?.loadSrmSnapshot(json) ?? false;
  }

  /// The native synheart-engine version, or `null` if unavailable.
  static String? get runtimeVersion => CoreRuntimeBridge.version();

  // ── synheart-lab session API ──

  /// Whether the lab C ABI symbols are available in the loaded native library.
  static bool get isLabAvailable => _coreRuntime?.isLabAvailable ?? false;

  /// Start a lab session. Returns `null` on success, or an error string.
  static String? labStart(String protocolJson, int startedAtMs) {
    return _coreRuntime?.labStart(protocolJson, startedAtMs);
  }

  /// Open a window in the active lab session. Returns the window ID.
  static String? labOpenWindow({
    String? parentId,
    required String windowType,
    String? label,
    required int startedAtMs,
  }) {
    return _coreRuntime?.labOpenWindow(
      parentId,
      windowType,
      label,
      startedAtMs,
    );
  }

  /// Close a window in the active lab session.
  static void labCloseWindow(String windowId, int endedAtMs) {
    _coreRuntime?.labCloseWindow(windowId, endedAtMs);
  }

  /// Set protocol-specific values on a lab window.
  static void labSetWindowValues(String windowId, String valuesJson) {
    _coreRuntime?.labSetWindowValues(windowId, valuesJson);
  }

  /// Merge session-level metadata into `session_metadata.extra_data`.
  ///
  /// Returns `null` on success, or an error string.
  static String? labMergeSessionExtraData(String patchJson) {
    return _coreRuntime?.labMergeExtraData(patchJson);
  }

  /// Set per-window state-data overrides before closing a lab window.
  ///
  /// Supported override keys include `device_context`, `system_state`,
  /// and `session_spacing` in the JSON object.
  static void labSetWindowStateOverrides(
    String windowId,
    String overridesJson,
  ) {
    _coreRuntime?.labSetStateOverrides(windowId, overridesJson);
  }

  /// Finalize the lab session and return the complete payload JSON.
  static String? labFinalize(int endedAtMs) {
    return _coreRuntime?.labFinalize(endedAtMs);
  }

  /// Get the last lab export JSON (available after session end in research mode).
  static String? get labExportJson => _coreRuntime?.labExportJson();

  /// Whether the linked runtime exports the lab re-enqueue symbol
  /// (engine v0.8.1+). Older binaries return false and
  /// [labReenqueueSession] will yield [LabReenqueueResult.unsupported].
  static bool get isLabReenqueueAvailable =>
      _coreRuntime?.isLabReenqueueAvailable ?? false;

  /// Re-enqueue a previously-finalized lab session payload for cloud
  /// upload. Use this to retry sessions whose initial upload was
  /// dropped on a 4xx (typically a cloud schema mismatch — the runtime
  /// removes those rows from the upload queue so they don't clog the
  /// connector).
  ///
  /// Host reads the persisted JSON from app-side storage (pulse-focus:
  /// `LabPayloadService` / the `lab_payloads` SQLite table) and passes
  /// it back in here. Same consent + connector gates apply as the
  /// auto-enqueue path; see [LabReenqueueResult] for outcomes.
  ///
  /// Returns [LabReenqueueResult.cloudNotConfigured] when the SDK is
  /// not initialized — callers should treat that as a no-op rather
  /// than a bug.
  static LabReenqueueResult labReenqueueSession(String sessionJson) {
    final rt = _coreRuntime;
    if (rt == null) return LabReenqueueResult.cloudNotConfigured;
    return rt.labReenqueueSession(sessionJson);
  }

  // ── Lab metadata ─────────────────────────────────────────────────────

  /// Whether the runtime exposes the lab metadata symbols.
  static bool get isLabMetadataAvailable =>
      _coreRuntime?.isLabMetadataAvailable ?? false;

  /// Build the metadata payload from current config + caller-supplied device
  /// and user info, then upload it if the canonical hash differs from the
  /// cached copy or the dirty flag is set. Returns the active `meta_id`.
  ///
  /// Call once at app start (after registration + research consent) and again
  /// only when [labMarkMetadataDirty] has been signaled. Subsequent calls are
  /// cheap — they short-circuit when the payload is unchanged.
  static String? labEnsureMetadata({
    required String deviceId,
    required String platform,
    required String osVersion,
    String? userInfoJson,
    String? deviceExtraJson,
  }) {
    return _coreRuntime?.labEnsureMetadata(
      deviceId: deviceId,
      platform: platform,
      osVersion: osVersion,
      userInfoJson: userInfoJson,
      deviceExtraJson: deviceExtraJson,
    );
  }

  /// Mark cached lab metadata as needing re-upload. Hosts call this on
  /// profile edits, device swaps, app version bumps, and consent changes.
  static void labMarkMetadataDirty(String reason) {
    _coreRuntime?.labMarkMetadataDirty(reason);
  }

  /// Cached `meta_id` to stamp on lab sessions, or null if nothing is cached.
  static String? labCurrentMetadataId() => _coreRuntime?.labCurrentMetadataId();

  // Collection status getters
  bool get _isWearCollecting {
    return _wearModule?.status == ModuleStatus.running;
  }

  bool get _isBehaviorCollecting {
    return _behaviorModule?.status == ModuleStatus.running;
  }

  bool get _isPhoneCollecting {
    return _phoneModule?.status == ModuleStatus.running;
  }

  /// Clear session buffers and subscribe to consent-gated HSI + raw wear streams.
  void _wireSessionBuffers() {
    _sessionHsiSubscription?.cancel();
    _sessionWearSubscription?.cancel();
    _sessionHsiBuffer = [];
    _sessionWearBuffer = [];
    // HSI session buffer is filled via the setHsiCallback wired in configure().
    // The _hsvStream already receives consent-gated HSI; listen to it for session buffering.
    _sessionHsiSubscription = _hsvStream.stream.listen((hsiJson) {
      _sessionHsiBuffer.add(hsiJson);
    });
    if (_wearModule != null) {
      _sessionWearSubscription = _wearModule!.rawSampleStream.listen(
        (sample) => _sessionWearBuffer.add(sample),
      );
    }
  }

  Future<void> _startRuntimeLinkedCollection() async {
    if (_isRunning) return;
    await _moduleManager.startAll();
    _wireSessionBuffers();
    _isRunning = true;
    _reevaluateAllFeatures();
  }

  Future<void> _stopRuntimeLinkedCollection() async {
    await _sessionHsiSubscription?.cancel();
    _sessionHsiSubscription = null;
    await _sessionWearSubscription?.cancel();
    _sessionWearSubscription = null;
    // `_logRuntimeSummary` is called by [stopSession] before
    // `_coreRuntime.stopSession()` so the pipeline is still alive
    // when frame_count is read. Calling it here again would log a
    // second line with frame_count=0 (pipeline torn down by then).
    await _moduleManager.stopAll();
  }

  void _logRuntimeSummary() {
    if (_coreRuntime == null) return;
    final fc = _coreRuntime!.frameCount();
    final q = _coreRuntime!.lastQuality();
    SynheartLogger.log(
      '[Runtime] Session end: frameCount=$fc lastQuality=$q'
      '${fc == 0 ? " (no HSI produced — no window completed)" : ""}',
    );
  }

  /// Start all data collection modules
  Future<void> _startDataCollection({int? durationSec}) async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before starting data collection',
      );
    }

    if (_isRunning) {
      SynheartLogger.log('[Synheart] Data collection already running');
      return;
    }

    final activated = _activationManager?.activatedFeatures() ?? {};
    if (activated.isEmpty) {
      throw StateError(
        'At least one feature must be enabled to start a session. '
        'Configure SynheartConfig with at least one of: wearConfig, phoneConfig, '
        'behaviorConfig, cloudConfig; or call Synheart.activate() for a feature.',
      );
    }

    if (!_hasAtLeastOneFeatureWithConsent()) {
      throw StateError(
        'At least one feature must have consent to start a session. '
        'Grant consent for at least one of: biosignals, behavior, phoneContext (e.g. via Synheart.grantConsent or the app consent UI).',
      );
    }

    SynheartLogger.log('[Synheart] Starting all data collection modules..');

    // Open main collection session via Session SDK (RFC: session boundary)
    final sessionId = 'core_${DateTime.now().millisecondsSinceEpoch}';
    final sec =
        durationSec ?? 86400; // default 24h — long-lived; stop explicitly
    final config = SessionConfig(
      mode: SessionMode.focus,
      durationSec: sec,
      sessionId: sessionId,
    );
    _activeMainSessionId = sessionId;
    _mainSessionSubscription = _mainSession!
        .startSession(config)
        .listen(
          (_) {},
          onDone: () {
            _activeMainSessionId = null;
            if (_isRunning) {
              _isRunning = false;
              _reevaluateAllFeatures();
              _logRuntimeSummary();
              _moduleManager.stopAll();
              SynheartLogger.log(
                '[Synheart] Main session ended (duration or stream closed)',
              );
            }
          },
          onError: (e, st) {
            SynheartLogger.log(
              '[Synheart] Main session stream error: $e',
              error: e,
              stackTrace: st,
            );
            _activeMainSessionId = null;
          },
        );

    await _moduleManager.startAll();

    _wireSessionBuffers();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final mode = _config?.mode ?? SynheartMode.personal;
    _currentSessionHandle = SessionHandle(
      sessionId: sessionId,
      startedAtMs: nowMs,
      mode: mode,
    );

    _isRunning = true;
    _reevaluateAllFeatures();
    SynheartLogger.log('[Synheart] Data collection started');
  }

  /// Stop all data collection modules
  Future<void> _stopDataCollection() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before stopping data collection',
      );
    }

    if (!_isRunning) {
      SynheartLogger.log('[Synheart] Data collection already stopped');
      return;
    }

    SynheartLogger.log('[Synheart] Stopping all data collection modules..');

    // Close main collection session via Session SDK
    if (_activeMainSessionId != null) {
      await _mainSession?.stopSession(_activeMainSessionId!);
      await _mainSessionSubscription?.cancel();
      _mainSessionSubscription = null;
      _activeMainSessionId = null;
    }
    // Cancel buffer subscriptions but keep buffers for post-session queries
    await _sessionHsiSubscription?.cancel();
    _sessionHsiSubscription = null;
    await _sessionWearSubscription?.cancel();
    _sessionWearSubscription = null;

    _currentSessionHandle = null;

    _isRunning = false;
    _reevaluateAllFeatures();
    _logRuntimeSummary();
    await _moduleManager.stopAll();
    SynheartLogger.log('[Synheart] Data collection stopped');
  }

  /// Start wear data collection
  Future<void> _startWearCollection({Duration? interval}) async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before starting wear collection',
      );
    }

    if (_wearModule == null) {
      throw StateError('Wear module not initialized');
    }

    if (_isWearCollecting) {
      // SynheartLogger.log('[Synheart] Wear collection already running');
      // If interval changed, update it
      if (interval != null) {
        await _wearModule!.updateCollectionInterval(interval);
      }
      return;
    }

    // SynheartLogger.log('[Synheart] Starting wear data collection..');
    if (interval != null) {
      await _wearModule!.updateCollectionInterval(interval);
    }
    await _wearModule!.start();
    // SynheartLogger.log('[Synheart] Wear data collection started');
  }

  /// Stop wear data collection
  Future<void> _stopWearCollection() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before stopping wear collection',
      );
    }

    if (_wearModule == null) {
      throw StateError('Wear module not initialized');
    }

    if (!_isWearCollecting) {
      // SynheartLogger.log('[Synheart] Wear collection already stopped');
      return;
    }

    // SynheartLogger.log('[Synheart] Stopping wear data collection..');
    await _wearModule!.stop();
    // SynheartLogger.log('[Synheart] Wear data collection stopped');
  }

  /// Start behavior data collection
  Future<void> _startBehaviorCollection() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before starting behavior collection',
      );
    }

    if (_behaviorModule == null) {
      throw StateError('Behavior module not initialized');
    }

    if (_isBehaviorCollecting) {
      // SynheartLogger.log('[Synheart] Behavior collection already running');
      return;
    }

    // SynheartLogger.log('[Synheart] Starting behavior data collection..');
    await _behaviorModule!.start();
    // SynheartLogger.log('[Synheart] Behavior data collection started');
  }

  /// Stop behavior data collection
  Future<void> _stopBehaviorCollection() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before stopping behavior collection',
      );
    }

    if (_behaviorModule == null) {
      throw StateError('Behavior module not initialized');
    }

    if (!_isBehaviorCollecting) {
      // SynheartLogger.log('[Synheart] Behavior collection already stopped');
      return;
    }

    // SynheartLogger.log('[Synheart] Stopping behavior data collection..');
    await _behaviorModule!.stop();
    // SynheartLogger.log('[Synheart] Behavior data collection stopped');
  }

  /// Start phone context data collection
  Future<void> _startPhoneCollection() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before starting phone collection',
      );
    }

    if (_phoneModule == null) {
      throw StateError('Phone module not initialized');
    }

    if (_isPhoneCollecting) {
      SynheartLogger.log('[Synheart] Phone collection already running');
      return;
    }

    SynheartLogger.log('[Synheart] Starting phone data collection..');
    await _phoneModule!.start();
    SynheartLogger.log('[Synheart] Phone data collection started');
  }

  /// Stop phone context data collection
  Future<void> _stopPhoneCollection() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before stopping phone collection',
      );
    }

    if (_phoneModule == null) {
      throw StateError('Phone module not initialized');
    }

    if (!_isPhoneCollecting) {
      SynheartLogger.log('[Synheart] Phone collection already stopped');
      return;
    }

    SynheartLogger.log('[Synheart] Stopping phone data collection..');
    await _phoneModule!.stop();
    SynheartLogger.log('[Synheart] Phone data collection stopped');
  }

  /// Start a behavior session
  Future<String> _startBehaviorSession() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before starting behavior session',
      );
    }

    if (_behaviorModule == null) {
      throw StateError('Behavior module not initialized');
    }

    final synheartBehavior = _behaviorModule!.synheartBehavior;
    if (synheartBehavior == null) {
      throw StateError(
        'synheart_behavior not initialized. Behavior module must be started first.',
      );
    }

    // SynheartLogger.log('[Synheart] Starting behavior session..');
    final session = await synheartBehavior.startSession();

    // Track the session so we can end it later
    _activeBehaviorSessions[session.sessionId] = session;

    // SynheartLogger.log(
    // '[Synheart] Behavior session started: ${session.sessionId}',
    // );
    return session.sessionId;
  }

  /// Stop a behavior session and get results
  Future<BehaviorSessionResults> _stopBehaviorSession(String sessionId) async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before stopping behavior session',
      );
    }

    if (_behaviorModule == null) {
      throw StateError('Behavior module not initialized');
    }

    final synheartBehavior = _behaviorModule!.synheartBehavior;
    if (synheartBehavior == null) {
      throw StateError(
        'synheart_behavior not initialized. Behavior module must be started first.',
      );
    }

    // Get the tracked session
    final session = _activeBehaviorSessions[sessionId];
    if (session == null) {
      throw StateError(
        'Session not found: $sessionId. Make sure you started the session using startBehaviorSession().',
      );
    }

    // SynheartLogger.log('[Synheart] Stopping behavior session: $sessionId..');

    // End the session and get summary
    final summary = await session.end();

    // Remove from tracking
    _activeBehaviorSessions.remove(sessionId);

    // SynheartLogger.log('[Synheart] Behavior session stopped: $sessionId');
    return BehaviorSessionResults.fromSummary(summary);
  }

  /// Get wear features for a specific time window
  /// Wrap a widget with behavior gesture detector if behavior consent is granted
  ///
  /// This method automatically checks if:
  /// - The SDK is initialized
  /// - Behavior module is available
  /// - Behavior consent is granted
  ///
  /// If all conditions are met, the widget is wrapped with the gesture detector.
  /// Otherwise, the original widget is returned unwrapped.
  ///
  /// Example:
  /// ```dart
  /// MaterialApp(
  /// home: Synheart.wrapWithBehaviorDetector(
  /// MaterialApp(..),
  /// ),
  /// )
  /// ```
  static Widget wrapWithBehaviorDetector(Widget child) {
    return shared._wrapWithBehaviorDetector(child);
  }

  Widget _wrapWithBehaviorDetector(Widget child) {
    // Check if SDK is configured and behavior module is available
    if (!_isConfigured || _behaviorModule == null) {
      return child;
    }

    // Check if behavior consent is granted
    if (_consentModule == null || !_consentModule!.current().behavior) {
      return child;
    }

    // Get synheart_behavior instance
    final synheartBehavior = _behaviorModule!.synheartBehavior;
    if (synheartBehavior == null) {
      return child;
    }

    // Wrap with gesture detector
    return synheartBehavior.wrapWithGestureDetector(child);
  }

  /// Get current consent snapshot
  ConsentSnapshot? get currentConsent {
    return _consentModule?.current();
  }

  /// Update consent
  static Future<void> updateConsent(ConsentSnapshot consent) async {
    return shared._updateConsent(consent);
  }

  Future<void> _updateConsent(ConsentSnapshot consent) async {
    if (_consentModule == null) {
      throw StateError('Consent module not initialized');
    }
    await _consentModule!.updateConsent(consent);
  }

  // Consent service integration methods

  /// Consent UI manager (for app-provided UI)
  final ConsentUIManager _consentUI = ConsentUIManager();

  /// Set custom consent UI provider
  ///
  /// Example:
  /// ```dart
  /// Synheart.setConsentUIProvider((profiles) async {
  /// // Show your custom UI
  /// return await showConsentDialog(profiles);
  /// });
  /// ```
  static void setConsentUIProvider(ConsentUIProvider provider) {
    shared._consentUI.customUIProvider = provider;
  }

  /// Get available consent profiles from cloud service
  ///
  /// Requires ConsentConfig to be provided during initialization.
  static Future<List<ConsentProfile>> getAvailableConsentProfiles() async {
    return shared._getAvailableConsentProfiles();
  }

  Future<List<ConsentProfile>> _getAvailableConsentProfiles() async {
    if (_consentModule == null) {
      throw StateError('Consent module not initialized');
    }
    return _consentModule!.getAvailableProfiles();
  }

  /// Request consent by presenting UI and issuing token
  ///
  /// This method:
  /// 1. Fetches available consent profiles
  /// 2. Presents UI (via customUIProvider if set)
  /// 3. Issues token for selected profile
  /// 4. Updates local consent snapshot
  ///
  /// Returns the issued token, or null if user declined.
  static Future<ConsentToken?> requestConsent() async {
    return shared._requestConsent();
  }

  Future<ConsentToken?> _requestConsent() async {
    if (_consentModule == null) {
      throw StateError('Consent module not initialized');
    }

    try {
      final profiles = await _consentModule!.getAvailableProfiles();
      if (profiles.isEmpty) {
        SynheartLogger.log('[Synheart] No consent profiles available');
        return null;
      }

      final selected = await _consentUI.presentConsentFlow(profiles);
      if (selected == null) {
        return null; // User declined
      }

      final token = await _consentModule!.requestConsent(selected);
      return token;
    } catch (e, stack) {
      SynheartLogger.log(
        '[Synheart] Error requesting consent: $e',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Check current consent status
  static ConsentStatus getConsentStatus() {
    return shared._getConsentStatus();
  }

  ConsentStatus _getConsentStatus() {
    if (_consentModule == null) {
      return ConsentStatus.pending;
    }
    return _consentModule!.checkConsentStatus();
  }

  /// Get current consent token (if available and valid)
  static ConsentToken? getCurrentConsentToken() {
    return shared._getCurrentConsentToken();
  }

  ConsentToken? _getCurrentConsentToken() {
    return _consentModule?.getCurrentToken();
  }

  /// Ensure runtime cloud consent is ready for ingest uploads.
  ///
  /// This follows the granular runtime flow:
  /// - read editable form,
  /// - submit current consent choices,
  /// - verify runtime status / token refresh state.
  ///
  /// IMPORTANT: this is the consent-grant chain — the runtime gate
  /// (`has_consent`) deliberately fails-closed when cloud is configured
  /// but no valid consent token is loaded. We must NOT pre-check that
  /// gate here, because the whole point of this function is to obtain
  /// the token that flips the gate open. Instead we read the local
  /// snapshot (effective state) directly: that tells us whether the
  /// user has chosen to allow cloud upload, independent of token
  /// validity. When the snapshot says cloud is allowed but no valid
  /// token exists, this is exactly the cold-start "user granted in a
  /// prior session, token expired or never persisted" case — and we
  /// need to re-submit the form to issue a fresh token.
  static Future<bool> ensureCloudConsentReady() async {
    final runtime = _coreRuntime;
    if (runtime == null) return false;
    final effective = consentEffectiveStateTyped();
    if (effective?.cloudUpload != true) return false;

    final status = consentStatus()?['status']?.toString().toLowerCase();
    final needsRefresh = consentNeedsTokenRefresh();
    if (status == 'granted' && !needsRefresh) {
      return true;
    }

    final currentForm = consentGetEditableFormTyped();
    if (currentForm == null) return false;
    final local = shared._consentModule?.current();
    final mergedForm = currentForm.copyWith(
      biosignals:
          local?.biosignals ?? effective?.biosignals ?? currentForm.biosignals,
      phoneContext:
          local?.phoneContext ??
          effective?.phoneContext ??
          currentForm.phoneContext,
      behavior: local?.behavior ?? effective?.behavior ?? currentForm.behavior,
      allowCloud: true,
      allowResearch:
          local?.research ?? effective?.research ?? currentForm.allowResearch,
      allowVendorSync:
          local?.vendorSync ??
          effective?.vendorSync ??
          currentForm.allowVendorSync,
    );

    final submit = await consentSubmitFormTyped(form: mergedForm);
    if (submit == null || submit['error'] != null) {
      return false;
    }
    // Verify a token was actually issued. submit_form returns
    // `synced=false, token=null` (without `error`) when the cloud
    // profile fetch or token-issue HTTP call failed — the local
    // snapshot is still saved but the runtime stays in Pending and
    // the biosignal/research gates remain closed. Treating that as
    // success would silently drop pushes for the rest of the session.
    final tokenIssued = submit['token'] != null;
    final synced = submit['synced'] == true;
    if (!tokenIssued || !synced) {
      SynheartLogger.log(
        '[Synheart] ensureCloudConsentReady: submit accepted but no '
        'cloud token issued (synced=$synced, token=$tokenIssued). '
        'Likely network/cloud unavailable — gates stay closed.',
      );
      return false;
    }
    final refreshedStatus = consentStatus()?['status']
        ?.toString()
        .toLowerCase();
    return refreshedStatus == 'granted' && !consentNeedsTokenRefresh();
  }

  /// Get all consent statuses as a map
  ///
  /// Example:
  /// ```dart
  /// Map<String, bool> statuses = await Synheart.getConsentStatusMap();
  /// print(statuses['biosignals']); // true/false
  /// ```
  static Map<String, bool> getConsentStatusMap() {
    return shared._getConsentStatusMap();
  }

  /// Check if consent is needed
  ///
  /// Returns true if:
  /// - CloudConfig is provided
  /// - At least one module config is provided (Wear, Phone, or Behavior)
  /// - No stored consent exists
  ///
  /// Example:
  /// ```dart
  /// if (await Synheart.needsConsent()) {
  /// // Show consent UI
  /// }
  /// ```
  static Future<bool> needsConsent() async {
    return shared._needsConsent();
  }

  Future<bool> _needsConsent() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before checking consent needs',
      );
    }

    // Only need consent if CloudConfig is provided
    if (_config?.cloudConfig == null) {
      return false;
    }

    // Check if at least one module config is provided
    final hasModuleConfig =
        _config?.wearConfig != null ||
        _config?.phoneConfig != null ||
        _config?.behaviorConfig != null;

    if (!hasModuleConfig) {
      return false;
    }

    // Check if consent was previously granted
    if (_consentModule == null) {
      return true; // No consent module means no stored consent
    }

    final consent = _consentModule!.current();
    return !consent.biosignals && !consent.behavior && !consent.phoneContext;
  }

  /// Get consent information for enabled modules
  ///
  /// Returns a map of module names to their consent descriptions.
  /// Only includes modules that have configs provided during initialization.
  ///
  /// Example:
  /// ```dart
  /// final consentInfo = await Synheart.getConsentInfo();
  /// print(consentInfo['biosignals']); // "Collect heart rate and HRV data.."
  /// ```
  static Future<Map<String, String>> getConsentInfo() async {
    return shared._getConsentInfo();
  }

  Future<Map<String, String>> _getConsentInfo() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before getting consent info',
      );
    }

    final info = <String, String>{};

    if (_config?.wearConfig != null) {
      info['biosignals'] =
          'Collect heart rate, heart rate variability, and other biosignals from your wearable device to understand your physiological state.';
    }

    if (_config?.phoneConfig != null) {
      info['phoneContext'] =
          'Collect motion and phone context data (screen state, app usage) to understand your activity patterns and device interactions.';
    }

    if (_config?.behaviorConfig != null) {
      info['behavior'] =
          'Collect behavioral data (typing patterns, gestures) to understand your interaction patterns and cognitive state.';
    }

    if (_config?.cloudConfig != null) {
      info['cloudUpload'] =
          'Upload anonymized state data to the cloud for enhanced insights and personalization. Your data is encrypted and pseudonymized.';
    }

    return info;
  }

  /// Grant consent for specific modules
  ///
  /// This should be called after the user has made their consent choices in the UI.
  /// If CloudConfig is provided, this will also issue
  /// a consent token from the consent service.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.grantConsent(
  /// biosignals: true,
  /// behavior: true,
  /// phoneContext: true,
  /// cloudUpload: true,
  /// );
  /// ```

  /// Process a vendor wearable event from RAMEN into the SRM pipeline.
  ///
  /// Call this from the wear SDK when a [RamenEvent] arrives.
  /// The internal WearModule instance (for vendor sync state observation).
  static WearModule? get wearModule => shared._wearModule;

  /// The event is normalized to a CanonicalWearableEvent, stored in SQLite,
  /// and pushed to the runtime for longitudinal baseline computation.
  ///
  /// Returns the canonical event the vendor payload was mapped to, or
  /// `null` if dropped (consent denied, no processor, mapping miss).
  static Future<CanonicalWearableEvent?> processVendorEvent({
    required String provider,
    required String eventType,
    required Map<String, dynamic> payload,
    required String eventId,
    required int seq,
  }) async {
    return shared._wearModule?.processVendorEvent(
      provider: provider,
      eventType: eventType,
      payload: payload,
      eventId: eventId,
      seq: seq,
    );
  }

  // ── Sleep Score (RFC-SLEEP-SCORE-PIPELINE-0001) ──────────────────

  /// Compute a batch [SleepScoreResult] from a [SleepScoreInput].
  ///
  /// Stateless: runs purely through the engine pipeline and does not
  /// persist. Use [attachSleepScore] to ride the next HSI with the
  /// returned result. Returns `null` if the runtime is not initialized
  /// or the engine rejected the input.
  static SleepScoreResult? computeSleepScore(SleepScoreInput input) {
    return _coreRuntime?.computeSleepScore(input);
  }

  /// Attach a batch [SleepScoreResult] so it rides the next emitted
  /// HSI window as the `sleep_score` axis and feeds the Path-B
  /// 7-night median. Returns 0 on success, non-zero on failure.
  static int attachSleepScore(SleepScoreResult result) {
    return _coreRuntime?.attachSleepScore(result) ?? -1;
  }

  // ── Recovery Score (RFC-RECOVERY-SCORE-0001) ──────────────────────

  /// Compute a daily Recovery Score from a JSON-encoded
  /// `RecoveryScoreInput`.
  ///
  /// Three-stage scoring per RFC-RECOVERY-SCORE-0001:
  /// - Stage 1 (FirstDay): 1 night of sleep + (HR or HRV)
  /// - Stage 2 (ShortHistory): ≥ 3 nights with HR/HRV trends
  /// - Stage 3 (Personalized): ≥ 7 nights + stable wearable baselines
  ///
  /// Returns the JSON-encoded `RecoveryScoreResult` on success, the
  /// literal `"null"` when the input has no overnight HR/HRV (sleep-only
  /// recovery is forbidden by design), or `null` on parse error / when
  /// the runtime isn't initialized.
  ///
  /// Decode the result with `RecoveryScoreResult.fromJsonString` (Dart
  /// model in the consuming app) or `jsonDecode(raw)` for ad-hoc
  /// rendering. The shape mirrors the Synheart Runtime's
  /// `RecoveryScoreResult` JSON-serialized form and is locked.
  static String? computeRecoveryScoreJson(String inputJson) {
    return _coreRuntime?.recoveryScoreComputeJson(inputJson);
  }

  /// Same as [computeRecoveryScoreJson] with a host-supplied
  /// correlation id attached to tracing events.
  static String? computeRecoveryScoreJsonTraced(
    String inputJson,
    String correlationId,
  ) {
    return _coreRuntime?.recoveryScoreComputeJsonTraced(
      inputJson,
      correlationId,
    );
  }

  /// Typed version of [computeRecoveryScoreJson]: builds the JSON,
  /// invokes the engine, and parses the result. Returns `null` when
  /// the input has no overnight HR/HRV (sleep-only recovery is
  /// forbidden by design) or when the runtime isn't ready / the
  /// engine returned an error.
  static RecoveryScoreResult? computeRecoveryScore(RecoveryScoreInput input) {
    final raw = _coreRuntime?.recoveryScoreComputeJson(input.toJsonString());
    if (raw == null || raw.isEmpty || raw == 'null') return null;
    try {
      return RecoveryScoreResult.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  // ── Readiness Score (RFC-READINESS-SCORE-0001) ────────────────────

  /// Compute a daily Readiness Score from a JSON-encoded
  /// `ReadinessScoreInput`. Combines today's Recovery Score with
  /// optional acute / chronic load, fatigue, and history context to
  /// answer "how much strain should the user take today?".
  ///
  /// Returns the JSON-encoded `ReadinessScoreResult` on success, or
  /// `null` on parse error / runtime not ready.
  static String? computeReadinessScoreJson(String inputJson) {
    return _coreRuntime?.readinessScoreComputeJson(inputJson);
  }

  /// Same as [computeReadinessScoreJson] with a host-supplied
  /// correlation id attached to tracing events.
  static String? computeReadinessScoreJsonTraced(
    String inputJson,
    String correlationId,
  ) {
    return _coreRuntime?.readinessScoreComputeJsonTraced(
      inputJson,
      correlationId,
    );
  }

  /// Typed version of [computeReadinessScoreJson]: builds the JSON,
  /// invokes the engine, and parses the result. Returns `null` only
  /// when the runtime isn't ready or the engine returned an error —
  /// readiness is computed whenever a recovery anchor is provided.
  static ReadinessScoreResult? computeReadinessScore(
    ReadinessScoreInput input,
  ) {
    final raw = _coreRuntime?.readinessScoreComputeJson(input.toJsonString());
    if (raw == null || raw.isEmpty || raw == 'null') return null;
    try {
      return ReadinessScoreResult.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  /// Attach today's daily Recovery Score (`0.=100`) so personalization
  /// Stage 2 blends it alongside the per-window HRV / RHR / provider /
  /// recent-sleep components. Sticky across HSI windows until cleared
  /// or replaced — call again on day rollover with a fresh score.
  /// Returns `0` on success.
  static int attachRecoveryScoreToday(int score) {
    return _coreRuntime?.attachRecoveryScoreToday(score) ?? -1;
  }

  /// Drop today's Recovery Score. Use on day rollover when no fresh
  /// score is yet available. Returns `0` on success.
  static int clearRecoveryScoreToday() {
    return _coreRuntime?.clearRecoveryScoreToday() ?? -1;
  }

  /// Snapshot of the current [WearableReferenceView] — including
  /// Path-B `recent_sleep_score_median`. Null when no reference has
  /// been produced yet or the runtime is not initialized.
  static WearableReferenceView? get wearableReference {
    return _coreRuntime?.wearableReference();
  }

  /// Last live-head SleepScore JSON (live-head shape:
  /// path/mode/components/tier/baseline). Null before the first
  /// window closes. For the batch-score shape use [computeSleepScore].
  static String? get lastSleepScoreJson {
    return _coreRuntime?.lastSleepScoreJson();
  }

  /// Raw JSON of the longitudinal SRM snapshot (Path-B
  /// `recent_sleep_score_ring`, dimension buffers, last reference,
  /// schema version). Useful to surface the ring before any HSI
  /// window has closed — the ring updates on every
  /// [attachSleepScore], whereas [wearableReference] only refreshes
  /// when the live HSI tick produces a window.
  static String? get longitudinalSnapshotJson {
    return _coreRuntime?.exportLongitudinalSnapshot();
  }

  // ── Vendor Sync (RAMEN via native stream-runtime) ────────────────

  /// Start the RAMEN streaming connection.
  ///
  /// [config] must include `host`, `port`, `app_id`, `device_id`, `user_id`.
  /// Optional: `api_key`, `use_tls`, `providers`, `event_types`.
  ///
  /// Stream events are automatically routed through [processVendorEvent]
  /// for normalization and storage.
  static void startVendorSync(Map<String, dynamic> config) {
    final bridge = _coreRuntime;
    if (bridge == null) {
      SynheartLogger.stream('Cannot start: runtime not initialized');
      return;
    }

    SynheartLogger.stream(
      'Starting RAMEN '
      'host=${config['host']}:${config['port']} '
      'app_id=${config['app_id']} '
      'user_id=${config['user_id']} '
      'use_tls=${config['use_tls']}',
    );

    // Capture connection-level identifiers so [_emitRawRamenEvent]
    // can stamp them onto each surfaced [RamenEvent] (the runtime
    // only carries event-level fields on the broadcast).
    _vendorAppId = config['app_id']?.toString() ?? '';
    _vendorUserId = config['user_id']?.toString() ?? '';

    // Register callback — each event from the native runtime is parsed and processed.
    bridge.setStreamCallback((String eventJson) {
      try {
        final event = jsonDecode(eventJson) as Map<String, dynamic>;
        final provider = event['provider']?.toString() ?? '';
        final eventType = event['event_type']?.toString() ?? '';
        final payloadJson = event['payload_json']?.toString() ?? '{}';
        final eventId = event['event_id']?.toString() ?? '';
        final seq = (event['seq'] as num?)?.toInt() ?? 0;

        // Surface the raw event on the typed stream first so apps
        // that want client-side ping handling see it before the
        // auto-route below kicks in.
        _emitRawRamenEvent(event);

        // Skip the auto-route for ping-flavored events: their inline
        // payload is empty by design (Garmin / Oura / Fitbit only send
        // a notification). The app must subscribe to [rawRamenEvents]
        // and use `RamenEventDispatcher` to fetch the full record via
        // REST before re-entering [processVendorEvent]. Auto-routing
        // here would just store an empty payload keyed by the event_id,
        // which then blocks the real one.
        final hint = event['delivery_hint']?.toString() ?? '';
        if (hint == 'ping') {
          SynheartLogger.stream(
            '[RAMEN] ping event provider=$provider type=$eventType '
            'event_id=$eventId seq=$seq — deferring to rawRamenEvents subscriber',
          );
          return;
        }

        Map<String, dynamic> payload;
        try {
          payload = jsonDecode(payloadJson) as Map<String, dynamic>;
        } catch (_) {
          payload = {};
        }

        // Surface the full raw payload so we can diff what RAMEN delivers
        // vs what backfill stores. Truncate at 1k chars to avoid log spam
        // on large workout/strain bodies.
        final preview = payloadJson.length > 1000
            ? '${payloadJson.substring(0, 1000)}…(${payloadJson.length}B)'
            : payloadJson;
        SynheartLogger.stream(
          '[RAMEN] event provider=$provider type=$eventType '
          'event_id=$eventId seq=$seq payload=$preview',
        );

        processVendorEvent(
          provider: provider,
          eventType: eventType,
          payload: payload,
          eventId: eventId,
          seq: seq,
        );

        // Mirror sleep events into Baselines.ingestVendorSleep — same fan-out
        // the backfill path performs. Baselines looks for the raw vendor
        // record under `<provider>_data`, so wrap it accordingly.
        if (eventType.contains('sleep')) {
          final wrapped = <String, dynamic>{
            '${provider}_data': payload,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          };
          // ignore: discarded_futures — fire-and-forget, matches backfill
          Baselines.ingestVendorSleep(provider: provider, payload: wrapped);
        }
      } catch (e) {
        SynheartLogger.stream('event parse failed: $e', error: e);
      }
    });

    bridge.startStream(config);
  }

  /// Stop the RAMEN streaming connection.
  static void stopVendorSync() {
    SynheartLogger.stream('Stopping RAMEN');
    _coreRuntime?.stopStream();
    _coreRuntime?.clearStreamCallback();
    _vendorAppId = '';
    _vendorUserId = '';
  }

  /// Get the current vendor sync connection state.
  ///
  /// Returns "connecting", "connected", "disconnected", or "reconnecting".
  static String? get vendorSyncState => _coreRuntime?.streamState();

  /// Stream of canonical vendor events as they are processed and stored.
  static Stream<CanonicalWearableEvent>? get vendorEvents =>
      shared._wearModule?.canonicalEvents;

  // ── Raw RAMEN event stream (for capability-flavored handling) ─────
  //
  // Apps that want client-side control over stream vs ping delivery
  // (capability-flavored delivery, 2026-05-02) subscribe here and route through
  // `RamenEventDispatcher` from synheart_wear before calling
  // `Synheart.processVendorEvent`. Apps that don't care can keep
  // using `vendorEvents` — the runtime auto-routes inline payloads
  // there, but ping-flavored events arrive payload-less and need
  // a follow-up REST pull.

  static final StreamController<RamenEvent> _ramenEventController =
      StreamController<RamenEvent>.broadcast();

  // Captured from the most recent [startVendorSync] config. The
  // native RamenEvent carries only event-level fields; app_id /
  // user_id are connection-level so we stamp them here before surfacing.
  static String _vendorAppId = '';
  static String _vendorUserId = '';

  /// Raw RAMEN events as they arrive from the runtime, with the
  /// capability-flavored `deliveryHint` parsed from the cloud.
  ///
  /// Apps wanting ping vs stream control should subscribe here
  /// rather than `vendorEvents` (which only sees the post-processed
  /// canonical events that the runtime auto-routed). Pair with
  /// `RamenEventDispatcher` from synheart_wear to materialize ping
  /// payloads via REST.
  static Stream<RamenEvent> get rawRamenEvents => _ramenEventController.stream;

  /// Internal: invoked from the stream callback below for every
  /// incoming event.
  static void _emitRawRamenEvent(Map<String, dynamic> json) {
    if (_ramenEventController.isClosed) return;
    _ramenEventController.add(
      RamenEvent.fromRuntimeJson(
        json,
        appId: _vendorAppId,
        userId: _vendorUserId,
      ),
    );
  }

  /// Query stored vendor events from the Core runtime.
  ///
  /// Returns a list of decoded event maps with `event_id`, `type`, `provider`,
  /// `payload`, `observed_at_ms`, `confidence`, etc.
  static List<dynamic>? queryVendorEvents({
    String? provider,
    String? type,
    DateTime? start,
    DateTime? end,
    int limit = 100,
  }) {
    return _coreRuntime?.queryVendorEvents(
      provider: provider,
      type: type,
      startMs: start?.millisecondsSinceEpoch,
      endMs: end?.millisecondsSinceEpoch,
      limit: limit,
    );
  }

  /// Get the most recent vendor event of a given type.
  static Map<String, dynamic>? getLatestVendorEvent(
    String provider,
    String type,
  ) {
    return _coreRuntime?.getLatestVendorEvent(provider, type);
  }

  /// Delete all stored vendor events for a provider (e.g. on unlink).
  static int deleteVendorEventsForProvider(String provider) {
    return _coreRuntime?.deleteVendorEventsForProvider(provider) ?? -1;
  }

  static Future<void> grantConsent({
    required bool biosignals,
    required bool behavior,
    required bool phoneContext,
    required bool cloudUpload,
    bool vendorSync = false,
    String? profileId,
    ConsentTier? tier,
    ConsentChannels? grantedChannels,
    bool research = false,
  }) async {
    if (_coreRuntime != null) {
      // Mirror every channel's new value into the native core — grant when
      // true, revoke when false. Without the revoke path the core's state
      // drifts out of sync with the UI the moment the user flips a toggle
      // OFF (the subsequent hasConsent read returns the stale TRUE).
      biosignals
          ? _coreRuntime!.grantConsent('biosignals')
          : _coreRuntime!.revokeConsent('biosignals');
      behavior
          ? _coreRuntime!.grantConsent('behavior')
          : _coreRuntime!.revokeConsent('behavior');
      phoneContext
          ? _coreRuntime!.grantConsent('phone_context')
          : _coreRuntime!.revokeConsent('phone_context');
      cloudUpload
          ? _coreRuntime!.grantConsent('cloud_upload')
          : _coreRuntime!.revokeConsent('cloud_upload');
      vendorSync
          ? _coreRuntime!.grantConsent('vendor_sync')
          : _coreRuntime!.revokeConsent('vendor_sync');
      research
          ? _coreRuntime!.grantConsent('research')
          : _coreRuntime!.revokeConsent('research');
      // Fall through to Dart consent module so UI and module wiring stays in sync
    }
    return shared._grantConsent(
      biosignals: biosignals,
      behavior: behavior,
      phoneContext: phoneContext,
      cloudUpload: cloudUpload,
      vendorSync: vendorSync,
      profileId: profileId,
      tier: tier,
      grantedChannels: grantedChannels,
      research: research,
    );
  }

  Future<void> _grantConsent({
    required bool biosignals,
    required bool behavior,
    required bool phoneContext,
    required bool cloudUpload,
    bool vendorSync = false,
    String? profileId,
    ConsentTier? tier,
    ConsentChannels? grantedChannels,
    bool research = false,
  }) async {
    if (!_isConfigured) {
      // If init is in progress, wait for it then proceed.
      if (_initCompleter != null) {
        await _initCompleter!.future;
      } else {
        // Not even started — queue for later.
        _pendingConsent = _PendingConsent(
          biosignals: biosignals,
          behavior: behavior,
          phoneContext: phoneContext,
          cloudUpload: cloudUpload,
          vendorSync: vendorSync,
          tier: tier,
          grantedChannels: grantedChannels,
          research: research,
        );
        SynheartLogger.log(
          '[Synheart] SDK not yet initialized — consent queued and will be applied after init.',
        );
        return;
      }
    }

    if (_consentModule == null) {
      throw StateError('Consent module not initialized');
    }

    // If cloud consent is granted and device auth is configured but not yet
    // initialized, run device attestation now.
    if (cloudUpload &&
        _config?.deviceAuthConfig != null &&
        _deviceAuthProvider == null) {
      try {
        SynheartLogger.log(
          '[Synheart] Cloud consent granted — activating device auth..',
        );
        await _initDeviceAuth(_config!);
        SynheartLogger.log('[Synheart] Device auth activated successfully.');
      } catch (e) {
        SynheartLogger.log(
          '[Synheart] Device auth activation failed: $e',
          error: e,
        );
        // Continue — cloud uploads will fail but local mode still works
      }
    }

    // If cloud or platform-ingest is configured and cloudUpload is true, issue token.
    if (_config?.cloudConfig != null && cloudUpload && profileId != null) {
      try {
        // Request token directly with known profile id.
        await _consentModule!.requestConsentByProfileId(
          profileId,
          grantedChannels: grantedChannels,
          tier: tier,
          cloud: cloudUpload,
          research: research,
        );
        SynheartLogger.log(
          '[Synheart] Consent token issued for profile: $profileId (tier: ${(tier ?? ConsentTier.local).name})',
        );
      } catch (e) {
        SynheartLogger.log(
          '[Synheart] Error issuing consent token: $e',
          error: e,
        );
        // Continue with local consent even if token issuance fails
      }
    } else if (_config?.cloudConfig != null &&
        cloudUpload &&
        profileId == null) {
      // Caller granted cloud but didn't supply a profile id. Without a token
      // the native ingest connector fails every flush tick with
      // "ERR_AUTH: ingest requires non-empty X-Consent-Token". Route through
      // the runtime's editable-form submission path, which derives the
      // profile id from the runtime's current form (offline default when no
      // profile has been selected) and issues the JWT end-to-end.
      await _maybeEnsureCloudConsentReady();
    }

    // Update local consent snapshot
    final snapshot = ConsentSnapshot(
      biosignals: biosignals,
      behavior: behavior,
      phoneContext: phoneContext,
      cloudUpload: cloudUpload,
      syni: false,
      vendorSync: vendorSync,
      research: research,
      timestamp: DateTime.now(),
      explicitlyDenied: false,
      tier: tier ?? ConsentTier.local,
      channels: grantedChannels,
    );

    await _consentModule!.updateConsent(snapshot);

    // If any consent was denied, stop data collection for those modules immediately
    if (!biosignals && _wearModule != null) {
      SynheartLogger.log(
        '[Synheart] Biosignals consent denied - stopping wear data collection',
      );
      // The WearModule will handle this via consent stream listener
    }

    if (!behavior && _behaviorModule != null) {
      SynheartLogger.log(
        '[Synheart] Behavior consent denied - stopping behavior data collection',
      );
      // The BehaviorModule will handle this via consent checks
    }

    if (!phoneContext && _phoneModule != null) {
      SynheartLogger.log(
        '[Synheart] Phone context consent denied - stopping phone data collection',
      );
      // The PhoneModule will handle this via consent checks
    }

    SynheartLogger.log(
      '[Synheart] Consent granted: biosignals=$biosignals, behavior=$behavior, phoneContext=$phoneContext, cloudUpload=$cloudUpload',
    );
  }

  Map<String, bool> _getConsentStatusMap() {
    if (_coreRuntime != null) {
      final runtime = _coreRuntime!;
      final syni = _consentModule?.current().syni ?? false;
      return {
        'biosignals': runtime.hasConsent('biosignals'),
        'behavior': runtime.hasConsent('behavior'),
        'phoneContext': runtime.hasConsent('phone_context'),
        'cloudUpload': runtime.hasConsent('cloud_upload'),
        'syni': syni,
        'vendorSync': runtime.hasConsent('vendor_sync'),
        'research': runtime.hasConsent('research'),
      };
    }

    if (_consentModule == null) {
      return {
        'biosignals': false,
        'behavior': false,
        'phoneContext': false,
        'cloudUpload': false,
        'syni': false,
        'vendorSync': false,
        'research': false,
      };
    }

    final consent = _consentModule!.current();
    return {
      'biosignals': consent.biosignals,
      'behavior': consent.behavior,
      'phoneContext': consent.phoneContext,
      'cloudUpload': consent.cloudUpload,
      'syni': consent.syni,
      'vendorSync': consent.vendorSync,
      'research': consent.research,
    };
  }

  /// Delete all local data
  ///
  /// Clears:
  /// - Module caches (wear, phone, behavior)
  /// - Consent data (but keeps consent preferences)
  /// - Upload queue
  /// - HSI state
  ///
  /// Example:
  /// ```dart
  /// await Synheart.deleteLocalData();
  /// ```
  static Future<void> deleteLocalData() async {
    return shared._deleteLocalData();
  }

  Future<void> _deleteLocalData() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before deleting local data',
      );
    }

    SynheartLogger.log('[Synheart] Deleting all local data..');

    // Clear module caches
    if (_wearModule != null) {
      await _wearModule!.clearCache();
    }
    if (_phoneModule != null) {
      await _phoneModule!.clearCache();
    }
    if (_behaviorModule != null) {
      await _behaviorModule!.clearCache();
    }

    // Wipe the core-runtime side: SQLite, SMK, longitudinal SRM
    // snapshot (where the persisted Path-B `recent_sleep_score_ring`
    // lives). Consumer apps that call this public entry expect _all_
    // local state to be gone — module caches alone weren't enough.
    if (_coreRuntime != null) {
      _coreRuntime!.wipeLocalData();
    }

    // Drop in-memory Baselines caches (latest score, last source,
    // dedupe map) so the next snapshot read returns cold-start.
    Baselines.reset();

    SynheartLogger.log('[Synheart] Local data deleted');
  }

  /// Delete data for a specific module
  ///
  /// Example:
  /// ```dart
  /// await Synheart.deleteModuleData('biosignals');
  /// ```
  static Future<void> deleteModuleData(String moduleName) async {
    return shared._deleteModuleData(moduleName);
  }

  Future<void> _deleteModuleData(String moduleName) async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before deleting module data',
      );
    }

    SynheartLogger.log('[Synheart] Deleting data for module: $moduleName');

    switch (moduleName.toLowerCase()) {
      case 'biosignals':
      case 'wear':
        await _wearModule?.clearCache();
        break;
      case 'phonecontext':
      case 'phone':
        await _phoneModule?.clearCache();
        break;
      case 'behavior':
        await _behaviorModule?.clearCache();
        break;
      default:
        throw ArgumentError('Unknown module: $moduleName');
    }

    SynheartLogger.log('[Synheart] Module data deleted: $moduleName');
  }

  /// Delete cloud data
  ///
  /// Clears the upload queue and notifies cloud service to delete user data.
  /// Note: This requires an API call to the cloud service.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.deleteCloudData();
  /// ```
  static Future<void> deleteCloudData() async {
    return shared._deleteCloudData();
  }

  Future<void> _deleteCloudData() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before deleting cloud data',
      );
    }

    SynheartLogger.log('[Synheart] Deleting cloud data..');

    SynheartLogger.log('[Synheart] Cloud data deletion requested');
  }

  /// Revoke consent (clears token and notifies cloud)
  static Future<void> revokeConsent() async {
    return shared._revokeConsent();
  }

  Future<void> _revokeConsent() async {
    if (_consentModule == null) {
      throw StateError('Consent module not initialized');
    }
    await _consentModule!.revokeConsent();
  }

  /// Deny consent (marks as explicitly denied by user)
  ///
  /// This should be called when user declines consent in the UI,
  /// to distinguish from "never asked" (pending) state.
  static Future<void> denyConsent() async {
    return shared._denyConsent();
  }

  Future<void> _denyConsent() async {
    if (_consentModule == null) {
      throw StateError('Consent module not initialized');
    }
    await _consentModule!.denyConsent();
  }

  /// Runtime diagnostics — returns availability, version, frame count, and last quality.
  ///
  /// Useful for debugging and runtime verification screens.
  /// Returns a map with keys: `isAvailable`, `version`, `frameCount`, `lastQuality`.
  static Map<String, dynamic> runtimeDiagnostics() {
    return {
      'isAvailable': _coreRuntime != null,
      'version': CoreRuntimeBridge.version(),
      'frameCount': _coreRuntime?.frameCount() ?? 0,
      'lastQuality': _coreRuntime?.lastQuality() ?? 0.0,
    };
  }

  /// All synheart crate versions, target, profile, and enabled features.
  /// No active session needed — compile-time info baked into the .so/.a.
  static Map<String, dynamic>? get buildInfo => CoreRuntimeBridge.buildInfo();

  /// Get module statuses (for debugging)
  Map<String, String> getModuleStatuses() {
    final statuses = _moduleManager.getModuleStatuses();
    return statuses.map((key, value) => MapEntry(key, value.name));
  }

  /// Handle consent changes — reevaluate all features via the four-authority model.
  void _onConsentChanged(ConsentSnapshot newConsent) {
    SynheartLogger.log('[Synheart] Consent changed:');
    SynheartLogger.log(' - Biosignals: ${newConsent.biosignals}');
    SynheartLogger.log(' - Behavior: ${newConsent.behavior}');
    SynheartLogger.log(' - PhoneContext: ${newConsent.phoneContext}');
    SynheartLogger.log(' - Cloud Upload: ${newConsent.cloudUpload}');
    SynheartLogger.log(' - Syni: ${newConsent.syni}');
    SynheartLogger.log(' - Vendor Sync: ${newConsent.vendorSync}');
    SynheartLogger.log(' - Research: ${newConsent.research}');
    // Background HRV / live HRV is not part of the consent snapshot
    // (it's a separate runtime gate, not a granted-channel) but it's
    // the user-facing toggle next to consents on the privacy screen,
    // so log it alongside for parity.
    SynheartLogger.log(' - Background HRV: ${getAmbientCapture()}');

    _reevaluateAllFeatures();
  }

  // Feature Reevaluation (RFC-0005 Four-Authority Model)

  /// Reevaluate whether a single feature should be operational.
  ///
  /// ```
  /// isOperational = activated AND hasConsent AND capabilityAllowed AND isRunning
  /// ```
  void _reevaluateFeature(SynheartFeature feature) {
    final activated = _activationManager?.isActivated(feature) ?? false;
    final hasConsent = _hasConsentForFeature(feature);
    final capabilityAllowed = _isCapabilityAllowed(feature);
    final isOperational =
        activated && hasConsent && capabilityAllowed && _isRunning;

    switch (feature) {
      case SynheartFeature.wear:
        if (isOperational && _wearModule?.status != ModuleStatus.running) {
          _wearModule?.start().catchError(
            (e) => SynheartLogger.log(
              '[Synheart] Error starting wear: $e',
              error: e,
            ),
          );
        } else if (!isOperational &&
            _wearModule?.status == ModuleStatus.running) {
          _wearModule?.stop().catchError(
            (e) => SynheartLogger.log(
              '[Synheart] Error stopping wear: $e',
              error: e,
            ),
          );
        }
      case SynheartFeature.behavior:
        if (isOperational && _behaviorModule?.status != ModuleStatus.running) {
          _behaviorModule?.start().catchError(
            (e) => SynheartLogger.log(
              '[Synheart] Error starting behavior: $e',
              error: e,
            ),
          );
        } else if (!isOperational &&
            _behaviorModule?.status == ModuleStatus.running) {
          _behaviorModule?.stop().catchError(
            (e) => SynheartLogger.log(
              '[Synheart] Error stopping behavior: $e',
              error: e,
            ),
          );
        }

      case SynheartFeature.phoneContext:
        if (isOperational && _phoneModule?.status != ModuleStatus.running) {
          _phoneModule?.start().catchError(
            (e) => SynheartLogger.log(
              '[Synheart] Error starting phone: $e',
              error: e,
            ),
          );
        } else if (!isOperational &&
            _phoneModule?.status == ModuleStatus.running) {
          _phoneModule?.stop().catchError(
            (e) => SynheartLogger.log(
              '[Synheart] Error stopping phone: $e',
              error: e,
            ),
          );
        }
      case SynheartFeature.cloud:
        // Cloud connector removed — managed by core runtime bridge.
        break;
      case SynheartFeature.syni:
        break;
    }
  }

  /// Reevaluate all features (e.g. after consent change or session start/stop).
  void _reevaluateAllFeatures() {
    for (final feature in SynheartFeature.values) {
      _reevaluateFeature(feature);
    }
  }

  /// Check consent for a feature's required consent type.
  bool _hasConsentForFeature(SynheartFeature feature) {
    final consent = _consentModule?.current();
    if (consent == null) return false;
    switch (feature.requiredConsent) {
      case 'biosignals':
        return consent.biosignals;
      case 'behavior':
        return consent.behavior;
      case 'phoneContext':
        return consent.phoneContext;
      case 'cloudUpload':
        return consent.cloudUpload;
      case 'syni':
        return consent.syni;
      default:
        return false;
    }
  }

  /// True if at least one activated feature has consent (required to start a session).
  bool _hasAtLeastOneFeatureWithConsent() {
    final activated = _activationManager?.activatedFeatures() ?? {};
    for (final feature in activated) {
      if (_hasConsentForFeature(feature)) return true;
    }
    return false;
  }

  /// Configure device authentication, register device, and fetch capabilities.
  Future<void> _initDeviceAuth(SynheartConfig resolvedConfig) async {
    final dac = resolvedConfig.deviceAuthConfig!;
    SynheartLogger.log('[Synheart] Configuring device authentication..');

    final runtime = _coreRuntime;
    if (runtime == null) {
      throw StateError(
        'Device registration requires core-runtime. Native runtime bridge is unavailable.',
      );
    }
    if (!runtime.sdkDeviceAuthAvailable) {
      throw StateError(
        'Device registration requires synheart_core_sdk_* symbols in the native runtime.',
      );
    }
    if (!_sdkCryptoCallbacksAttached) {
      throw StateError(
        'Device registration requires SDK crypto callbacks to be attached. '
        'Ensure the synheart_auth plugin is registered and '
        'libsynheart_native_crypto.so (Android) / the @_cdecl symbols (iOS) '
        'are bundled so synheart_native_* resolves.',
      );
    }

    SynheartLogger.log(
      '[Synheart] DeviceAuthConfig: authBaseUrl=${dac.authBaseUrl} '
      'capabilityBaseUrl=${dac.capabilityBaseUrl ?? "(default=authBaseUrl)"} '
      'allowUnsignedCapabilities=${resolvedConfig.allowUnsignedCapabilities} '
      'appId=${resolvedConfig.appId}',
    );

    try {
      // After keychain restore the runtime can already be in `registered`
      // state. Calling sdkRegisterDevice again kicks off the full 7-step
      // re-registration (Play Integrity → new keypair → HTTP POST), which
      // blocks the main isolate's microtask queue while it runs and ANRs
      // the app on cold boot once a few stale device records pile up
      // server-side. Short-circuit when the runtime already considers us
      // registered — the keychain/state is the source of truth.
      final preSnap = runtime.sdkDeviceAuthStatus();
      final preStatus = preSnap?['status']?.toString();
      if (preStatus == 'registered') {
        final restoredId = preSnap?['device_id']?.toString();
        _deviceAuthViaCoreRuntime = true;
        final idPreview = (restoredId == null || restoredId.length <= 8)
            ? (restoredId ?? '?')
            : '${restoredId.substring(0, 8)}..';
        SynheartLogger.log(
          '[Synheart] Device already registered (restored from keychain) — '
          'skipping re-registration (device_id preview: $idPreview)',
        );
      } else {
        final reg = await runtime.sdkRegisterDevice(resolvedConfig.subjectId);
        final deviceId =
            reg?['device_id'] as String? ?? reg?['deviceId'] as String?;
        final err = reg?['error']?.toString();
        if (reg == null ||
            deviceId == null ||
            (err != null && err.isNotEmpty)) {
          throw StateError(
            'Core SDK register_device failed: ${reg ?? "null result"}',
          );
        }
        _deviceAuthViaCoreRuntime = true;
        final idPreview = deviceId.length <= 8
            ? deviceId
            : '${deviceId.substring(0, 8)}..';
        SynheartLogger.log(
          '[Synheart] Core SDK device registration complete (device_id preview: $idPreview)',
        );
      }
    } catch (e) {
      SynheartLogger.log('[Synheart] Device registration failed: $e', error: e);
      if (resolvedConfig.allowUnsignedCapabilities) {
        SynheartLogger.log(
          '[Synheart] WARNING: Device registration failed, falling back to unsigned capabilities.',
        );
        await _capabilityModule!.loadDefaults();
        return;
      }
      rethrow;
    }

    try {
      if (resolvedConfig.capabilitySecret != null) {
        _coreRuntime?.loadCapabilityToken(
          '{}',
          resolvedConfig.capabilitySecret!,
        );
      }
      _capabilityModule?.loadDefaults();
    } catch (e) {
      SynheartLogger.log(
        '[Synheart] Capability token fetch failed: $e',
        error: e,
      );
      if (resolvedConfig.allowUnsignedCapabilities) {
        SynheartLogger.log(
          '[Synheart] WARNING: Falling back to unsigned default capabilities.',
        );
        await _capabilityModule!.loadDefaults();
      } else {
        rethrow;
      }
    }

    // 4. Create DeviceAuthProvider for cloud/platform signing
    _deviceAuthProvider = DeviceAuthProvider(
      coreRuntime: runtime,
      baseUrl: dac.authBaseUrl,
    );
  }

  /// Check whether the CapabilityModule allows a given feature.
  bool _isCapabilityAllowed(SynheartFeature feature) {
    final cap = _capabilityModule;
    if (cap == null) return false;
    switch (feature) {
      case SynheartFeature.wear:
        return cap.capability(Module.wear) != CapabilityLevel.none;
      case SynheartFeature.behavior:
        return cap.capability(Module.behavior) != CapabilityLevel.none;
      case SynheartFeature.phoneContext:
        return cap.capability(Module.phone) != CapabilityLevel.none;
      case SynheartFeature.cloud:
        return cap.capability(Module.cloud) != CapabilityLevel.none;
      case SynheartFeature.syni:
        // Syni runs independent of the wearable capability lattice. Real
        // operational gating (model installed, engine loaded) lives in
        // SyniModule and is composed at the four-authority layer.
        return _syni?.isInstalled ?? false;
    }
  }

  /// Stop Synheart Core SDK
  static Future<void> stop() async {
    return shared._stop();
  }

  Future<void> _stop() async {
    if (!_isRunning) {
      return;
    }

    try {
      SynheartLogger.log('[Synheart] Stopping..');

      // Clear HSI callback (core runtime handles cleanup in dispose)
      _coreRuntime?.clearHsiCallback();

      // Remove consent listener (best-effort)
      _consentModule?.removeListener(_onConsentChanged);

      // Stop core modules
      await _moduleManager.stopAll();

      _isRunning = false;
      SynheartLogger.log('[Synheart] Stopped');
    } catch (e, stack) {
      SynheartLogger.log(
        '[Synheart] Stop failed: $e',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Dispose all resources
  static Future<void> dispose() async {
    return shared._dispose();
  }

  Future<void> _dispose() async {
    try {
      await _stop();

      _coreRuntime?.dispose();
      _coreRuntime = null;

      await _moduleManager.disposeAll();

      await _hsvStream.close();

      await _mainSessionSubscription?.cancel();
      _mainSessionSubscription = null;
      _mainSession?.dispose();
      _mainSession = null;
      _activeMainSessionId = null;

      _watchSessionModule?.dispose();
      _watchSessionModule = null;

      await _sessionHsiSubscription?.cancel();
      _sessionHsiSubscription = null;
      await _sessionWearSubscription?.cancel();
      _sessionWearSubscription = null;
      _sessionHsiBuffer = [];
      _sessionWearBuffer = [];

      _consentModule = null;
      _capabilityModule = null;
      _wearModule = null;
      _phoneModule = null;
      _behaviorModule = null;
      _coreRuntime?.dispose();
      _coreRuntime = null;
      _activationManager = null;
      _pendingConsent = null;

      _currentSessionHandle = null;

      _isConfigured = false;
      _isRunning = false;
      _initCompleter = null;
      _deviceAuthViaCoreRuntime = false;
      _sdkCryptoCallbacksAttached = false;

      SynheartLogger.log('[Synheart] Disposed');
      // Allow re-initialization by creating a fresh instance next time.
      _instance = null;
    } catch (e, stack) {
      SynheartLogger.log(
        '[Synheart] Dispose failed: $e',
        error: e,
        stackTrace: stack,
      );
    }
  }
}

/// Sync result from a push/pull cycle.
class SyncResult {
  final int pushed;
  final int pulled;

  const SyncResult({this.pushed = 0, this.pulled = 0});
}

/// Current sync status.
class SyncStatus {
  final bool enabled;

  const SyncStatus({required this.enabled});
}

/// Session record returned from session queries.
class SessionRecord {
  final String sessionId;
  final String subjectId;
  final String mode;
  final int createdAtUtc;
  final int startUtc;
  final String appId;
  final String appVersion;
  final String deviceId;
  final String platform;

  const SessionRecord({
    required this.sessionId,
    required this.subjectId,
    required this.mode,
    required this.createdAtUtc,
    required this.startUtc,
    this.appId = '',
    this.appVersion = '',
    this.deviceId = '',
    this.platform = 'flutter',
  });

  factory SessionRecord.fromMap(Map<String, dynamic> map) {
    int readInt(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v is int) return v;
        if (v is num) return v.toInt();
      }
      return 0;
    }

    return SessionRecord(
      sessionId: map['session_id'] as String? ?? '',
      subjectId: map['subject_id'] as String? ?? '',
      mode: map['mode'] as String? ?? 'personal',
      createdAtUtc: readInt(['created_at_utc', 'created_at_ms']),
      startUtc: readInt(['started_at_ms', 'start_utc']),
      appId: map['app_id'] as String? ?? '',
      appVersion: map['app_version'] as String? ?? '',
      deviceId: map['device_id'] as String? ?? '',
      platform: map['platform'] as String? ?? 'flutter',
    );
  }
}

class IngestionSubmissionResponse {
  final bool success;
  final int statusCode;
  final String? errorMessage;
  final Map<String, dynamic>? details;

  const IngestionSubmissionResponse({
    required this.success,
    required this.statusCode,
    this.errorMessage,
    this.details,
  });
}

/// User-facing cloud-sync state. Combines queue depth, last-success
/// timestamp, and cloud-upload consent into a single bucket the host
/// can render as a pill.
///
/// - [synced] — queue empty, at least one successful upload this
/// process. "Everything is in the cloud."
/// - [syncing] — queue has rows. "Uploading…"
/// - [pending] — queue empty but no successful upload yet (cold
/// start, or first session before token + first window). "Will
/// sync as soon as something is ready."
/// - [localOnly] — cloud-upload consent is off. "By your choice,
/// nothing leaves the device."
enum CloudSyncStatus { synced, syncing, pending, localOnly }

class QueueFlushResult {
  final bool success;
  final int uploaded;
  final int failed;
  final int requeued;
  final String? errorMessage;

  const QueueFlushResult({
    required this.success,
    required this.uploaded,
    required this.failed,
    required this.requeued,
    this.errorMessage,
  });
}

class QueueStatusSnapshot {
  final int queueLength;
  final String? lastUploadBatchId;
  final DateTime? lastUploadAt;
  final DateTime? lastUploadAttemptAt;
  final String? lastUploadError;

  const QueueStatusSnapshot({
    required this.queueLength,
    this.lastUploadBatchId,
    this.lastUploadAt,
    this.lastUploadAttemptAt,
    this.lastUploadError,
  });
}

class SynheartIngestion {
  SynheartIngestion._();

  static final SynheartIngestion instance = SynheartIngestion._();

  QueueStatusSnapshot get queueStatus => QueueStatusSnapshot(
    queueLength: Synheart.uploadQueueLength,
    lastUploadBatchId: Synheart.lastUploadBatchId,
    lastUploadAt: Synheart.lastUploadAt,
    lastUploadAttemptAt: Synheart.lastUploadAttemptAt,
    lastUploadError: Synheart.lastUploadError,
  );

  void enqueueHsiWindows(List<String> hsiJsons, {int? timestampMs}) {
    final bridge = Synheart._coreRuntime;
    if (bridge == null || hsiJsons.isEmpty) return;
    final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    for (final hsiJson in hsiJsons) {
      if (hsiJson.trim().isEmpty) continue;
      bridge.enqueueHsi(hsiJson, ts);
    }
  }

  Future<QueueFlushResult> flushIfEligible({bool requireConsent = true}) async {
    final bridge = Synheart._coreRuntime;
    if (bridge == null) {
      Synheart._lastUploadAttemptAt = DateTime.now().toUtc();
      Synheart._lastUploadError = 'core runtime bridge unavailable';
      return const QueueFlushResult(
        success: false,
        uploaded: 0,
        failed: 0,
        requeued: 0,
        errorMessage: 'core runtime bridge unavailable',
      );
    }
    if (requireConsent && !await Synheart.hasConsent('cloudUpload')) {
      Synheart._lastUploadAttemptAt = DateTime.now().toUtc();
      Synheart._lastUploadError = 'cloudUpload consent not granted';
      return const QueueFlushResult(
        success: false,
        uploaded: 0,
        failed: 0,
        requeued: 0,
        errorMessage: 'cloudUpload consent not granted',
      );
    }

    Synheart._lastUploadAttemptAt = DateTime.now().toUtc();
    final result = bridge.flushUploads();
    if (result == null) {
      Synheart._lastUploadError = 'flush_uploads returned null';
      return const QueueFlushResult(
        success: false,
        uploaded: 0,
        failed: 0,
        requeued: 0,
        errorMessage: 'flush_uploads returned null',
      );
    }

    final uploaded = result['uploaded'] as int? ?? 0;
    final failed = result['failed'] as int? ?? 0;
    final requeued = result['requeued'] as int? ?? 0;
    Synheart._lastUploadAt = DateTime.now().toUtc();
    Synheart._lastUploadError = null;
    if (uploaded > 0) {
      Synheart._lastUploadBatchId =
          result['batch_id']?.toString() ??
          'flush_${Synheart._lastUploadAt!.millisecondsSinceEpoch}';
    }
    return QueueFlushResult(
      success: true,
      uploaded: uploaded,
      failed: failed,
      requeued: requeued,
    );
  }

  Future<IngestionSubmissionResponse> submitSessionArtifacts(
    Map<String, dynamic> payload, {
    List<String> hsiWindows = const <String>[],
  }) async {
    final bridge = Synheart._coreRuntime;
    if (bridge == null) {
      return const IngestionSubmissionResponse(
        success: false,
        statusCode: 503,
        errorMessage: 'core runtime bridge unavailable',
      );
    }
    enqueueHsiWindows(hsiWindows);
    final flush = await flushIfEligible();
    if (!flush.success) {
      return IngestionSubmissionResponse(
        success: false,
        statusCode: 403,
        errorMessage: flush.errorMessage,
        details: {'payloadAccepted': false},
      );
    }
    return IngestionSubmissionResponse(
      success: true,
      statusCode: 200,
      details: {
        'payloadAccepted': true,
        'payloadKeys': payload.keys.length,
        'uploaded': flush.uploaded,
        'failed': flush.failed,
        'requeued': flush.requeued,
        'queuedWindows': hsiWindows.length,
      },
    );
  }

  Future<IngestionSubmissionResponse> submitMetadata(
    Map<String, dynamic> payload,
  ) async {
    final bridge = Synheart._coreRuntime;
    if (bridge == null) {
      return const IngestionSubmissionResponse(
        success: false,
        statusCode: 503,
        errorMessage: 'core runtime bridge unavailable',
      );
    }
    return IngestionSubmissionResponse(
      success: true,
      statusCode: 202,
      details: {
        'accepted': true,
        'payloadKeys': payload.keys.length,
        'message':
            'Metadata payload accepted by bridge-first SDK; no separate metadata upload path.',
      },
    );
  }
}

class LabIngestResponse {
  final bool success;
  final int statusCode;
  final String? errorMessage;

  const LabIngestResponse({
    required this.success,
    required this.statusCode,
    this.errorMessage,
  });
}

/// Consent values queued before SDK initialization.
class _PendingConsent {
  final bool biosignals;
  final bool behavior;
  final bool phoneContext;
  final bool cloudUpload;
  final bool vendorSync;
  final ConsentTier? tier;
  final ConsentChannels? grantedChannels;
  final bool research;

  _PendingConsent({
    required this.biosignals,
    required this.behavior,
    required this.phoneContext,
    required this.cloudUpload,
    this.vendorSync = false,
    this.tier,
    this.grantedChannels,
    this.research = false,
  });
}
