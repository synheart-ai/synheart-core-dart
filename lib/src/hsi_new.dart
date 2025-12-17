import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'models/hsv.dart';
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

/// Synheart Core SDK - Main Entry Point
///
/// This is the main entry point for the Synheart Core SDK.
/// It orchestrates all 7 core modules:
/// - Capabilities Module (feature gating)
/// - Consent Module (permission management)
/// - Wear Module (biosignal collection)
/// - Phone Module (motion/context)
/// - Behavior Module (interaction patterns)
/// - HSI Runtime (signal fusion & state computation)
/// - Cloud Connector (secure uploads)
///
/// Note: The class is named `HSI` for backward compatibility,
/// but it represents the full Core SDK, not just HSI Runtime.
class HSI {
  static HSI? _instance;
  static HSI get shared => _instance ??= HSI._();

  HSI._();

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

  // Services
  final AuthService _authService = MockAuthService();

  // State
  bool _isConfigured = false;
  bool _isRunning = false;
  // ignore: unused_field
  String? _userId;
  // ignore: unused_field
  SynheartConfig? _config;

  // Final HSV stream
  final BehaviorSubject<HumanStateVector> _finalHsvStream =
      BehaviorSubject<HumanStateVector>();

  /// Stream of final HSV (with emotion and focus populated)
  Stream<HumanStateVector> get onStateUpdate => _finalHsvStream.stream;

  /// Configure HSI with app key, user ID, and optional config
  ///
  /// Example:
  /// ```dart
  /// await hsi.configure(
  ///   appKey: 'YOUR_KEY',
  ///   userId: 'user123',
  ///   config: SynheartConfig.defaults(),
  /// );
  /// ```
  Future<void> configure({
    required String appKey,
    required String userId,
    SynheartConfig? config,
  }) async {
    if (_isConfigured) {
      throw StateError('HSI already configured');
    }

    _userId = userId;
    _config = config ?? SynheartConfig.defaults();

    try {
      // 1. Authenticate & get capabilities
      print('[HSI] Authenticating...');
      await _authService.authenticate(
        appKey: appKey,
        userId: userId,
      );

      // 2. Initialize capability module
      print('[HSI] Initializing capability module...');
      _capabilityModule = CapabilityModule();
      await _capabilityModule!.loadDefaults();

      // 3. Initialize consent module
      print('[HSI] Initializing consent module...');
      _consentModule = ConsentModule();

      // 4. Register modules with manager
      _moduleManager.registerModule(_capabilityModule!);
      _moduleManager.registerModule(_consentModule!);

      // 5. Initialize data collection modules
      print('[HSI] Initializing data modules...');
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

      _moduleManager
          .registerModule(_wearModule!, dependsOn: ['capabilities', 'consent']);
      _moduleManager.registerModule(_phoneModule!,
          dependsOn: ['capabilities', 'consent']);
      _moduleManager.registerModule(_behaviorModule!,
          dependsOn: ['capabilities', 'consent']);

      // 6. Initialize HSI Runtime
      print('[HSI] Initializing HSI Runtime...');
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

      // TODO: Cloud & Syni modules
      // if (_config!.enableCloudSync) {
      //   _moduleManager.registerModule(_cloudConnector!, dependsOn: ['hsi_runtime', 'consent']);
      // }
      // if (_config!.enableSyniHooks) {
      //   _moduleManager.registerModule(_syniHooks!, dependsOn: ['hsi_runtime', 'consent']);
      // }

      // 7. Initialize all modules
      print('[HSI] Initializing all modules...');
      await _moduleManager.initializeAll();

      // 8. Set up consent change listeners
      _consentModule!.addListener(_onConsentChanged);

      // 9. Subscribe to final HSV stream
      _hsiRuntimeModule!.finalHsvStream.listen(
        (hsv) => _finalHsvStream.add(hsv),
        onError: (e) => print('[HSI] HSV stream error: $e'),
      );

      _isConfigured = true;
      print('[HSI] Configuration complete');
    } catch (e, stack) {
      print('[HSI] Configuration failed: $e');
      print(stack);
      rethrow;
    }
  }

  /// Start HSI pipeline
  Future<void> start() async {
    if (!_isConfigured) {
      throw StateError('HSI must be configured before starting');
    }

    if (_isRunning) {
      return;
    }

    try {
      print('[HSI] Starting all modules...');
      await _moduleManager.startAll();

      _isRunning = true;
      print('[HSI] HSI pipeline started');
    } catch (e, stack) {
      print('[HSI] Start failed: $e');
      print(stack);
      rethrow;
    }
  }

  /// Stop HSI pipeline
  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    try {
      print('[HSI] Stopping all modules...');
      await _moduleManager.stopAll();

      _isRunning = false;
      print('[HSI] HSI pipeline stopped');
    } catch (e, stack) {
      print('[HSI] Stop failed: $e');
      print(stack);
    }
  }

  /// Get current state (latest HSV)
  HumanStateVector? get currentState {
    return _hsiRuntimeModule?.currentState;
  }

  /// Get behavior module for recording events
  BehaviorModule? get behaviorModule => _behaviorModule;

  /// Get phone module for direct access
  PhoneModule? get phoneModule => _phoneModule;

  /// Get current consent snapshot
  ConsentSnapshot? get currentConsent {
    return _consentModule?.current();
  }

  /// Update consent
  Future<void> updateConsent(ConsentSnapshot consent) async {
    if (_consentModule == null) {
      throw StateError('Consent module not initialized');
    }
    await _consentModule!.updateConsent(consent);
  }

  /// Enable cloud sync (requires cloudUpload consent)
  Future<void> enableCloudSync() async {
    // TODO: Implement cloud sync
    throw UnimplementedError('Cloud sync not yet implemented');
  }

  /// Enable Syni hooks (requires syni consent)
  Future<void> enableSyniHooks() async {
    // TODO: Implement Syni hooks
    throw UnimplementedError('Syni hooks not yet implemented');
  }

  /// Get module statuses (for debugging)
  Map<String, String> getModuleStatuses() {
    final statuses = _moduleManager.getModuleStatuses();
    return statuses.map((key, value) => MapEntry(key, value.name));
  }

  /// Handle consent changes
  void _onConsentChanged(ConsentSnapshot consent) {
    print('[HSI] Consent changed:');
    print('  - Biosignals: ${consent.biosignals}');
    print('  - Behavior: ${consent.behavior}');
    print('  - Motion: ${consent.motion}');
    print('  - Cloud Upload: ${consent.cloudUpload}');
    print('  - Syni: ${consent.syni}');

    // TODO: Notify modules of consent changes
    // When a module's consent is revoked, it should stop or zero out its outputs
  }

  /// Dispose all resources
  Future<void> dispose() async {
    try {
      await stop();
      await _moduleManager.disposeAll();
      await _finalHsvStream.close();

      _consentModule = null;
      _capabilityModule = null;
      _wearModule = null;
      _phoneModule = null;
      _behaviorModule = null;
      _hsiRuntimeModule = null;
      _isConfigured = false;
      _isRunning = false;

      print('[HSI] Disposed');
    } catch (e, stack) {
      print('[HSI] Dispose failed: $e');
      print(stack);
    }
  }
}
