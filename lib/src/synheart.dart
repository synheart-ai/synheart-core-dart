import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'config/api_endpoints.dart';
import 'config/synheart_config.dart';
import 'core/logger.dart';
import 'modules/base/module_manager.dart';
import 'modules/base/synheart_module.dart';
import 'modules/capabilities/capability_module.dart';
import 'modules/consent/consent_module.dart';
import 'modules/interfaces/capability_provider.dart';
import 'modules/interfaces/consent_provider.dart';
import 'modules/wear/wear_module.dart';
import 'modules/wear/wear_source_handler.dart';
import 'modules/phone/phone_module.dart';
import 'modules/behavior/behavior_module.dart';
import 'modules/behavior/behavior_events.dart';
import 'modules/interfaces/feature_providers.dart';
import 'models/behavior_session_results.dart';
import 'package:synheart_behavior/synheart_behavior.dart' as sb;
import 'config/synheart_mode.dart';
import 'models/session_handle.dart';
import 'models/hsi_state.dart';
import 'models/metric_event.dart';
import 'config/synheart_feature.dart';
import 'config/activation_manager.dart';
import 'package:synheart_auth/synheart_auth.dart';
import 'modules/cloud/device_auth_provider.dart';
import 'core_runtime/core_runtime_bridge.dart';
import 'modules/consent/consent_profile.dart';
import 'modules/consent/consent_token.dart';
import 'modules/consent/consent_ui.dart';
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
///   userId: 'anon_user_123',
/// );
///
/// // Subscribe to HSI updates (core state representation)
/// Synheart.onHSIUpdate.listen((hsi) {
///   print('HSI JSON: $hsi');
/// });
///
/// // Enable cloud upload (with consent)
/// Synheart.activate(SynheartFeature.cloud);
/// ```
class Synheart {
  static Synheart? _instance;
  static Synheart get shared => _instance ??= Synheart._();

  /// Rust core runtime bridge (FFI). Null when native lib unavailable.
  static CoreRuntimeBridge? _coreRuntime;

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

  // --- Phase 2: Typed state subscription ---

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

  // --- Phase 2: Metrics API ---

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

  // --- Phase 2: Local Query API ---

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
  static Future<List<Map<String, dynamic>>> getHSIWindows(
    String sessionId, {
    WindowRange? range,
  }) async {
    if (_coreRuntime != null) {
      final raw = _coreRuntime!.getHsiWindows(
        sessionId,
        startMs: range?.startMs ?? 0,
        endMs: range?.endMs ?? 0,
        limit: range?.limit ?? 0,
      );
      if (raw != null) {
        return raw.cast<Map<String, dynamic>>();
      }
    }
    return [];
  }

  // --- Phase 2: Storage & Retention ---

