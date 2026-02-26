import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:synheart_core/synheart_core.dart';
import 'package:synheart_core/src/modules/wear/wear_source_handler.dart';
import 'package:synheart_core/src/modules/behavior/behavior_events.dart';
import 'package:synheart_core/src/models/behavior_session_results.dart';

/// Unified provider for all Synheart SDK state management
class SynheartProvider extends ChangeNotifier {
  // SDK State
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _userId;
  String? _errorMessage;

  // Feature States
  bool _cloudSyncEnabled = false;

  // Data Streams
  String? _latestHSI;

  // Stream Subscriptions
  StreamSubscription<String>? _hsiSubscription;

  // Consent State
  ConsentStatus _consentStatus = ConsentStatus.pending;
  ConsentToken? _currentToken;
  List<ConsentProfile> _availableProfiles = [];
  bool _needsConsent = false;
  Map<String, String> _consentInfo = {};

  // Config
  SynheartConfig? sdkConfig;

  // On-demand collection state
  List<WearSample> _recentWearSamples = [];
  List<BehaviorEvent> _recentBehaviorEvents = [];
  String? _activeBehaviorSessionId;
  BehaviorSessionResults? _lastSessionResults;
  WindowType? _selectedWindow;
  Map<String, dynamic>? _queriedFeatures;
  bool _isGameActive = false;
  double? _latestGameHR;

  // Stream subscriptions for raw data
  StreamSubscription<WearSample>? _wearSampleSubscription;
  StreamSubscription<BehaviorEvent>? _behaviorEventSubscription;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  String? get userId => _userId;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  bool get cloudSyncEnabled => _cloudSyncEnabled;

  String? get latestHSI => _latestHSI;
  /// Backward-compatible alias for UI screens
  String? get latestHSV => _latestHSI;

  ConsentStatus get consentStatus => _consentStatus;
  ConsentToken? get currentToken => _currentToken;
  List<ConsentProfile> get availableProfiles => _availableProfiles;
  bool get hasConsentToken => _currentToken != null && _currentToken!.isValid;
  bool get needsConsent => _needsConsent;
  Map<String, String> get consentInfo => _consentInfo;

  // On-demand collection getters
  List<WearSample> get recentWearSamples => _recentWearSamples;
  List<BehaviorEvent> get recentBehaviorEvents => _recentBehaviorEvents;
  String? get activeBehaviorSessionId => _activeBehaviorSessionId;
  BehaviorSessionResults? get lastSessionResults => _lastSessionResults;
  WindowType? get selectedWindow => _selectedWindow;
  Map<String, dynamic>? get queriedFeatures => _queriedFeatures;
  bool get isGameActive => _isGameActive;
  double? get latestGameHR => _latestGameHR;

  /// Runtime diagnostics from the native synheart-runtime bridge.
  Map<String, dynamic> get runtimeDiagnostics {
    if (!_isInitialized) {
      return {
        'isAvailable': false,
        'version': null,
        'frameCount': 0,
        'lastQuality': null,
      };
    }
    return Synheart.runtimeDiagnostics();
  }

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
      phoneContext: statusMap['phoneContext'] ?? false,
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
      // NOTE: To use consent service features, you must provide your own appId and appApiKey.
      // See EXAMPLE_APP_SETUP.md for instructions on how to obtain these credentials.
      final finalConfig =
          config ??
          SynheartConfig(
            allowUnsignedCapabilities: true,
            wearConfig: WearConfig(),
            phoneConfig: PhoneConfig(),
            behaviorConfig: BehaviorConfig(),
            // // ConsentConfig now defaults to dev consent service URL
            // // To enable consent service features, provide your own appId and appApiKey:
            // consentConfig: ConsentConfig(
            //   appId: 'app-123',
            //   appApiKey: 'synheart_sk_live_3lzNKf-4kSqOzX5L6qQatecmI614brZGJqo6NO3Q5Tw',
            //   platform: 'flutter',
            //   userId: userId,
            //   region: 'US',
            // ),
            // // CloudConfig is optional - only needed for cloud sync features
            // // To enable cloud sync, provide your own credentials:
            // cloudConfig: CloudConfig(
            //   baseUrl: 'https://api.synheart.com',  // Or your custom API endpoint
            //   tenantId: 'your-tenant-id',           // Your tenant identifier (kept for backward compatibility)
            //   hmacSecret: 'your-hmac-secret',        // HMAC secret for request signing
            //   subjectId: userId,                     // Pseudonymous user identifier (becomes user_id in payload)
            //   instanceId: 'unique-instance-id',      // Unique instance identifier
            //   apiKey: 'your-api-key',
            // ),
          );

