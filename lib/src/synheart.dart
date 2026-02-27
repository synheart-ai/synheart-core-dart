import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'config/synheart_config.dart';
import 'core/logger.dart';
import 'modules/base/module_manager.dart';
import 'modules/base/synheart_module.dart';
import 'modules/capabilities/capability_module.dart';
import 'modules/consent/consent_module.dart';
import 'modules/consent/consent_storage.dart';
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
import 'modules/runtime/runtime_bridge.dart';
import 'modules/runtime/runtime_module.dart';
import 'modules/srm/srm_module.dart';
import 'modules/srm/srm_snapshot_storage.dart';
import 'modules/cloud/cloud_connector_module.dart';
import 'config/synheart_feature.dart';
import 'config/activation_manager.dart';
import 'modules/consent/consent_profile.dart';
import 'modules/consent/consent_token.dart';
import 'modules/consent/consent_ui.dart';

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
///   config: SynheartConfig(
///     enableWear: true,
///     enablePhone: true,
///     enableBehavior: true,
///   ),
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

  Synheart._();

  // Module manager
  final ModuleManager _moduleManager = ModuleManager();

  // Core modules
  CapabilityModule? _capabilityModule;
  ConsentModule? _consentModule;
  WearModule? _wearModule;
  PhoneModule? _phoneModule;
  BehaviorModule? _behaviorModule;
  RuntimeModule? _runtimeModule;
  SRMModule? _srmModule;
  CloudConnectorModule? _cloudConnector;

  StreamSubscription? _hsvSubscription;

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
  ConsentSnapshot? _previousConsent;

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
  /// Consumers receive raw HSI JSON strings from the synheart-runtime C ABI.
  Stream<String> get hsiUpdates => _hsvStream.stream;

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
  ///   config: SynheartConfig(
  ///     enableWear: true,
  ///     enablePhone: true,
  ///     enableBehavior: true,
  ///   ),
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
  /// Whether the SDK has been initialized via [initialize].
  static bool get isInitialized => shared._isConfigured;

  static Future<void> initialize({
    required String userId,
    SynheartConfig? config,
    String? appKey,
    bool autoStart =
        false, // Changed: RFC §3.3 — no collection before startSession()
  }) async {
    return shared._configure(
      appKey: appKey ?? 'mock_app_key',
      userId: userId,
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

    try {
      SynheartLogger.log('[Synheart] Initializing capability module...');
      _capabilityModule = CapabilityModule();
      final resolvedConfig = config ?? SynheartConfig.defaults();
      if (resolvedConfig.capabilityToken != null &&
          resolvedConfig.capabilitySecret != null) {
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
          'Capability token and secret are required. Set allowUnsignedCapabilities: true for debug/testing.',
        );
      }

      SynheartLogger.log('[Synheart] Initializing consent module...');
      _consentModule = ConsentModule(consentConfig: _config?.consentConfig);

      _moduleManager.registerModule(_capabilityModule!);
      _moduleManager.registerModule(_consentModule!);

      SynheartLogger.log('[Synheart] Initializing data modules...');
      _wearModule = WearModule(
        capabilities: _capabilityModule!,
        consent: _consentModule!,
      );
      _phoneModule = PhoneModule(
        capabilities: _capabilityModule!,
        consent: _consentModule!,
      );
      _behaviorModule = BehaviorModule(
        capabilities: _capabilityModule!,
        consent: _consentModule!,
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

      SynheartLogger.log('[Synheart] Initializing SRM...');
      _srmModule = SRMModule(storage: SRMSnapshotStorage());
      _moduleManager.registerModule(
        _srmModule!,
        dependsOn: ['capabilities', 'consent'],
      );

      SynheartLogger.log('[Synheart] Initializing Runtime...');
      _runtimeModule = RuntimeModule(
        runtime: RuntimeBridge.createIfAvailable(
          RuntimeConfig(
            subjectId: _userId!,
            sessionId: 'sess_${DateTime.now().millisecondsSinceEpoch}',
          ),
        ),
        wearSampleStream: _wearModule!.rawSampleStream,
        behaviorEventStream: _behaviorModule!.eventStream.events,
      );
      _moduleManager.registerModule(
        _runtimeModule!,
        dependsOn: ['wear', 'behavior'],
      );

      if (_config?.cloudConfig != null) {
        SynheartLogger.log('[Synheart] Initializing Cloud Connector...');
        _cloudConnector = CloudConnectorModule(
          capabilities: _capabilityModule!,
          consent: _consentModule!,
          hsiRuntime: _runtimeModule!,
          config: _config!.cloudConfig!,
        );
        _moduleManager.registerModule(
          _cloudConnector!,
          dependsOn: ['capabilities', 'consent', 'hsi_runtime'],
        );
      }

      SynheartLogger.log('[Synheart] Initializing all modules...');
      await _moduleManager.initializeAll();

      _previousConsent = _consentModule!.current();
      _consentModule!.addListener(_onConsentChanged);

      _hsvSubscription = _runtimeModule!.hsiStream.listen(
        (hsiJson) {
          final consent = _consentModule?.current();
          if (consent == null || !consent.biosignals) return;
          _hsvStream.add(hsiJson);
        },
        onError: (e, st) => SynheartLogger.log(
          '[Synheart] HSI stream error: $e',
          error: e,
          stackTrace: st,
        ),
      );

      _activationManager = ActivationManager();
      _activationManager!.activateFromConfig(resolvedConfig);

      if (autoStart) {
        SynheartLogger.log('[Synheart] Starting all modules...');
        await _moduleManager.startAll();
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
  /// signals to synheart-runtime, enable HSV updates, and enable optional HSI export.
  ///
  /// Must be called after initialize(). No data collection occurs until
  /// this method is called (RFC §3.3).
  static Future<void> startSession() async {
    return shared._startDataCollection();
  }

  /// Stop the current session — halts module streaming and clears ephemeral buffers.
  ///
  /// Per RFC §5.2: Core must halt module streaming, stop synheart-runtime updates,
  /// clear ephemeral buffers, and prevent further HSI export.
  static Future<void> stopSession() async {
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

  /// Get wear features for a specific time window
  ///
  /// Queries aggregated wear features (HR, HRV, etc.) for the specified window.
  ///
  /// Example:
  /// ```dart
  /// final features = await Synheart.getWearFeatures(WindowType.window30s);
  /// if (features != null) {
  ///   print('Average HR: ${features.hrAverage} BPM');
  ///   print('HRV RMSSD: ${features.hrvRmssd} ms');
  /// }
  /// ```
  static Future<WearWindowFeatures?> getWearFeatures(WindowType window) async {
    return shared._getWearFeatures(window);
  }

  /// Get behavior features for a specific time window
  ///
  /// Queries aggregated behavior features (tap rate, keystroke rate, etc.) for the specified window.
  ///
  /// Example:
  /// ```dart
  /// final features = await Synheart.getBehaviorFeatures(WindowType.window30s);
  /// if (features != null) {
  ///   print('Tap Rate: ${features.tapRateNorm}');
  ///   print('Focus Hint: ${features.focusHint}');
  /// }
  /// ```
  static Future<BehaviorWindowFeatures?> getBehaviorFeatures(
    WindowType window,
  ) async {
    return shared._getBehaviorFeatures(window);
  }

  /// Get phone features for a specific time window
  ///
  /// Queries aggregated phone context features (motion, screen state, etc.) for the specified window.
  ///
  /// Example:
  /// ```dart
  /// final features = await Synheart.getPhoneFeatures(WindowType.window30s);
  /// if (features != null) {
  ///   print('Motion Level: ${features.motionLevel}');
  ///   print('Screen On Ratio: ${features.screenOnRatio}');
  /// }
  /// ```
  static Future<PhoneWindowFeatures?> getPhoneFeatures(
    WindowType window,
  ) async {
    return shared._getPhoneFeatures(window);
  }

  /// Force upload of queued snapshots now
  ///
  /// Example:
  /// ```dart
  /// await Synheart.uploadNow();
  /// ```
  static Future<void> uploadNow() async {
    return shared._uploadNow();
  }

  Future<void> _uploadNow() async {
    if (!_isConfigured) {
      throw StateError('Synheart must be initialized before uploading');
    }
    if (_cloudConnector == null) {
      throw StateError('Cloud connector not enabled');
    }
    await _cloudConnector!.uploadNow();
  }

  /// Flush entire upload queue
  ///
  /// Example:
  /// ```dart
  /// await Synheart.flushUploadQueue();
  /// ```
  static Future<void> flushUploadQueue() async {
    return shared._flushUploadQueue();
  }

  Future<void> _flushUploadQueue() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before flushing upload queue',
      );
    }
    if (_cloudConnector == null) {
      throw StateError('Cloud connector not enabled');
    }
    await _cloudConnector!.flushQueue();
  }

  /// Check if user has granted a specific consent
  ///
  /// Example:
  /// ```dart
  /// bool hasConsent = await Synheart.hasConsent('biosignals');
  /// ```
  static Future<bool> hasConsent(String consentType) async {
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

  /// Get runtime module (for diagnostics and direct bridge access)
  RuntimeModule? get runtimeModule => _runtimeModule;

  // ── synheart-runtime SRM API (baselines live in the native Rust engine) ──

  /// Baseline summary from the native synheart-runtime.
  ///
  /// Returns a JSON string like `{"total":14,"ready":0,"warming":5,"empty":9}`
  /// or `null` if the native runtime is not linked.
  static String? get runtimeBaselineSummary {
    return shared._runtimeModule?.bridge?.baselineSummary();
  }

  /// All native runtime baselines as JSON, or `null`.
  static String? get runtimeBaselinesJson {
    return shared._runtimeModule?.bridge?.baselinesJson();
  }

  /// Export the native runtime SRM snapshot as JSON for cross-session persistence.
  static String? exportRuntimeSRMSnapshot() {
    return shared._runtimeModule?.bridge?.exportSrmSnapshot();
  }

  /// Load a native runtime SRM snapshot from JSON.
  /// Returns 0 on success, non-zero error code on failure.
  static int? loadRuntimeSRMSnapshot(String json) {
    return shared._runtimeModule?.bridge?.loadSrmSnapshot(json);
  }

  /// The native synheart-runtime version, or `null` if unavailable.
  static String? get runtimeVersion => RuntimeBridge.version();

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

  /// Start all data collection modules
  Future<void> _startDataCollection() async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before starting data collection',
      );
    }

    if (_isRunning) {
      SynheartLogger.log('[Synheart] Data collection already running');
      return;
    }

    SynheartLogger.log('[Synheart] Starting all data collection modules...');
    await _moduleManager.startAll();

    // Clear session buffers and start accumulating
    _sessionHsiBuffer = [];
    _sessionWearBuffer = [];
    _sessionHsiSubscription = _runtimeModule!.hsiStream.listen(
      (hsiJson) => _sessionHsiBuffer.add(hsiJson),
    );
    _sessionWearSubscription = _wearModule!.rawSampleStream.listen(
      (sample) => _sessionWearBuffer.add(sample),
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

    // Cancel buffer subscriptions but keep buffers for post-session queries
    await _sessionHsiSubscription?.cancel();
    _sessionHsiSubscription = null;
    await _sessionWearSubscription?.cancel();
    _sessionWearSubscription = null;

    _isRunning = false;
    _reevaluateAllFeatures();
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
      SynheartLogger.log('[Synheart] Wear collection already running');
      // If interval changed, update it
      if (interval != null) {
        await _wearModule!.updateCollectionInterval(interval);
      }
      return;
    }

    SynheartLogger.log('[Synheart] Starting wear data collection...');
    if (interval != null) {
      await _wearModule!.updateCollectionInterval(interval);
    }
    await _wearModule!.start();
    SynheartLogger.log('[Synheart] Wear data collection started');
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
      SynheartLogger.log('[Synheart] Wear collection already stopped');
      return;
    }

    SynheartLogger.log('[Synheart] Stopping wear data collection...');
    await _wearModule!.stop();
    SynheartLogger.log('[Synheart] Wear data collection stopped');
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
      SynheartLogger.log('[Synheart] Behavior collection already running');
      return;
    }

    SynheartLogger.log('[Synheart] Starting behavior data collection...');
    await _behaviorModule!.start();
    SynheartLogger.log('[Synheart] Behavior data collection started');
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
      SynheartLogger.log('[Synheart] Behavior collection already stopped');
      return;
    }

    SynheartLogger.log('[Synheart] Stopping behavior data collection...');
    await _behaviorModule!.stop();
    SynheartLogger.log('[Synheart] Behavior data collection stopped');
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

    SynheartLogger.log('[Synheart] Starting behavior session...');
    final session = await synheartBehavior.startSession();

    // Track the session so we can end it later
    _activeBehaviorSessions[session.sessionId] = session;

    SynheartLogger.log(
      '[Synheart] Behavior session started: ${session.sessionId}',
    );
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

    SynheartLogger.log('[Synheart] Stopping behavior session: $sessionId...');

    // End the session and get summary
    final summary = await session.end();

    // Remove from tracking
    _activeBehaviorSessions.remove(sessionId);

    SynheartLogger.log('[Synheart] Behavior session stopped: $sessionId');
    return BehaviorSessionResults.fromSummary(summary);
  }

  /// Get wear features for a specific time window
  Future<WearWindowFeatures?> _getWearFeatures(WindowType window) async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before querying wear features',
      );
    }

    if (_wearModule == null) {
      throw StateError('Wear module not initialized');
    }

    return _wearModule!.features(window);
  }

  /// Get behavior features for a specific time window
  Future<BehaviorWindowFeatures?> _getBehaviorFeatures(
    WindowType window,
  ) async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before querying behavior features',
      );
    }

    if (_behaviorModule == null) {
      throw StateError('Behavior module not initialized');
    }

    return _behaviorModule!.features(window);
  }

  /// Get phone features for a specific time window
  Future<PhoneWindowFeatures?> _getPhoneFeatures(WindowType window) async {
    if (!_isConfigured) {
      throw StateError(
        'Synheart must be initialized before querying phone features',
      );
    }

    if (_phoneModule == null) {
      throw StateError('Phone module not initialized');
    }

    return _phoneModule!.features(window);
  }

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

    // Check if consent was previously stored
    if (_consentModule == null) {
      return true; // No consent module means no stored consent
    }

    // Check if consent exists in storage
    final storage = ConsentStorage();
    final hasStoredConsent = await storage.exists();
    return !hasStoredConsent;
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
  /// If CloudConfig is provided, this will also issue a consent token from the consent service.
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
  static Future<void> grantConsent({
    required bool biosignals,
    required bool behavior,
    required bool phoneContext,
    required bool cloudUpload,
    String? profileId,
  }) async {
    return shared._grantConsent(
      biosignals: biosignals,
      behavior: behavior,
      phoneContext: phoneContext,
      cloudUpload: cloudUpload,
      profileId: profileId,
    );
  }

  Future<void> _grantConsent({
    required bool biosignals,
    required bool behavior,
    required bool phoneContext,
    required bool cloudUpload,
    String? profileId,
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

    // If CloudConfig is provided and cloudUpload is true, issue token
    if (_config?.cloudConfig != null && cloudUpload && profileId != null) {
      try {
        // Fetch profiles if needed
        final profiles = await _consentModule!.getAvailableProfiles();
        final profile = profiles.firstWhere(
          (p) => p.id == profileId,
          orElse: () => throw StateError('Profile not found: $profileId'),
        );

        // Request consent token
        await _consentModule!.requestConsent(profile);
        SynheartLogger.log(
          '[Synheart] Consent token issued for profile: $profileId',
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
      focusEstimation: false,
      emotionEstimation: false,
      timestamp: DateTime.now(),
      explicitlyDenied: false,
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

    // Clear upload queue
    if (_cloudConnector != null) {
      await _cloudConnector!.clearQueue();
    }

    // Clear HSI state (if any persisted state exists)
    // Note: HSI Runtime doesn't persist state, so nothing to clear

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

    // Clear upload queue
    if (_cloudConnector != null) {
      await _cloudConnector!.clearQueue();
    }

    SynheartLogger.log(
      '[Synheart] Cloud upload queue cleared. Note: Cloud service data deletion requires API call (not implemented yet)',
    );
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
    final runtime = shared._runtimeModule;
    final bridge = runtime != null ? runtime.bridge : null;
    return {
      'isAvailable': bridge != null,
      'version': RuntimeBridge.version(),
      'frameCount': bridge?.frameCount() ?? 0,
      'lastQuality': bridge?.lastQuality(),
    };
  }

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

    _previousConsent = newConsent;
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
        // Focus is computed by synheart-runtime and available via lastHsv()
        break;
      case SynheartFeature.emotion:
        // Emotion is computed by synheart-runtime and available via lastHsv()
        break;
      case SynheartFeature.cloud:
        if (isOperational &&
            _cloudConnector != null &&
            _cloudConnector!.status != ModuleStatus.running) {
          _cloudConnector?.start().catchError(
            (e) => SynheartLogger.log(
              '[Synheart] Error starting cloud: $e',
              error: e,
            ),
          );
        } else if (!isOperational &&
            _cloudConnector != null &&
            _cloudConnector!.status == ModuleStatus.running) {
          _cloudConnector?.stop().catchError(
            (e) => SynheartLogger.log(
              '[Synheart] Error stopping cloud: $e',
              error: e,
            ),
          );
        }
      case SynheartFeature.syni:
        break; // placeholder — no SyniHooksModule yet
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

      // Stop HSI subscription
      await _hsvSubscription?.cancel();

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

      await _moduleManager.disposeAll();

      await _hsvStream.close();

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
      _runtimeModule = null;
      _srmModule = null;
      _activationManager = null;
      _previousConsent = null;
      _pendingConsent = null;
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
}

/// Consent values queued before SDK initialization.
class _PendingConsent {
  final bool biosignals;
  final bool behavior;
  final bool phoneContext;
  final bool cloudUpload;

  _PendingConsent({
    required this.biosignals,
    required this.behavior,
    required this.phoneContext,
    required this.cloudUpload,
  });
}
