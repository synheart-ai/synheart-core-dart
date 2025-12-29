import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'models/hsv.dart';
import 'models/emotion.dart';
import 'models/focus.dart';
import 'config/synheart_config.dart';
import 'core/logger.dart';
import 'services/auth_service.dart';
import 'modules/base/module_manager.dart';
import 'modules/capabilities/capability_module.dart';
import 'modules/consent/consent_module.dart';
import 'modules/interfaces/consent_provider.dart';
import 'modules/wear/wear_module.dart';
import 'modules/phone/phone_module.dart';
import 'modules/behavior/behavior_module.dart';
import 'modules/hsi_runtime/hsi_runtime_module.dart';
import 'modules/hsi_runtime/channel_collector.dart';
import 'modules/cloud/cloud_connector_module.dart';
import 'heads/emotion_head.dart';
import 'heads/focus_head.dart';

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
  static Stream<EmotionState> get onEmotionUpdate => shared._emotionStream.stream;

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
  static Future<void> initialize({
    required String userId,
    SynheartConfig? config,
    String? appKey,
  }) async {
    return shared._configure(
      appKey: appKey ?? 'mock_app_key',
      userId: userId,
      config: config,
    );
  }

  Future<void> _configure({
    required String appKey,
    required String userId,
    SynheartConfig? config,
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
      await _capabilityModule!.loadFromToken(
        token,
        'mock_secret',
      );

      // 3. Initialize consent module
      SynheartLogger.log('[Synheart] Initializing consent module...');
      _consentModule = ConsentModule();

      // 4. Register modules with manager
      _moduleManager.registerModule(_capabilityModule!);
      _moduleManager.registerModule(_consentModule!);

      // 5. Initialize data collection modules
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

      // 6. Initialize HSI Runtime (produces HSV - NO emotion/focus here, they're optional)
      SynheartLogger.log('[Synheart] Initializing HSI Runtime...');
      final collector = ChannelCollector(
        wear: _wearModule!,
        phone: _phoneModule!,
        behavior: _behaviorModule!,
      );
      _hsiRuntimeModule = HSIRuntimeModule(
        collector: collector,
      );
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

      // 10. Start modules
      SynheartLogger.log('[Synheart] Starting all modules...');
      await _moduleManager.startAll();

      _isConfigured = true;
      _isRunning = true;
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
      _focusHead!.start(_hsvStream.stream);

      // Subscribe to focus output
      _focusSubscription = _focusHead!.focusStream.listen(
        (hsv) {
          // Extract focus state from HSV and emit
          _focusStream.add(hsv.focus);
        },
        onError: (e, st) => SynheartLogger.log(
          '[Synheart] Focus stream error: $e',
          error: e,
          stackTrace: st,
        ),
      );

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
          // Extract emotion state from HSV and emit
          _emotionStream.add(hsv.emotion);
        },
        onError: (e, st) => SynheartLogger.log(
          '[Synheart] Emotion stream error: $e',
          error: e,
          stackTrace: st,
        ),
      );

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

    if (_cloudConnector == null) {
      throw StateError('Cloud connector not configured. Provide cloudConfig during initialization');
    }

    // Cloud connector is already initialized and started with other modules
    // This method is here for API consistency but the module is auto-started
    SynheartLogger.log('[Synheart] Cloud connector already active');
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
      throw StateError('Synheart must be initialized before flushing upload queue');
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

  /// Grant consent for a specific data type
  ///
  /// Example:
  /// ```dart
  /// await Synheart.grantConsent('biosignals');
  /// ```
  static Future<void> grantConsent(String consentType) async {
    return shared._grantConsent(consentType);
  }

  Future<void> _grantConsent(String consentType) async {
    if (_consentModule == null) {
      throw StateError('Consent module not initialized');
    }

    final current = _consentModule!.current();
    final updated = ConsentSnapshot(
      biosignals: consentType == 'biosignals' ? true : current.biosignals,
      behavior: consentType == 'behavior' ? true : current.behavior,
      motion: consentType == 'motion' || consentType == 'phoneContext' ? true : current.motion,
      cloudUpload: consentType == 'cloudUpload' ? true : current.cloudUpload,
      syni: consentType == 'syni' ? true : current.syni,
      timestamp: DateTime.now(),
    );

    await _consentModule!.updateConsent(updated);
  }

  /// Revoke consent for a specific data type
  ///
  /// Example:
  /// ```dart
  /// await Synheart.revokeConsent('biosignals');
  /// ```
  static Future<void> revokeConsent(String consentType) async {
    return shared._revokeConsent(consentType);
  }

  Future<void> _revokeConsent(String consentType) async {
    if (_consentModule == null) {
      throw StateError('Consent module not initialized');
    }

    final current = _consentModule!.current();
    final updated = ConsentSnapshot(
      biosignals: consentType == 'biosignals' ? false : current.biosignals,
      behavior: consentType == 'behavior' ? false : current.behavior,
      motion: consentType == 'motion' || consentType == 'phoneContext' ? false : current.motion,
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