      sdkConfig = finalConfig;

      await Synheart.initialize(
        userId: userId,
        appKey: appKey ?? 'mock_app_key',
        config: finalConfig,
        autoStart: false, // Don't start automatically for demo
      );

      _userId = userId;
      _isInitialized = true;
      _isInitializing = false;
      _errorMessage = null;

      // Start listening to HSI updates
      _startHSIListening();

      // Start listening to raw data streams
      _startRawDataListening();

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

  /// Start listening to HSI updates
  void _startHSIListening() {
    _hsiSubscription?.cancel();
    _hsiSubscription = Synheart.onHSIUpdate.listen((hsi) {
      _latestHSI = hsi;
      notifyListeners();
    });
  }

  /// Start listening to raw data streams
  void _startRawDataListening() {
    // Listen to wear samples
    _wearSampleSubscription?.cancel();
    try {
      _wearSampleSubscription = Synheart.wearSampleStream.listen((sample) {
        _recentWearSamples.add(sample);
        // Keep only last 100 samples
        if (_recentWearSamples.length > 100) {
          _recentWearSamples.removeAt(0);
        }
        // Update game HR if game is active
        if (_isGameActive && sample.hr != null) {
          _latestGameHR = sample.hr;
        }
        notifyListeners();
      });
    } catch (e) {
      // Stream not available yet (module not started)
    }

    // Listen to behavior events
    _behaviorEventSubscription?.cancel();
    try {
      _behaviorEventSubscription = Synheart.behaviorEventStream.listen((event) {
        _recentBehaviorEvents.add(event);
        // Keep only last 100 events
        if (_recentBehaviorEvents.length > 100) {
          _recentBehaviorEvents.removeAt(0);
        }
        notifyListeners();
      });
    } catch (e) {
      // Stream not available yet (module not started)
    }
  }

