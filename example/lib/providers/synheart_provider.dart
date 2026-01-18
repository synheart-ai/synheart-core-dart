import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:synheart_core/synheart_core.dart';

/// Unified provider for all Synheart SDK state management
class SynheartProvider extends ChangeNotifier {
  // SDK State
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _userId;
  String? _errorMessage;

  // Feature States
  bool _cloudSyncEnabled = false;
  bool _emotionEnabled = false;
  bool _focusEnabled = false;

  // Data Streams
  HumanStateVector? _latestHSV;
  EmotionState? _latestEmotion;
  FocusState? _latestFocus;
  BehaviorState? _latestBehavior;
  HSIAxes? _latestAxes;

  // Stream Subscriptions
  StreamSubscription<HumanStateVector>? _hsvSubscription;
  StreamSubscription<EmotionState>? _emotionSubscription;
  StreamSubscription<FocusState>? _focusSubscription;

  // Consent State
  ConsentStatus _consentStatus = ConsentStatus.pending;
  ConsentToken? _currentToken;
  List<ConsentProfile> _availableProfiles = [];
  bool _needsConsent = false;
  Map<String, String> _consentInfo = {};

  // Config
  SynheartConfig? sdkConfig;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  String? get userId => _userId;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  bool get cloudSyncEnabled => _cloudSyncEnabled;
  bool get emotionEnabled => _emotionEnabled;
  bool get focusEnabled => _focusEnabled;

  HumanStateVector? get latestHSV => _latestHSV;
  EmotionState? get latestEmotion => _latestEmotion;
  FocusState? get latestFocus => _latestFocus;
  BehaviorState? get latestBehavior => _latestBehavior;
  HSIAxes? get latestAxes => _latestAxes;

  ConsentStatus get consentStatus => _consentStatus;
  ConsentToken? get currentToken => _currentToken;
  List<ConsentProfile> get availableProfiles => _availableProfiles;
  bool get hasConsentToken => _currentToken != null && _currentToken!.isValid;
  bool get needsConsent => _needsConsent;
  Map<String, String> get consentInfo => _consentInfo;

  /// Get current consent status map
  Map<String, bool> get consentStatusMap {
    if (!_isInitialized) {
      return {};
    }
    return Synheart.getConsentStatusMap();
  }

  /// Get current consent snapshot
  ConsentSnapshot get currentConsentSnapshot {
    if (!_isInitialized) {
      return ConsentSnapshot.none();
    }
    // Access current consent through the consent status map
    final statusMap = consentStatusMap;
    return ConsentSnapshot(
      biosignals: statusMap['biosignals'] ?? false,
      behavior: statusMap['behavior'] ?? false,
      motion: statusMap['motion'] ?? false,
      cloudUpload: statusMap['cloudUpload'] ?? false,
      syni: statusMap['syni'] ?? false,
      timestamp: DateTime.now(),
    );
  }

