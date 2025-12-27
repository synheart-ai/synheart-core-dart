import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'models/hsv.dart';
import 'models/emotion.dart';
import 'models/focus.dart';
import 'config/synheart_config.dart';
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
/// // Subscribe to HSI updates (core state representation)
/// Synheart.onHSIUpdate.listen((hsi) {
///   print('Arousal Index: ${hsi.affect.arousalIndex}');
///   print('Engagement Stability: ${hsi.engagement.engagementStability}');
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
  // TODO: CloudConnectorModule? _cloudConnector;
  // TODO: SyniHooksModule? _syniHooks;

  // Optional interpretation modules
  EmotionHead? _emotionHead;
  FocusHead? _focusHead;
  StreamSubscription? _emotionSubscription;
  StreamSubscription? _focusSubscription;

  // Services
  final AuthService _authService = MockAuthService();

  // State
  bool _isConfigured = false;
  bool _isRunning = false;
  String? _userId;
  SynheartConfig? _config;

  // Streams
  final BehaviorSubject<HumanStateVector> _hsiStream =
      BehaviorSubject<HumanStateVector>();
  final BehaviorSubject<EmotionState> _emotionStream =
      BehaviorSubject<EmotionState>();
  final BehaviorSubject<FocusState> _focusStream =
      BehaviorSubject<FocusState>();

  /// Stream of HSI updates (core state representation)
  ///
  /// HSI contains:
  /// - State axes (affect, engagement, activity, context)
  /// - State indices (arousalIndex, engagementStability, etc.)
  /// - 64D state embedding
  ///
  /// HSI does NOT contain interpretation (emotion, focus).
  Stream<HumanStateVector> get onHSIUpdate => _hsiStream.stream;

  /// Stream of emotion updates (optional interpretation)
  ///
  /// Only emits if emotion module is enabled via enableEmotion().
  Stream<EmotionState> get onEmotionUpdate => _emotionStream.stream;

  /// Stream of focus updates (optional interpretation)
  ///
  /// Only emits if focus module is enabled via enableFocus().
  Stream<FocusState> get onFocusUpdate => _focusStream.stream;

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
      print('[Synheart] Authenticating...');
      final token = await _authService.authenticate(
        appKey: appKey,
        userId: userId,
      );

      // 2. Initialize capability module
      print('[Synheart] Initializing capability module...');
      _capabilityModule = CapabilityModule();
      await _capabilityModule!.loadFromToken(
        token,
        'mock_secret',
      );

      // 3. Initialize consent module
      print('[Synheart] Initializing consent module...');
      _consentModule = ConsentModule();

      // 4. Register modules with manager
      _moduleManager.registerModule(_capabilityModule!);
      _moduleManager.registerModule(_consentModule!);

      // 5. Initialize data collection modules
      print('[Synheart] Initializing data modules...');
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

      _moduleManager.registerModule(_wearModule!, dependsOn: ['capabilities', 'consent']);
      _moduleManager.registerModule(_phoneModule!, dependsOn: ['capabilities', 'consent']);
      _moduleManager.registerModule(_behaviorModule!, dependsOn: ['capabilities', 'consent']);

      // 6. Initialize HSI Runtime (NO emotion/focus here - they're optional)
      print('[Synheart] Initializing HSI Runtime...');
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

      // 7. Initialize all modules
      print('[Synheart] Initializing all modules...');
      await _moduleManager.initializeAll();

      // 8. Set up consent change listeners
      _consentModule!.addListener(_onConsentChanged);

      // 9. Subscribe to HSI stream (core state only)
      _hsiRuntimeModule!.hsiStream.listen(
        (hsi) => _hsiStream.add(hsi),
        onError: (e) => print('[Synheart] HSI stream error: $e'),
      );

      // 10. Start modules
      print('[Synheart] Starting all modules...');
      await _moduleManager.startAll();

      _isConfigured = true;
      _isRunning = true;
      print('[Synheart] Initialization complete');
    } catch (e, stack) {
      print('[Synheart] Initialization failed: $e');
      print(stack);
      rethrow;
    }
  }

  /// Enable focus interpretation module
  ///
  /// This is an optional interpretation module that consumes HSI
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
      print('[Synheart] Focus module already enabled');
      return;
    }

    try {
      print('[Synheart] Enabling focus module...');

      _focusHead = FocusHead();

      // Focus head subscribes to HSI stream
      _focusHead!.start(_hsiStream.stream);

      // Subscribe to focus output
      _focusSubscription = _focusHead!.focusStream.listen(
        (hsv) {
          // Extract focus state from HSV and emit
          _focusStream.add(hsv.focus);
        },
        onError: (e) => print('[Synheart] Focus stream error: $e'),
      );

      print('[Synheart] Focus module enabled');
    } catch (e, stack) {
      print('[Synheart] Failed to enable focus: $e');
      print(stack);
      rethrow;
    }
  }

  /// Enable emotion interpretation module
  ///
  /// This is an optional interpretation module that consumes HSI
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
      print('[Synheart] Emotion module already enabled');
      return;
    }

    try {
      print('[Synheart] Enabling emotion module...');

      _emotionHead = EmotionHead();

      // Emotion head subscribes to HSI stream
      _emotionHead!.start(_hsiStream.stream);

      // Subscribe to emotion output
      _emotionSubscription = _emotionHead!.emotionStream.listen(
        (hsv) {
          // Extract emotion state from HSV and emit
          _emotionStream.add(hsv.emotion);
        },
        onError: (e) => print('[Synheart] Emotion stream error: $e'),
      );

      print('[Synheart] Emotion module enabled');
    } catch (e, stack) {
      print('[Synheart] Failed to enable emotion: $e');
      print(stack);
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
    // TODO: Implement cloud sync
    throw UnimplementedError('Cloud sync not yet implemented');
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

  /// Get current HSI state (latest)
  HumanStateVector? get currentState {
    return _hsiRuntimeModule?.currentState;
  }

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
    print('[Synheart] Consent changed:');
    print('  - Biosignals: ${consent.biosignals}');
    print('  - Behavior: ${consent.behavior}');
    print('  - Motion: ${consent.motion}');
    print('  - Cloud Upload: ${consent.cloudUpload}');
    print('  - Syni: ${consent.syni}');
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
      print('[Synheart] Stopping...');

      // Stop interpretation modules
      await _focusSubscription?.cancel();
      await _emotionSubscription?.cancel();
      await _focusHead?.stop();
      await _emotionHead?.stop();

      // Stop core modules
      await _moduleManager.stopAll();

      _isRunning = false;
      print('[Synheart] Stopped');
    } catch (e, stack) {
      print('[Synheart] Stop failed: $e');
      print(stack);
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

      await _hsiStream.close();
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

      print('[Synheart] Disposed');
    } catch (e, stack) {
      print('[Synheart] Dispose failed: $e');
      print(stack);
    }
  }
}