  /// Get storage usage statistics.
  static Future<StorageUsage> getStorageUsage() async {
    if (_coreRuntime != null) {
      final result = _coreRuntime!.getStorageUsage();
      if (result != null) {
        return StorageUsage(
          totalBytes: result['total_bytes'] as int? ?? 0,
          bySessionBytes: (result['by_session_bytes'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ?? {},
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

  // --- Phase 2: Deletion API ---

  /// Delete a session and all its artifacts locally.
  /// Creates tombstones for future sync propagation.
  static Future<void> deleteLocalSession(String sessionId) async {
    if (_coreRuntime != null) {
      _coreRuntime!.deleteSession(sessionId);
      return;
    }
  }

  /// Wipe all local data: SQLite, SMK, and reset state.
  static Future<void> wipeLocalData() async {
    if (_coreRuntime != null) {
      _coreRuntime!.wipeLocalData();
      shared._currentSessionHandle = null;
      shared._isRunning = false;
      return;
    }
    // Stop if running
    if (shared._isRunning) {
      await shared._stopDataCollection();
    }

    shared._currentSessionHandle = null;
  }

  /// Request account deletion — wipes local data and requests server-side deletion.
  static Future<DeletionRequestResult> requestAccountDeletion() async {
    if (_coreRuntime != null) {
      final ok = _coreRuntime!.requestAccountDeletion();
      return DeletionRequestResult(
        status: ok ? 'accepted' : 'error',
        message: ok
            ? 'Account deletion requested via core runtime.'
            : 'Account deletion request failed.',
      );
    }
    final token = shared._consentModule?.getCurrentToken();
    if (token != null && token.isValid) {
      try {
        await http.post(
          shared._buildAccountApiUri(ApiEndpoints.accountDeletePath),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.token}',
          },
          body: jsonEncode({'confirmation': 'DELETE_MY_ACCOUNT'}),
        );
      } catch (_) {
        // Server deletion request failed — still wipe locally
      }
    }

    await wipeLocalData();
    return const DeletionRequestResult(
      status: 'accepted',
      message: 'Local data wiped. Server deletion pending.',
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
    final token = shared._consentModule?.getCurrentToken();
    if (token == null || !token.isValid) {
      return const DeletionRequestResult(
        status: 'error',
        message: 'No valid consent token',
      );
    }

    try {
      final response = await http.post(
        shared._buildAccountApiUri(ApiEndpoints.accountDeleteCancelPath),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token.token}',
        },
      );

      if (response.statusCode == 200) {
        return const DeletionRequestResult(
          status: 'cancelled',
          message: 'Account deletion cancelled.',
        );
      }

      return DeletionRequestResult(
        status: 'error',
        message: 'Cancel failed: ${response.statusCode}',
      );
    } catch (e) {
      return DeletionRequestResult(
        status: 'error',
        message: 'Cancel failed: $e',
      );
    }
  }

  // --- Phase 3: Auth ---

  /// Log out — revoke consent.
  static Future<void> logout() async {
    if (_coreRuntime != null) {
      _coreRuntime!.wipeLocalData();
    }
    try { await shared._consentModule?.revokeConsent(); } catch (_) {}
  }

  // --- Phase 3: Sync API ---

  /// Enable or disable sync.
  static Future<void> setSyncEnabled(bool enabled) async {
    if (_coreRuntime != null) {
      _coreRuntime!.setSyncEnabled(enabled);
      return;
    }
  }

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
  ///   userId: 'anon_user_123',
  /// );
  /// ```
  ///
  /// To initialize and then start a session:
  /// ```dart
  /// await Synheart.initialize(
  ///   userId: 'anon_user_123',
  /// );
  /// await Synheart.startSession(); // Start when ready
  /// ```
  /// Whether the SDK has been initialized via [initialize] or [configure].
  static bool get isInitialized => shared._isConfigured;

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
  }) async {
    if (config != null) {
      config.validate();
    }
    return shared._configure(
      appKey: config?.appId ?? 'default',
      userId: userId ?? config?.subjectId ?? '',
      config: config,
      autoStart: autoStart,
    );
  }

  Future<void> _configure({
    required String appKey,
    required String userId,
    SynheartConfig? config,
    bool autoStart = false,
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

    // Initialize Rust core runtime bridge (best-effort; null if native lib absent)
    try {
      final resolvedCfg = _config!;
      _coreRuntime = CoreRuntimeBridge.create({
        'app_id': resolvedCfg.appId,
        'subject_id': resolvedCfg.subjectId,
        'mode': resolvedCfg.mode.name,
        'device_id': resolvedCfg.deviceId ?? '',
        'app_version': resolvedCfg.appVersion ?? '0.0.0',
        'platform': 'flutter',
        'storage': {'enabled': resolvedCfg.storage.enabled},
        'sync': {
          'enabled': resolvedCfg.sync.enabled,
          'base_url': resolvedCfg.sync.baseUrl,
        },
        'privacy': {'allow_research': resolvedCfg.privacy.allowResearch},
      });
      if (_coreRuntime != null) {
        SynheartLogger.log('[Synheart] Rust core runtime bridge loaded');
      }
    } catch (e) {
      SynheartLogger.log('[Synheart] Rust core runtime bridge unavailable: $e');
      _coreRuntime = null;
    }

    try {
      SynheartLogger.log('[Synheart] Initializing capability module...');
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

      SynheartLogger.log('[Synheart] Initializing consent module...');
      _consentModule = ConsentModule(consentConfig: _config?.consentConfig);

      // Wire device signing into consent module so all consent-token requests
      // are signed with device identity (X-Synheart-* headers).
      // Uses lazy binding — resolves _deviceAuthProvider at call time.
      _consentModule!.setDeviceSigner(
        ({required String method, required String path, required List<int> bodyBytes}) async {
          if (_deviceAuthProvider == null) return <String, String>{};
          return await _deviceAuthProvider!.signRequest(
            method: method,
            path: path,
            bodyBytes: Uint8List.fromList(bodyBytes),
          );
        },
      );

      _moduleManager.registerModule(_capabilityModule!);
      _moduleManager.registerModule(_consentModule!);

      SynheartLogger.log('[Synheart] Initializing data modules...');
      _wearModule = WearModule(
        capabilities: _capabilityModule!,
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
        capabilities: _capabilityModule!,
        consent: _consentModule!,
        enableMotionLite: _config?.behaviorConfig?.enableMotionLite ?? false,
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

      SynheartLogger.log('[Synheart] Initializing Runtime...');
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
          '[Synheart] Core runtime bridge loaded. isLabAvailable=${_coreRuntime!.isLabAvailable} '
          '(Lab requires synheart-engine built with: cargo build --release --features lab)',
        );
      }

      // Wire wearable event processor for vendor sync (RAMEN → pipeline)
      _wearModule!.setEventProcessor(WearableEventProcessor(
        bridge: _coreRuntime,
        subjectId: runtimeSubjectId,
        deviceInstallId: runtimeSessionId,
      ));

      // Push all behavior events (notification, app_switch, touch, etc.) to the runtime
      if (_coreRuntime != null) {
        _behaviorModule!.pushBehaviorToRuntime =
            (int tsMs, int eventType, double value) {
              _coreRuntime?.pushBehavior(tsMs, eventType, value);
            };
      }

      _watchSessionModule = WatchSessionModule();
      _watchSessionModule!.initialize();

      _mainSession = SynheartSession();

      SynheartLogger.log('[Synheart] Initializing all modules...');
      await _moduleManager.initializeAll();

      _consentModule!.addListener(_onConsentChanged);

      // Wire HSI callback from core runtime → _hsvStream + session engine
      if (_coreRuntime != null) {
        _coreRuntime!.setHsiCallback((hsiJson) {
          final consent = _consentModule?.current();
          if (consent == null || !consent.biosignals) return;
          _hsvStream.add(hsiJson);

          // Bridge HSI metrics from runtime → session engine
          final sid = _activeMainSessionId;
          if (sid == null || _mainSession == null) return;
          try {
            final parsed = jsonDecode(hsiJson) as Map<String, dynamic>;
            _mainSession!.ingestHsiMetrics(sid, parsed);
          } catch (_) {}
        });
      }

      _activationManager = ActivationManager();
      _activationManager!.activateFromConfig(resolvedConfig);

      // Phase 3: Initialize auth
      final appId = resolvedConfig.appId;
      if (appId.isNotEmpty) {
        // Configure synheart-auth for device attestation + signing.
        final authBaseUrl = resolvedConfig.deviceAuthConfig?.authBaseUrl
            ?? 'https://auth.synheart.ai';
        try {
          await SynheartAuth.instance.configure(authBaseUrl);
        } catch (e) {
          SynheartLogger.log('[Synheart] SynheartAuth configure failed (non-fatal): $e');
        }
      }

      if (autoStart) {
        SynheartLogger.log('[Synheart] Starting all modules...');
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
        SynheartLogger.log('[Synheart] Applying pending consent...');
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
      final result = _coreRuntime!.startSession();
      if (result != null) {
        shared._currentSessionHandle = SessionHandle(
          sessionId: result['session_id'] as String,
          startedAtMs: result['started_at_ms'] as int,
          mode: shared._config?.mode ?? SynheartMode.personal,
        );
        shared._isRunning = true;
        return shared._currentSessionHandle;
      }
    }
    await shared._startDataCollection(durationSec: durationSec);
    return shared._currentSessionHandle;
  }

  /// Whether the main data-collection session is currently running.
  static bool get isSessionRunning => shared._isRunning;

  /// Stop the current session — halts module streaming and clears ephemeral buffers.
  ///
  /// Per RFC §5.2: Core must halt module streaming, stop synheart-engine updates,
  /// clear ephemeral buffers, and prevent further HSI export.
  static Future<void> stopSession() async {
    if (_coreRuntime != null) {
      _coreRuntime!.stopSession();
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
  /// Returns false if behavior module or synheart_behavior is not initialized.
  static Future<bool> checkNotificationListenerEnabled() async {
    final sb = shared._behaviorModule?.synheartBehavior;
    if (sb == null) return false;
    return sb.checkNotificationPermission();
  }

  /// Open system settings where the user can enable notification access.
  /// On Android: Notification listener access (Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).
  /// On iOS: Opens app settings. Call after behavior collection is started.
  static Future<void> openNotificationListenerSettings() async {
    final sb = shared._behaviorModule?.synheartBehavior;
    if (sb == null) return;
    await sb.requestNotificationPermission();
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
  ///   print('Watch is reachable');
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
  ///   SessionConfig(
  ///     mode: SessionMode.focus,
  ///     durationSec: 300,
  ///     profile: ComputeProfile(windowSec: 60, emitIntervalSec: 5),
  ///   ),
  /// );
  /// stream.listen((event) {
  ///   if (event is SessionFrame) {
  ///     print('HR: ${event.metrics['hr_mean_bpm']}');
  ///   }
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
  ///   print('HR: ${sample.hr} BPM');
  ///   print('RR Intervals: ${sample.rrIntervals}');
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
  ///   print('Event: ${event.type} at ${event.timestamp}');
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
  /// // ... user interacts with app ...
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
  static int get uploadQueueLength => 0;

  /// Batch id from the last successful cloud ingest (null if none yet).
  static String? get lastUploadBatchId => null;

  /// Time of the last successful cloud ingest (null if none yet).
  static DateTime? get lastUploadAt => null;

  /// Last upload error message (null when last attempt succeeded or no attempt yet).
  static String? get lastUploadError => null;

  /// Time of the last upload attempt (success or failure); null if no attempt yet.
  static DateTime? get lastUploadAttemptAt => null;

  /// Force-upload queued HSI snapshots through Cloud Connector now.
  ///
  /// No-op if Cloud Connector is not configured.
  static Future<void> uploadHsiNow() async {
    return shared._uploadHsiNow();
  }

  /// Enqueue raw HSI JSON strings collected externally (e.g. persisted from a
  /// foreground session) so they are included in the next [uploadHsiNow] call.
  ///
  /// No-op if Cloud Connector is not configured or list is empty.
  static Future<void> enqueueHsiSnapshots(List<String> hsiJsons) async {
    return shared._enqueueHsiSnapshots(hsiJsons);
  }

  // ── Lab Ingest API ──────────────────────────────────────────

  /// Ingest a session payload via the lab ingestion service.
  /// Requires `behavior` consent. Returns a [LabIngestResponse].
  static Future<LabIngestResponse> ingestSession(
    Map<String, dynamic> payload,
  ) async {
    return const LabIngestResponse(
      success: false,
      statusCode: 0,
      errorMessage: 'LabIngestModule removed — use core runtime bridge',
    );
  }

  /// Ingest a metadata payload via the lab ingestion service.
  /// Requires `biosignals` consent. Returns a [LabIngestResponse].
  static Future<LabIngestResponse> ingestMetadata(
    Map<String, dynamic> payload,
  ) async {
    return const LabIngestResponse(
      success: false,
      statusCode: 0,
      errorMessage: 'LabIngestModule removed — use core runtime bridge',
    );
  }

  Future<void> _uploadHsiNow() async {
    // Cloud connector removed — no-op.
  }

  Future<void> _enqueueHsiSnapshots(List<String> hsiJsons) async {
    // Cloud connector removed — no-op.
  }

  /// Build and ingest a platform session payload from internal SDK data.
  Future<void> _autoIngestSession(SessionHandle session) async {
    // No-op: lab ingest module removed.
  }

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
      case 'vendorSync':
        return consent.vendorSync;
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
      focusEstimation: false,
      emotionEstimation: false,
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
    _coreRuntime?.pushBehavior(tsMs, 2, 1.0);
  }

  /// Push a notification-received behavior event into the runtime for the given timestamp (ms since epoch).
  /// Call when the app displays or receives a notification so behavioral_metrics include notification counts.
  /// No-op if runtime or bridge is unavailable.
  static void pushBehaviorNotificationReceived(int tsMs) {
    _coreRuntime?.pushBehavior(tsMs, 4, 1.0);
  }

  /// Push a wear HR event into runtime and optionally synthesize RR.
  /// Use when HR is coming from external/watch channels not wired to WearModule.
  static void pushWearHr(int tsMs, double bpm) {
    _coreRuntime?.pushHr(tsMs, bpm);
  }

  static void pushRr(int tsMs, double rrMs) {
    _coreRuntime?.pushRr(tsMs, rrMs);
  }

  /// Last preprocessed features from the engine (HRV, motion, quality, SRM context).
  static String? get lastFeatures => _coreRuntime?.lastFeatures();

  // ── synheart-engine SRM API (baselines live in the native Rust engine) ──

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
  static bool get isLabAvailable =>
      _coreRuntime?.isLabAvailable ?? false;

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
      parentId, windowType, label, startedAtMs,
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

  /// Flush buffered behavior/wear events to the native runtime (batch mode only).
  /// Call before [labFinalize] so the lab payload includes behavior_data.
  static void flushRuntimeBatch() {
    // In core runtime, batching is handled internally; this is a no-op.
  }

  /// Finalize the lab session and return the complete payload JSON.
  static String? labFinalize(int endedAtMs) {
    return _coreRuntime?.labFinalize(endedAtMs);
  }

  /// Get the last lab export JSON (available after session end in research mode).
  static String? get labExportJson => _coreRuntime?.labExportJson();

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

    SynheartLogger.log('[Synheart] Starting all data collection modules...');

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

    SynheartLogger.log('[Synheart] Stopping all data collection modules...');

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

    // SynheartLogger.log('[Synheart] Starting wear data collection...');
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

    // SynheartLogger.log('[Synheart] Stopping wear data collection...');
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

    // SynheartLogger.log('[Synheart] Starting behavior data collection...');
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

    // SynheartLogger.log('[Synheart] Stopping behavior data collection...');
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

    SynheartLogger.log('[Synheart] Starting phone data collection...');
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

    SynheartLogger.log('[Synheart] Stopping phone data collection...');
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

    // SynheartLogger.log('[Synheart] Starting behavior session...');
    final session = await synheartBehavior.startSession();

    // Track the session so we can end it later
    _activeBehaviorSessions[session.sessionId] = session;

    // SynheartLogger.log(
    //   '[Synheart] Behavior session started: ${session.sessionId}',
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

    // SynheartLogger.log('[Synheart] Stopping behavior session: $sessionId...');

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
  ///   home: Synheart.wrapWithBehaviorDetector(
  ///     MaterialApp(...),
  ///   ),
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
  ///   // Show your custom UI
  ///   return await showConsentDialog(profiles);
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
    return await _consentModule!.getAvailableProfiles();
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
  ///   // Show consent UI
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
  /// print(consentInfo['biosignals']); // "Collect heart rate and HRV data..."
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
  /// If CloudConfig or LabIngestConfig is provided, this will also issue
  /// a consent token from the consent service.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.grantConsent(
  ///   biosignals: true,
  ///   behavior: true,
  ///   phoneContext: true,
  ///   cloudUpload: true,
  /// );
  /// ```

  /// Process a vendor wearable event from RAMEN into the SRM pipeline.
  ///
  /// Call this from the wear SDK when a [RamenEvent] arrives.
  /// The internal WearModule instance (for vendor sync state observation).
  static WearModule? get wearModule => shared._wearModule;

  /// The event is normalized to a CanonicalWearableEvent, stored in SQLite,
  /// and pushed to the runtime for longitudinal baseline computation.
  static Future<void> processVendorEvent({
    required String provider,
    required String eventType,
    required Map<String, dynamic> payload,
    required String eventId,
    required int seq,
  }) async {
    await shared._wearModule?.processVendorEvent(
      provider: provider,
      eventType: eventType,
      payload: payload,
      eventId: eventId,
      seq: seq,
    );
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
      if (biosignals) _coreRuntime!.grantConsent('biosignals');
      if (behavior) _coreRuntime!.grantConsent('behavior');
      if (phoneContext) _coreRuntime!.grantConsent('phoneContext');
      if (cloudUpload) _coreRuntime!.grantConsent('cloudUpload');
      if (vendorSync) _coreRuntime!.grantConsent('vendorSync');
      if (research) _coreRuntime!.grantConsent('research');
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
        SynheartLogger.log('[Synheart] Cloud consent granted — activating device auth...');
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
    if (_config?.cloudConfig != null &&
        cloudUpload &&
        profileId != null) {
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
          '[Synheart] Consent token issued for profile: $profileId (tier: ${tier?.name ?? "legacy"})',
        );
      } catch (e) {
        SynheartLogger.log(
          '[Synheart] Error issuing consent token: $e',
          error: e,
        );
        // Continue with local consent even if token issuance fails
      }
    }

    // Update local consent snapshot
    final snapshot = ConsentSnapshot(
      biosignals: biosignals,
      behavior: behavior,
      phoneContext: phoneContext,
      cloudUpload: cloudUpload,
      syni: false,
      focusEstimation: grantedChannels?.interpretation.focusEstimation ?? false,
      emotionEstimation: grantedChannels?.interpretation.emotionEstimation ?? false,
      vendorSync: vendorSync,
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
    if (_consentModule == null) {
      return {
        'biosignals': false,
        'behavior': false,
        'phoneContext': false,
        'cloudUpload': false,
        'syni': false,
      };
    }

    final consent = _consentModule!.current();
    return {
      'biosignals': consent.biosignals,
      'behavior': consent.behavior,
      'phoneContext': consent.phoneContext,
      'cloudUpload': consent.cloudUpload,
      'syni': consent.syni,
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

    SynheartLogger.log('[Synheart] Deleting all local data...');

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

    SynheartLogger.log('[Synheart] Deleting cloud data...');

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
    SynheartLogger.log('  - Biosignals: ${newConsent.biosignals}');
    SynheartLogger.log('  - Behavior: ${newConsent.behavior}');
    SynheartLogger.log('  - PhoneContext: ${newConsent.phoneContext}');
    SynheartLogger.log('  - Cloud Upload: ${newConsent.cloudUpload}');
    SynheartLogger.log('  - Syni: ${newConsent.syni}');

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
      case SynheartFeature.focus:
        // Focus is computed by synheart-engine and available via lastHsv()
        break;
      case SynheartFeature.emotion:
        // Emotion is computed by synheart-engine and available via lastHsv()
        break;
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
    SynheartLogger.log('[Synheart] Configuring device authentication...');
    SynheartLogger.log(
      '[Synheart] DeviceAuthConfig: authBaseUrl=${dac.authBaseUrl} '
      'capabilityBaseUrl=${dac.capabilityBaseUrl ?? "(default=authBaseUrl)"} '
      'allowUnsignedCapabilities=${resolvedConfig.allowUnsignedCapabilities} '
      'appId=${resolvedConfig.appId}',
    );

    // 1. Configure SynheartAuth
    await SynheartAuth.instance.configure(dac.authBaseUrl);

    // Optional: surface current registration state before attempting registration.
    try {
      final already = await SynheartAuth.instance.isRegistered(resolvedConfig.appId);
      SynheartLogger.log('[Synheart] Device already registered? $already');
    } catch (e) {
      SynheartLogger.log('[Synheart] isRegistered() check failed (non-fatal): $e', error: e);
    }

    // 2. Register device (idempotent — returns alreadyRegistered if done)
    final regResult = await SynheartAuth.instance.registerDevice(
      resolvedConfig.appId,
    );
    SynheartLogger.log(
      '[Synheart] registerDevice result: status=${regResult.status} deviceId=${regResult.deviceId}',
    );
    if (regResult.status == RegistrationStatus.failed) {
      if (resolvedConfig.allowUnsignedCapabilities) {
        SynheartLogger.log(
          '[Synheart] WARNING: Device registration failed, falling back to unsigned capabilities.',
        );
        await _capabilityModule!.loadDefaults();
        return;
      }
      throw StateError(
        'Device registration failed. Set allowUnsignedCapabilities: true for dev mode.',
      );
    }
    SynheartLogger.log(
      '[Synheart] Device registered: ${regResult.deviceId}',
    );

    try {
      if (resolvedConfig.capabilitySecret != null) {
        _coreRuntime?.loadCapabilityToken('{}', resolvedConfig.capabilitySecret!);
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
    _deviceAuthProvider = DeviceAuthProvider(appId: resolvedConfig.appId);
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
      case SynheartFeature.focus:
        return cap.isFeatureEnabled(FeatureFlag.hsiEmotionFocus);
      case SynheartFeature.emotion:
        return cap.isFeatureEnabled(FeatureFlag.hsiEmotionFocus);
      case SynheartFeature.cloud:
        return cap.capability(Module.cloud) != CapabilityLevel.none;
      case SynheartFeature.syni:
        return true; // no capability gate for syni yet
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
      SynheartLogger.log('[Synheart] Stopping...');

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

  String _accountApiBaseUrl() {
    final configured = _config?.sync.baseUrl.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    return ApiEndpoints.defaultAuthBaseUrl;
  }

  Uri _buildAccountApiUri(String path) {
    final base = Uri.parse(_accountApiBaseUrl());
    return base.resolve(path);
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
    return SessionRecord(
      sessionId: map['session_id'] as String? ?? '',
      subjectId: map['subject_id'] as String? ?? '',
      mode: map['mode'] as String? ?? 'personal',
      createdAtUtc: map['created_at_utc'] as int? ?? 0,
      startUtc: map['start_utc'] as int? ?? 0,
      appId: map['app_id'] as String? ?? '',
      appVersion: map['app_version'] as String? ?? '',
      deviceId: map['device_id'] as String? ?? '',
      platform: map['platform'] as String? ?? 'flutter',
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
