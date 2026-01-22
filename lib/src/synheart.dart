import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'models/hsv.dart';
import 'models/emotion.dart';
import 'models/focus.dart';
import 'config/synheart_config.dart';
import 'core/logger.dart';
import 'services/auth_service.dart';
import 'modules/base/module_manager.dart';
import 'modules/base/synheart_module.dart';
import 'modules/capabilities/capability_module.dart';
import 'modules/consent/consent_module.dart';
import 'modules/consent/consent_storage.dart';
import 'modules/interfaces/consent_provider.dart';
import 'modules/wear/wear_module.dart';
import 'modules/wear/wear_source_handler.dart';
import 'modules/phone/phone_module.dart';
import 'modules/behavior/behavior_module.dart';
import 'modules/behavior/behavior_events.dart';
import 'modules/interfaces/feature_providers.dart';
import 'models/behavior_session_results.dart';
import 'package:synheart_behavior/synheart_behavior.dart' as sb;
import 'modules/hsi_runtime/hsi_runtime_module.dart';
import 'modules/hsi_runtime/channel_collector.dart';
import 'modules/cloud/cloud_connector_module.dart';
import 'heads/emotion_head.dart';
import 'heads/focus_head.dart';
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
/// Optional interpretation modules:
/// - Emotion (affect modeling)
/// - Focus (engagement/focus estimation)
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
/// // Subscribe to HSV updates (core state representation)
/// Synheart.onHSVUpdate.listen((hsv) {
///   print('Arousal Index: ${hsv.meta.axes.affect.arousalIndex}');
///   print('Engagement Stability: ${hsv.meta.axes.engagement.engagementStability}');
/// });
///
/// // Optional: Enable interpretation modules
/// await Synheart.enableFocus();
/// Synheart.onFocusUpdate.listen((focus) {
///   print('Focus Score: ${focus.estimate.score}');
/// });
///
/// await Synheart.enableEmotion();
/// Synheart.onEmotionUpdate.listen((emotion) {
///   print('Stress Index: ${emotion.stressIndex}');
/// });
///
/// // Enable cloud upload (with consent)
/// await Synheart.enableCloud();
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
  HSIRuntimeModule? _hsiRuntimeModule;
  CloudConnectorModule? _cloudConnector;
  // TODO: SyniHooksModule? _syniHooks;

  // Optional interpretation modules
  EmotionHead? _emotionHead;
  FocusHead? _focusHead;
  StreamSubscription? _emotionSubscription;
  StreamSubscription? _focusSubscription;
  StreamSubscription? _hsvSubscription;

  // Behavior session tracking
  final Map<String, sb.BehaviorSession> _activeBehaviorSessions = {};

  // Services
  final AuthService _authService = MockAuthService();

  // State
  bool _isConfigured = false;
  bool _isRunning = false;
  String? _userId;
  SynheartConfig? _config;

  // Streams
  final BehaviorSubject<HumanStateVector> _hsvStream =
      BehaviorSubject<HumanStateVector>();
  final BehaviorSubject<EmotionState> _emotionStream =
      BehaviorSubject<EmotionState>();
  final BehaviorSubject<FocusState> _focusStream =
      BehaviorSubject<FocusState>();

  /// Static stream of HSV updates (core state representation)
  static Stream<HumanStateVector> get onHSVUpdate => shared._hsvStream.stream;

  /// Static stream of emotion updates (optional interpretation)
  static Stream<EmotionState> get onEmotionUpdate =>
      shared._emotionStream.stream;

  /// Static stream of focus updates (optional interpretation)
  static Stream<FocusState> get onFocusUpdate => shared._focusStream.stream;

  /// Stream of HSV updates (core state representation)
  ///
  /// HSV (Human State Vector) contains:
  /// - State axes (affect, engagement, activity, context)
  /// - State indices (arousalIndex, engagementStability, etc.)
  /// - 64D state embedding
  ///
  /// HSV does NOT contain interpretation (emotion, focus) unless enabled.
  Stream<HumanStateVector> get hsvUpdates => _hsvStream.stream;

  /// Stream of emotion updates (optional interpretation)
  ///
  /// Only emits if emotion module is enabled via enableEmotion().
  Stream<EmotionState> get emotionUpdates => _emotionStream.stream;

  /// Stream of focus updates (optional interpretation)
  ///
  /// Only emits if focus module is enabled via enableFocus().
  Stream<FocusState> get focusUpdates => _focusStream.stream;

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
  /// To initialize without automatically starting data collection:
  /// ```dart
  /// await Synheart.initialize(
  ///   userId: 'anon_user_123',
  ///   autoStart: false, // Don't start collection automatically
  /// );
  /// await Synheart.startDataCollection(); // Start when needed
  /// ```
  static Future<void> initialize({
    required String userId,
    SynheartConfig? config,
    String? appKey,
    bool autoStart = true, // Default to true for backward compatibility
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
    bool autoStart = true,
  }) async {
    if (_isConfigured) {
      throw StateError('Synheart already configured');
    }

    _userId = userId;
    _config = config ?? SynheartConfig.defaults();

    try {
      // 1. Authenticate & get capabilities
      SynheartLogger.log('[Synheart] Authenticating...');
      final token = await _authService.authenticate(
        appKey: appKey,
        userId: userId,
      );

      // 2. Initialize capability module
      SynheartLogger.log('[Synheart] Initializing capability module...');
      _capabilityModule = CapabilityModule();
      await _capabilityModule!.loadFromToken(token, 'mock_secret');

      // 3. Initialize consent module
      SynheartLogger.log('[Synheart] Initializing consent module...');
      _consentModule = ConsentModule(consentConfig: _config?.consentConfig);

      // 4. Register modules with manager
      _moduleManager.registerModule(_capabilityModule!);
      _moduleManager.registerModule(_consentModule!);

      // 5. Initialize data collection modules
      SynheartLogger.log('[Synheart] Initializing data modules...');
      _wearModule = WearModule(
        capabilities: _capabilityModule!,
        consent: _consentModule!,
        focusEnabled: _focusHead != null,
        emotionEnabled: _emotionHead != null,
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

      // 6. Initialize HSI Runtime (produces HSV - NO emotion/focus here, they're optional)
      SynheartLogger.log('[Synheart] Initializing HSI Runtime...');
      final collector = ChannelCollector(
        wear: _wearModule!,
        phone: _phoneModule!,
        behavior: _behaviorModule!,
      );
      _hsiRuntimeModule = HSIRuntimeModule(collector: collector);
      _moduleManager.registerModule(
        _hsiRuntimeModule!,
        dependsOn: ['wear', 'phone', 'behavior'],
      );

      // 7. Initialize Cloud Connector (optional, depends on consent and config)
      if (_config?.cloudConfig != null) {
        SynheartLogger.log('[Synheart] Initializing Cloud Connector...');
        _cloudConnector = CloudConnectorModule(
          capabilities: _capabilityModule!,
          consent: _consentModule!,
          hsiRuntime: _hsiRuntimeModule!,
          config: _config!.cloudConfig!,
        );
        _moduleManager.registerModule(
          _cloudConnector!,
          dependsOn: ['capabilities', 'consent', 'hsi_runtime'],
        );
      }

      // 8. Initialize all modules
      SynheartLogger.log('[Synheart] Initializing all modules...');
      await _moduleManager.initializeAll();

      // 8. Set up consent change listeners
      _consentModule!.addListener(_onConsentChanged);

      // 9. Subscribe to HSV stream (core state only)
      _hsvSubscription = _hsiRuntimeModule!.hsiStream.listen(
        _hsvStream.add,
        onError: (e, st) => SynheartLogger.log(
          '[Synheart] HSV stream error: $e',
          error: e,
          stackTrace: st,
        ),
      );

      // 10. Start modules (if autoStart is enabled)
      if (autoStart) {
        SynheartLogger.log('[Synheart] Starting all modules...');
        await _moduleManager.startAll();
        _isRunning = true;
      } else {
        SynheartLogger.log(
          '[Synheart] Modules initialized but not started (autoStart=false). Call startDataCollection() when ready.',
        );
        _isRunning = false;
      }

      _isConfigured = true;
      SynheartLogger.log('[Synheart] Initialization complete');
    } catch (e, stack) {
      SynheartLogger.log(
        '[Synheart] Initialization failed: $e',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Start all data collection modules
  ///
  /// Starts wear, phone, and behavior data collection if not already running.
  /// This is useful when you initialized with `autoStart: false`.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.initialize(userId: 'user', autoStart: false);
  /// // ... later when you need data collection
  /// await Synheart.startDataCollection();
  /// ```
  static Future<void> startDataCollection() async {
    return shared._startDataCollection();
  }

  /// Stop all data collection modules
  ///
  /// Stops wear, phone, and behavior data collection but keeps modules initialized.
  /// Useful for saving battery when data collection is not needed.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.stopDataCollection(); // Stop collecting
  /// // ... later
  /// await Synheart.startDataCollection(); // Resume collecting
  /// ```
  static Future<void> stopDataCollection() async {
    return shared._stopDataCollection();
  }

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

  /// Enable focus interpretation module
  ///
  /// This is an optional interpretation module that consumes HSV
  /// and produces focus estimates.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.enableFocus();
  /// Synheart.onFocusUpdate.listen((focus) {
  ///   print('Focus Score: ${focus.estimate.score}');
  /// });
  /// ```
  static Future<void> enableFocus() async {
    return shared._enableFocus();
  }

  Future<void> _enableFocus() async {
    if (!_isConfigured) {
      throw StateError('Synheart must be initialized before enabling focus');
    }

    if (_focusHead != null) {
      SynheartLogger.log('[Synheart] Focus module already enabled');
      return;
    }

    try {
      SynheartLogger.log('[Synheart] Enabling focus module...');

      _focusHead = FocusHead();

      // Focus head subscribes to HSV stream
      await _focusHead!.start(_hsvStream.stream);

      // Subscribe to focus output
      _focusSubscription = _focusHead!.focusStream.listen(
        (hsvWithFocus) {
          // Instead of just emitting focus, merge the full HSV back into the main stream
          _hsvStream.add(hsvWithFocus);
          // Also emit focus state for backward compatibility
          _focusStream.add(hsvWithFocus.focus);
        },
        onError: (e, st) => SynheartLogger.log(
          '[Synheart] Focus stream error: $e',
          error: e,
          stackTrace: st,
        ),
      );

      // Update wear module to use higher frequency collection (1s)
      await _wearModule?.updateModuleStatus(focusEnabled: true);

      SynheartLogger.log('[Synheart] Focus module enabled');
    } catch (e, stack) {
      SynheartLogger.log(
        '[Synheart] Failed to enable focus: $e',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Enable emotion interpretation module
  ///
  /// This is an optional interpretation module that consumes HSV
  /// and produces emotion estimates.
  ///
  /// Example:
  /// ```dart
  /// await Synheart.enableEmotion();
  /// Synheart.onEmotionUpdate.listen((emotion) {
  ///   print('Stress Index: ${emotion.stressIndex}');
  /// });
  /// ```
  static Future<void> enableEmotion() async {
    return shared._enableEmotion();
  }

  Future<void> _enableEmotion() async {
    if (!_isConfigured) {
      throw StateError('Synheart must be initialized before enabling emotion');
    }

    if (_emotionHead != null) {
      SynheartLogger.log('[Synheart] Emotion module already enabled');
      return;
    }

    try {
      SynheartLogger.log('[Synheart] Enabling emotion module...');

      _emotionHead = EmotionHead();

      // Emotion head subscribes to HSV stream
      _emotionHead!.start(_hsvStream.stream);

      // Subscribe to emotion output
      _emotionSubscription = _emotionHead!.emotionStream.listen(
        (hsv) {
          // Extract emotion state from HSV and emit to emotion stream
          _emotionStream.add(hsv.emotion);

          // Also merge emotion-populated HSV back into main HSV stream
          // This ensures UI subscribers see the updated emotion data
          _hsvStream.add(hsv);
        },
        onError: (e, st) => SynheartLogger.log(
          '[Synheart] Emotion stream error: $e',
          error: e,
          stackTrace: st,
        ),
      );

      // Update wear module to use higher frequency collection (1s)
      await _wearModule?.updateModuleStatus(emotionEnabled: true);

      SynheartLogger.log('[Synheart] Emotion module enabled');
    } catch (e, stack) {
      SynheartLogger.log(
        '[Synheart] Failed to enable emotion: $e',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Enable cloud uploads (requires cloudUpload consent)
  ///
  /// Example:
  /// ```dart
  /// await Synheart.enableCloud();
  /// ```
  static Future<void> enableCloud() async {
    return shared._enableCloud();
  }

  Future<void> _enableCloud() async {
    if (!_isConfigured) {
      throw StateError('Synheart must be initialized before enabling cloud');
    }

    if (!_consentModule!.current().cloudUpload) {
      throw StateError('cloudUpload consent required');
    }

    // If cloud connector doesn't exist, create it lazily
    if (_cloudConnector == null) {
      // Check if cloudConfig was provided during initialization
      CloudConfig? cloudConfig = _config?.cloudConfig;

      // If no cloudConfig was provided, we cannot enable cloud sync
      // CloudConfig requires tenantId, hmacSecret, etc. which must come from app config
      if (cloudConfig == null) {
        throw StateError(
          'Cloud Connector not configured. Provide cloudConfig during initialization with tenantId, hmacSecret, subjectId, and instanceId.',
        );
      }

      SynheartLogger.log('[Synheart] Lazy initializing Cloud Connector...');
      _cloudConnector = CloudConnectorModule(
        capabilities: _capabilityModule!,
        consent: _consentModule!,
        hsiRuntime: _hsiRuntimeModule!,
        config: cloudConfig,
      );
      _moduleManager.registerModule(
        _cloudConnector!,
        dependsOn: ['capabilities', 'consent', 'hsi_runtime'],
      );

      await _cloudConnector!.initialize();
    }

    // Ensure cloud connector is running
    if (_cloudConnector!.status != ModuleStatus.running) {
      await _cloudConnector!.start();
    }
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

  /// Disable cloud uploads
  ///
  /// Example:
  /// ```dart
  /// await Synheart.disableCloud();
  /// ```
  static Future<void> disableCloud() async {
    return shared._disableCloud();
  }

  Future<void> _disableCloud() async {
    if (!_isConfigured) {
      throw StateError('Synheart must be initialized before disabling cloud');
    }
    if (_cloudConnector != null) {
      await _cloudConnector!.stop();
    }
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
      case 'motion':
        return consent.motion;
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
      motion: consentType == 'motion' || consentType == 'phoneContext'
          ? false
          : current.motion,
      cloudUpload: consentType == 'cloudUpload' ? false : current.cloudUpload,
      syni: consentType == 'syni' ? false : current.syni,
      timestamp: DateTime.now(),
    );

    await _consentModule!.updateConsent(updated);
  }

  /// Get current HSV state (latest)
  HumanStateVector? get currentState {
    return _hsiRuntimeModule?.currentState;
  }

  /// Get the currently configured user id (if initialized)
  String? get userId => _userId;

  /// Get behavior module for recording events
  BehaviorModule? get behaviorModule => _behaviorModule;

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
    _isRunning = true;
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
    await _moduleManager.stopAll();
    _isRunning = false;
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
      // 1. Fetch available profiles
      final profiles = await _consentModule!.getAvailableProfiles();
      if (profiles.isEmpty) {
        SynheartLogger.log('[Synheart] No consent profiles available');
        return null;
      }

      // 2. Present UI (via hook)
      final selected = await _consentUI.presentConsentFlow(profiles);
      if (selected == null) {
        return null; // User declined
      }

      // 3. Issue token
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
      info['motion'] =
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
  ///   motion: true,
  ///   cloudUpload: true,
  /// );
  /// ```
  static Future<void> grantConsent({
    required bool biosignals,
    required bool behavior,
    required bool motion,
    required bool cloudUpload,
    String? profileId,
  }) async {
    return shared._grantConsent(
      biosignals: biosignals,
      behavior: behavior,
      motion: motion,
      cloudUpload: cloudUpload,
      profileId: profileId,
    );
  }

  Future<void> _grantConsent({
    required bool biosignals,
    required bool behavior,
    required bool motion,
    required bool cloudUpload,
    String? profileId,
  }) async {
    if (!_isConfigured) {
      throw StateError('Synheart must be initialized before granting consent');
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
      motion: motion,
      cloudUpload: cloudUpload,
      syni: false,
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

    if (!motion && _phoneModule != null) {
      SynheartLogger.log(
        '[Synheart] Motion consent denied - stopping phone data collection',
      );
      // The PhoneModule will handle this via consent checks
    }

    SynheartLogger.log(
      '[Synheart] Consent granted: biosignals=$biosignals, behavior=$behavior, motion=$motion, cloudUpload=$cloudUpload',
    );
  }

  Map<String, bool> _getConsentStatusMap() {
    if (_consentModule == null) {
      return {
        'biosignals': false,
        'behavior': false,
        'motion': false,
        'phoneContext': false,
        'cloudUpload': false,
        'syni': false,
      };
    }

    final consent = _consentModule!.current();
    return {
      'biosignals': consent.biosignals,
      'behavior': consent.behavior,
      'motion': consent.motion,
      'phoneContext': consent.motion, // Alias
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
      case 'motion':
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

    // TODO: Add API call to cloud service to delete user data
    // This would require:
    // 1. Cloud service endpoint for data deletion
    // 2. User authentication/authorization
    // 3. Confirmation of deletion
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

  /// Get module statuses (for debugging)
  Map<String, String> getModuleStatuses() {
    final statuses = _moduleManager.getModuleStatuses();
    return statuses.map((key, value) => MapEntry(key, value.name));
  }

  /// Handle consent changes
  void _onConsentChanged(ConsentSnapshot consent) {
    SynheartLogger.log('[Synheart] Consent changed:');
    SynheartLogger.log('  - Biosignals: ${consent.biosignals}');
    SynheartLogger.log('  - Behavior: ${consent.behavior}');
    SynheartLogger.log('  - Motion: ${consent.motion}');
    SynheartLogger.log('  - Cloud Upload: ${consent.cloudUpload}');
    SynheartLogger.log('  - Syni: ${consent.syni}');
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

      // Stop interpretation modules
      await _focusSubscription?.cancel();
      await _emotionSubscription?.cancel();
      await _hsvSubscription?.cancel();
      await _focusHead?.stop();
      await _emotionHead?.stop();

      // Update wear module to reduce collection frequency (no longer need 1s)
      await _wearModule?.updateModuleStatus(
        focusEnabled: false,
        emotionEnabled: false,
      );

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

      await _focusHead?.dispose();
      await _emotionHead?.dispose();
      await _moduleManager.disposeAll();

      await _hsvStream.close();
      await _emotionStream.close();
      await _focusStream.close();

      _consentModule = null;
      _capabilityModule = null;
      _wearModule = null;
      _phoneModule = null;
      _behaviorModule = null;
      _hsiRuntimeModule = null;
      _focusHead = null;
      _emotionHead = null;
      _isConfigured = false;
      _isRunning = false;

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