  /// Initialize SDK
  Future<void> initialize({
    required String userId,
    String? appKey,
    SynheartConfig? config,
  }) async {
    if (_isInitialized || _isInitializing) {
      return;
    }

    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Create config with ConsentConfig and CloudConfig if not provided
      final finalConfig =
          config ??
          SynheartConfig(
            wearConfig: WearConfig(),
            phoneConfig: PhoneConfig(),
            behaviorConfig: BehaviorConfig(),
            
            consentConfig: ConsentConfig(
              consentServiceUrl: 'https://consent-service-dev.synheart.io',
              appId: 'test-app-123',
              appApiKey:
                  'synheart_sk_live_3lzNKf-4kSqOzX5L6qQatecmI614brZGJqo6NO3Q5Tw',
              deviceId:
                  'example_device_${DateTime.now().millisecondsSinceEpoch}',
              platform: 'flutter',
              userId: userId,
              region: 'US',
            ),
            cloudConfig: CloudConfig(
              baseUrl: 'https://api.synheart.com',
              tenantId: 'example_tenant',
              hmacSecret: 'example_hmac_secret',
              subjectId: userId,
              instanceId:
                  'example_instance_${DateTime.now().millisecondsSinceEpoch}',
            ),
          );

      sdkConfig = finalConfig;

      await Synheart.initialize(
        userId: userId,
        appKey: appKey ?? 'mock_app_key',
        config: finalConfig,
      );

      _userId = userId;
      _isInitialized = true;
      _isInitializing = false;
      _errorMessage = null;

      // Start listening to HSV updates
      _startHSVListening();

      // Check consent status
      _checkConsentStatus();

      // Check if consent is needed
      await _checkConsentNeeds();

      notifyListeners();
    } catch (e) {
      _isInitializing = false;
      _errorMessage = 'Initialization failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Start listening to HSV updates
  void _startHSVListening() {
    _hsvSubscription?.cancel();
    _hsvSubscription = Synheart.onHSVUpdate.listen((hsv) {
      _latestHSV = hsv;
      _latestBehavior = hsv.behavior;
      _latestAxes = hsv.meta.axes;
      notifyListeners();
    });
  }

  /// Enable cloud sync (requires consent)
  Future<void> enableCloudSync() async {
    if (!_isInitialized) {
      throw StateError('SDK must be initialized first');
    }

    try {
      // Check if consent is already granted
      _checkConsentStatus();
      if (!hasConsentToken) {
        throw StateError('Consent token required. Please grant consent first.');
      }

      await Synheart.enableCloud();
      _cloudSyncEnabled = true;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to enable cloud sync: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Disable cloud sync
  Future<void> disableCloudSync() async {
    if (!_cloudSyncEnabled) {
      return;
    }

    try {
      await Synheart.disableCloud();
      _cloudSyncEnabled = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to disable cloud sync: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Enable emotion module
  Future<void> enableEmotion() async {
    if (!_isInitialized) {
      throw StateError('SDK must be initialized first');
    }

    if (_emotionEnabled) {
      return;
    }

    try {
      await Synheart.enableEmotion();
      _emotionEnabled = true;
      _startEmotionListening();
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to enable emotion: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Disable emotion module
  Future<void> disableEmotion() async {
    if (!_emotionEnabled) {
      return;
    }

    try {
      _emotionSubscription?.cancel();
      _emotionSubscription = null;
      _emotionEnabled = false;
      _latestEmotion = null;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to disable emotion: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Start listening to emotion updates
  void _startEmotionListening() {
    _emotionSubscription?.cancel();
    _emotionSubscription = Synheart.onEmotionUpdate.listen((emotion) {
      _latestEmotion = emotion;
      notifyListeners();
    });
  }

  /// Enable focus module
  Future<void> enableFocus() async {
    if (!_isInitialized) {
      throw StateError('SDK must be initialized first');
    }

    if (_focusEnabled) {
      return;
    }

    try {
      await Synheart.enableFocus();
      _focusEnabled = true;
      _startFocusListening();
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to enable focus: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Disable focus module
  Future<void> disableFocus() async {
    if (!_focusEnabled) {
      return;
    }

    try {
      _focusSubscription?.cancel();
      _focusSubscription = null;
      _focusEnabled = false;
      _latestFocus = null;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to disable focus: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Start listening to focus updates
  void _startFocusListening() {
    _focusSubscription?.cancel();
    _focusSubscription = Synheart.onFocusUpdate.listen((focus) {
      _latestFocus = focus;
      notifyListeners();
    });
  }

  /// Check consent status
  void _checkConsentStatus() {
    try {
      _consentStatus = Synheart.getConsentStatus();
      _currentToken = Synheart.getCurrentConsentToken();
      notifyListeners();
    } catch (e) {
      // Ignore errors if consent module not initialized
    }
  }

  /// Check if consent is needed and get consent info
  Future<void> _checkConsentNeeds() async {
    try {
      _needsConsent = await Synheart.needsConsent();
      if (_needsConsent) {
        _consentInfo = await Synheart.getConsentInfo();

        // If CloudConfig is provided, fetch profiles
        if (sdkConfig?.cloudConfig != null) {
          try {
            _availableProfiles = await Synheart.getAvailableConsentProfiles();
          } catch (e) {
            // If profile fetch fails, we can still show consent UI
            // Log error but don't throw
          }
        }
      }
    } catch (e) {
      _needsConsent = false;
    }
  }

  /// Grant consent with user's choices
  Future<void> grantConsent({
    required bool biosignals,
    required bool behavior,
    required bool motion,
    required bool cloudUpload,
    String? profileId,
  }) async {
    try {
      await Synheart.grantConsent(
        biosignals: biosignals,
        behavior: behavior,
        motion: motion,
        cloudUpload: cloudUpload,
        profileId: profileId,
      );

      // Update consent status
      _checkConsentStatus();
      _needsConsent = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to grant consent: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Fetch available consent profiles
  Future<void> fetchConsentProfiles() async {
    try {
      _availableProfiles = await Synheart.getAvailableConsentProfiles();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to fetch profiles: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Request consent with selected profile
  Future<ConsentToken?> requestConsent(ConsentProfile profile) async {
    try {
      // Set up UI provider to return the selected profile
      Synheart.setConsentUIProvider((profiles) async => profile);

      final token = await Synheart.requestConsent();
      _currentToken = token;
      _checkConsentStatus();
      notifyListeners();
      return token;
    } catch (e) {
      _errorMessage = 'Failed to request consent: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Revoke consent
  Future<void> revokeConsent() async {
    try {
      await Synheart.revokeConsent();
      _currentToken = null;
      _cloudSyncEnabled = false;
      _checkConsentStatus();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to revoke consent: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Revoke consent for a specific feature type
  Future<void> revokeConsentType(String consentType) async {
    try {
      await Synheart.revokeConsentType(consentType);
      _checkConsentStatus();

      // Update local state based on revoked consent
      if (consentType == 'cloudUpload') {
        _cloudSyncEnabled = false;
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to revoke consent for $consentType: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Stop SDK
  Future<void> stop() async {
    if (!_isInitialized) {
      return;
    }

    try {
      // Cancel subscriptions first
      await _hsvSubscription?.cancel();
      _hsvSubscription = null;
      await _emotionSubscription?.cancel();
      _emotionSubscription = null;
      await _focusSubscription?.cancel();
      _focusSubscription = null;

      // Dispose the SDK to allow re-initialization
      // This fully cleans up and resets the configuration state
      await Synheart.dispose();

      // Reset state
      _isInitialized = false;
      _emotionEnabled = false;
      _focusEnabled = false;
      _cloudSyncEnabled = false;

      // Clear cached data
      _latestHSV = null;
      _latestEmotion = null;
      _latestFocus = null;
      _latestBehavior = null;
      _latestAxes = null;

      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to stop SDK: $e';
      notifyListeners();
    }
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _hsvSubscription?.cancel();
    _emotionSubscription?.cancel();
    _focusSubscription?.cancel();
    // Only dispose SDK if it's still initialized
    // (if stop() was called, it already disposed the SDK)
    if (_isInitialized) {
      Synheart.dispose();
    }
    super.dispose();
  }
}