  /// Enable cloud sync (requires consent)
  void enableCloudSync() {
    if (!_isInitialized) {
      throw StateError('SDK must be initialized first');
    }

    try {
      // Check if consent is already granted
      _checkConsentStatus();
      if (!hasConsentToken) {
        throw StateError('Consent token required. Please grant consent first.');
      }

      Synheart.activate(SynheartFeature.cloud);
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
  void disableCloudSync() {
    if (!_cloudSyncEnabled) {
      return;
    }

    try {
      Synheart.deactivate(SynheartFeature.cloud);
      _cloudSyncEnabled = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to disable cloud sync: $e';
      notifyListeners();
      rethrow;
    }
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
    required bool phoneContext,
    required bool cloudUpload,
    String? profileId,
  }) async {
    try {
      await Synheart.grantConsent(
        biosignals: biosignals,
        behavior: behavior,
        phoneContext: phoneContext,
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
      await _hsiSubscription?.cancel();
      _hsiSubscription = null;

      // Dispose the SDK to allow re-initialization
      // This fully cleans up and resets the configuration state
      await Synheart.dispose();

      // Reset state
      _isInitialized = false;
      _cloudSyncEnabled = false;

      // Clear cached data
      _latestHSI = null;

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

  // On-demand collection methods
  Future<void> startWearCollection({Duration? interval}) async {
    try {
      await Synheart.startWearCollection(interval: interval);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to start wear collection: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopWearCollection() async {
    try {
      await Synheart.stopWearCollection();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to stop wear collection: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> startBehaviorCollection() async {
    try {
      await Synheart.startBehaviorCollection();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to start behavior collection: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopBehaviorCollection() async {
    try {
      await Synheart.stopBehaviorCollection();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to stop behavior collection: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> startPhoneCollection() async {
    try {
      await Synheart.startPhoneCollection();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to start phone collection: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopPhoneCollection() async {
    try {
      await Synheart.stopPhoneCollection();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to stop phone collection: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<String> startBehaviorSession() async {
    try {
      final sessionId = await Synheart.startBehaviorSession();
      _activeBehaviorSessionId = sessionId;
      notifyListeners();
      return sessionId;
    } catch (e) {
      _errorMessage = 'Failed to start behavior session: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<BehaviorSessionResults> stopBehaviorSession() async {
    if (_activeBehaviorSessionId == null) {
      throw StateError('No active behavior session');
    }
    try {
      final results = await Synheart.stopBehaviorSession(
        _activeBehaviorSessionId!,
      );
      _lastSessionResults = results;
      _activeBehaviorSessionId = null;
      notifyListeners();
      return results;
    } catch (e) {
      _errorMessage = 'Failed to stop behavior session: $e';
      _activeBehaviorSessionId = null;
      notifyListeners();
      rethrow;
    }
  }

  void setSelectedWindow(WindowType window) {
    _selectedWindow = window;
    notifyListeners();
  }

  Future<void> queryWearFeatures() async {
    final window = _selectedWindow ?? WindowType.window30s;
    try {
      final features = await Synheart.getWearFeatures(window);
      if (features != null) {
        _queriedFeatures = {
          'hrAverage': features.hrAverage,
          'hrMin': features.hrMin,
          'hrMax': features.hrMax,
          'hrvRmssd': features.hrvRmssd,
          'hrvSdnn': features.hrvSdnn,
          'pnn50': features.pnn50,
          'meanRrMs': features.meanRrMs,
          'motionIndex': features.motionIndex,
          'respRate': features.respRate,
        };
      } else {
        _queriedFeatures = {'error': 'No features available'};
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to query wear features: $e';
      notifyListeners();
    }
  }

  Future<void> queryBehaviorFeatures() async {
    final window = _selectedWindow ?? WindowType.window30s;
    try {
      final features = await Synheart.getBehaviorFeatures(window);
      if (features != null) {
        _queriedFeatures = {
          'tapRateNorm': features.tapRateNorm,
          'keystrokeRateNorm': features.keystrokeRateNorm,
          'scrollVelocityNorm': features.scrollVelocityNorm,
          'idleRatio': features.idleRatio,
          'switchRateNorm': features.switchRateNorm,
          'burstiness': features.burstiness,
          'sessionFragmentation': features.sessionFragmentation,
          'notificationLoad': features.notificationLoad,
          'distractionScore': features.distractionScore,
          'focusHint': features.focusHint,
        };
      } else {
        _queriedFeatures = {'error': 'No features available'};
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to query behavior features: $e';
      notifyListeners();
    }
  }

  Future<void> queryPhoneFeatures() async {
    final window = _selectedWindow ?? WindowType.window30s;
    try {
      final features = await Synheart.getPhoneFeatures(window);
      if (features != null) {
        _queriedFeatures = {
          'motionLevel': features.motionLevel,
          'appSwitchRate': features.appSwitchRate,
          'screenOnRatio': features.screenOnRatio,
          'notificationRate': features.notificationRate,
        };
      } else {
        _queriedFeatures = {'error': 'No features available'};
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to query phone features: $e';
      notifyListeners();
    }
  }

  void clearWearSamples() {
    _recentWearSamples.clear();
    notifyListeners();
  }

  void clearBehaviorEvents() {
    _recentBehaviorEvents.clear();
    notifyListeners();
  }

  Future<void> startGameSession() async {
    try {
      // Start wear collection at 1s interval for game
      await Synheart.startWearCollection(interval: const Duration(seconds: 1));
      _isGameActive = true;
      _latestGameHR = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to start game session: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopGameSession() async {
    try {
      await Synheart.stopWearCollection();
      _isGameActive = false;
      _latestGameHR = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to stop game session: $e';
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _hsiSubscription?.cancel();
    _wearSampleSubscription?.cancel();
    _behaviorEventSubscription?.cancel();
    // Only dispose SDK if it's still initialized
    // (if stop() was called, it already disposed the SDK)
    if (_isInitialized) {
      Synheart.dispose();
    }
    super.dispose();
  }
}
