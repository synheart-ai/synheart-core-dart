import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/consent_provider.dart';
import '../../config/synheart_config.dart';
import 'consent_storage.dart';
import 'consent_token_storage.dart';
import 'consent_api_client.dart';
import 'consent_token.dart';
import 'consent_profile.dart';

/// Consent Module
///
/// Single source of truth for user consent on the device.
/// Gates collection and export of biosignals, behavior, motion/context,
/// cloud upload, and Syni personalization.
///
/// Supports both local consent (on-device only) and cloud consent service
/// integration (with JWT tokens for cloud uploads).
class ConsentModule extends BaseSynheartModule implements ConsentProvider {
  @override
  String get moduleId => 'consent';

  final ConsentStorage _storage;
  final BehaviorSubject<ConsentSnapshot> _consentStream =
      BehaviorSubject<ConsentSnapshot>();

  ConsentSnapshot? _currentConsent;

  /// Callbacks for when consent changes
  final List<void Function(ConsentSnapshot)> _listeners = [];

  // Cloud consent service integration (optional)
  ConsentConfig? _consentConfig;
  ConsentAPIClient? _apiClient;
  ConsentTokenStorage? _tokenStorage;
  ConsentToken? _currentToken;
  Timer? _tokenRefreshTimer;

  // Device ID storage
  static const _deviceIdKey = 'synheart_device_id';
  final FlutterSecureStorage _deviceIdStorage = const FlutterSecureStorage();
  final Uuid _uuid = const Uuid();

  ConsentModule({
    ConsentStorage? storage,
    ConsentConfig? consentConfig,
  })  : _storage = storage ?? ConsentStorage(),
        _consentConfig = consentConfig {
    if (consentConfig?.isConfigured ?? false) {
      _tokenStorage = ConsentTokenStorage();
      _apiClient = ConsentAPIClient(
        baseUrl: consentConfig!.consentServiceUrl,
        appId: consentConfig.appId!,
        appApiKey: consentConfig.appApiKey!,
      );
    }
  }

  @override
  ConsentSnapshot current() {
    if (_currentConsent == null) {
      throw StateError('Consent module not initialized');
    }
    return _currentConsent!;
  }

  @override
  Stream<ConsentSnapshot> observe() => _consentStream.stream;

  @override
  Future<void> updateConsent(ConsentSnapshot newConsent) async {
    final oldConsent = _currentConsent;
    _currentConsent = newConsent;

    // Persist to storage
    await _storage.save(newConsent);

    // Emit to stream
    _consentStream.add(newConsent);

    // Notify listeners
    _notifyListeners(newConsent);

    // Check for consent revocations and log
    if (oldConsent != null) {
      _logConsentChanges(oldConsent, newConsent);
    }
  }

  /// Register a listener for consent changes
  void addListener(void Function(ConsentSnapshot) listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(void Function(ConsentSnapshot) listener) {
    _listeners.remove(listener);
  }

  /// Load consent from storage or use defaults
  ///
  /// Per documentation: All consents default to false.
  /// SDK should return empty/null state until consent is granted.
  Future<void> loadConsent() async {
    final stored = await _storage.load();

    if (stored != null) {
      _currentConsent = stored;
      _consentStream.add(stored);
      SynheartLogger.log(
        '[ConsentModule] Loaded consent from storage: biosignals=${stored.biosignals}, behavior=${stored.behavior}, motion=${stored.motion}, cloudUpload=${stored.cloudUpload}',
      );
    } else {
      // No stored consent, use defaults
      // Per documentation: All consents default to false - explicit consent required
      _currentConsent = ConsentSnapshot.none();
      SynheartLogger.log(
        '[ConsentModule] No stored consent, using defaults (all denied - explicit consent required)',
      );
      _consentStream.add(_currentConsent!);
    }
  }

  /// Grant all consents
  Future<void> grantAll() async {
    await updateConsent(ConsentSnapshot.all());
  }

  /// Revoke all consents
  Future<void> revokeAll() async {
    await updateConsent(ConsentSnapshot.none());
  }

  /// Update a specific consent type
  Future<void> updateConsentType(ConsentType type, bool granted) async {
    if (_currentConsent == null) {
      throw StateError('Consent module not initialized');
    }

    final updated = _currentConsent!.copyWith(
      biosignals: type == ConsentType.biosignals
          ? granted
          : _currentConsent!.biosignals,
      behavior: type == ConsentType.behavior
          ? granted
          : _currentConsent!.behavior,
      motion: type == ConsentType.motion ? granted : _currentConsent!.motion,
      cloudUpload: type == ConsentType.cloudUpload
          ? granted
          : _currentConsent!.cloudUpload,
      syni: type == ConsentType.syni ? granted : _currentConsent!.syni,
      timestamp: DateTime.now(),
    );

    await updateConsent(updated);
  }

  /// Notify all registered listeners
  void _notifyListeners(ConsentSnapshot consent) {
    for (final listener in _listeners) {
      try {
        listener(consent);
      } catch (e) {
        SynheartLogger.log('Error notifying consent listener: $e', error: e);
      }
    }
  }

  /// Log consent changes for debugging
  void _logConsentChanges(
    ConsentSnapshot oldConsent,
    ConsentSnapshot newConsent,
  ) {
    if (oldConsent.biosignals != newConsent.biosignals) {
      SynheartLogger.log(
        'Consent changed: biosignals ${newConsent.biosignals ? "granted" : "revoked"}',
      );
    }
    if (oldConsent.behavior != newConsent.behavior) {
      SynheartLogger.log(
        'Consent changed: behavior ${newConsent.behavior ? "granted" : "revoked"}',
      );
    }
    if (oldConsent.motion != newConsent.motion) {
      SynheartLogger.log(
        'Consent changed: motion ${newConsent.motion ? "granted" : "revoked"}',
      );
    }
    if (oldConsent.cloudUpload != newConsent.cloudUpload) {
      SynheartLogger.log(
        'Consent changed: cloudUpload ${newConsent.cloudUpload ? "granted" : "revoked"}',
      );
    }
    if (oldConsent.syni != newConsent.syni) {
      SynheartLogger.log(
        'Consent changed: syni ${newConsent.syni ? "granted" : "revoked"}',
      );
    }
  }

  /// Get available consent profiles from cloud service
  ///
  /// Returns cached profiles if available and not expired, otherwise fetches from API.
  Future<List<ConsentProfile>> getAvailableProfiles() async {
    SynheartLogger.log('[ConsentModule] getAvailableProfiles() called');
    
    if (_apiClient == null) {
      SynheartLogger.log(
        '[ConsentModule] ERROR: API client not initialized. ConsentConfig missing or not configured.',
      );
      throw StateError(
        'Consent service not configured. Provide ConsentConfig with appId and appApiKey.',
      );
    }

    SynheartLogger.log(
      '[ConsentModule] API client configured: baseUrl=${_consentConfig?.consentServiceUrl}, appId=${_consentConfig?.appId}',
    );

    // Try to load from cache first
    SynheartLogger.log('[ConsentModule] Checking for cached profiles...');
    final cached = await _tokenStorage?.loadCachedProfiles();
    if (cached != null && cached.isNotEmpty) {
      SynheartLogger.log(
        '[ConsentModule] Using cached profiles (count: ${cached.length})',
      );
      for (final profile in cached) {
        SynheartLogger.log(
          '[ConsentModule] Cached profile: id=${profile.id}, name=${profile.name}, isDefault=${profile.isDefault}',
        );
      }
      return cached;
    }

    SynheartLogger.log('[ConsentModule] No valid cached profiles, fetching from API...');

    // Fetch from API
    try {
      SynheartLogger.log(
        '[ConsentModule] Calling API: GET /api/v1/apps/${_consentConfig!.appId}/consent-profiles',
      );
      final profiles = await _apiClient!.getAvailableProfiles();
      
      SynheartLogger.log(
        '[ConsentModule] Successfully fetched ${profiles.length} profiles from API',
      );
      
      for (final profile in profiles) {
        SynheartLogger.log(
          '[ConsentModule] Profile: id=${profile.id}, name=${profile.name}, description=${profile.description}, isDefault=${profile.isDefault}',
        );
        SynheartLogger.log(
          '[ConsentModule] Profile channels: biosignals.vitals=${profile.channels.biosignals.vitals}, biosignals.sleep=${profile.channels.biosignals.sleep}, behavior=${profile.channels.behavior.enabled}, cloudEnabled=${profile.cloudEnabled}',
        );
      }
      
      // Cache the profiles
      SynheartLogger.log('[ConsentModule] Caching profiles...');
      await _tokenStorage?.cacheProfiles(profiles);
      SynheartLogger.log('[ConsentModule] Profiles cached successfully');
      
      return profiles;
    } catch (e, stackTrace) {
      SynheartLogger.log(
        '[ConsentModule] ERROR fetching profiles: $e',
        error: e,
        stackTrace: stackTrace,
      );
      SynheartLogger.log(
        '[ConsentModule] Stack trace: $stackTrace',
      );
      rethrow;
    }
  }

  /// Request consent by issuing a token for the selected profile
  ///
  /// This should be called after the user has selected a consent profile.
  Future<ConsentToken> requestConsent(ConsentProfile profile) async {
    if (_apiClient == null || _consentConfig == null) {
      throw StateError(
        'Consent service not configured. Provide ConsentConfig with appId and appApiKey.',
      );
    }

    // Get or generate persistent device ID
    final deviceId = _consentConfig!.deviceId ?? await _getOrGenerateDeviceId();

    // Determine platform
    final platform = _consentConfig!.platform;

    try {
      // Issue token from consent service
      final token = await _apiClient!.issueToken(
        deviceId: deviceId,
        consentProfileId: profile.id,
        platform: platform,
        userId: _consentConfig!.userId,
        region: _consentConfig!.region,
      );

      // Store token
      await _tokenStorage?.saveToken(token);
      _currentToken = token;

      // Update local consent snapshot based on profile
      await _updateConsentFromProfile(profile);

      // Start token refresh timer
      _startTokenRefreshTimer();

      SynheartLogger.log(
        '[ConsentModule] Consent token issued for profile: ${profile.id}',
      );

      return token;
    } catch (e) {
      SynheartLogger.log(
        '[ConsentModule] Error requesting consent: $e',
        error: e,
      );
      rethrow;
    }
  }

  /// Check current consent status
  ConsentStatus checkConsentStatus() {
    // Check if user explicitly denied consent
    if (_currentConsent?.explicitlyDenied == true) {
      return ConsentStatus.denied;
    }

    if (_currentToken == null) {
      // Try to load from storage
      _loadTokenFromStorage();
      if (_currentToken == null) {
        return ConsentStatus.pending;
      }
    }

    if (_currentToken!.isExpired) {
      return ConsentStatus.expired;
    }

    return ConsentStatus.granted;
  }

  /// Get current valid consent token
  ConsentToken? getCurrentToken() {
    if (_currentToken == null) {
      _loadTokenFromStorage();
    }

    if (_currentToken != null && _currentToken!.isValid) {
      return _currentToken;
    }

    return null;
  }

  /// Revoke consent (clears token and notifies cloud)
  Future<void> revokeConsent() async {
    if (_currentToken != null && _apiClient != null && _consentConfig != null) {
      try {
        final deviceId = _consentConfig!.deviceId ?? await _getOrGenerateDeviceId();
        await _apiClient!.revokeConsent(
          deviceId: deviceId,
          profileId: _currentToken!.profileId,
        );
      } catch (e) {
        SynheartLogger.log(
          '[ConsentModule] Error notifying cloud of revocation: $e',
          error: e,
        );
        // Continue with local revocation even if cloud notification fails
      }
    }

    // Clear token locally
    await _tokenStorage?.deleteToken();
    _currentToken = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;

    // Update consent snapshot to deny cloud upload and mark as explicitly denied
    if (_currentConsent != null) {
      await updateConsent(
        _currentConsent!.copyWith(
          cloudUpload: false,
          explicitlyDenied: true,
          timestamp: DateTime.now(),
        ),
      );
    } else {
      // If no consent snapshot exists, create one with explicit denial
      await updateConsent(
        ConsentSnapshot.none(explicitlyDenied: true),
      );
    }

    SynheartLogger.log('[ConsentModule] Consent revoked');
  }

  /// Mark consent as explicitly denied by user
  ///
  /// This should be called when user declines consent in the UI,
  /// to distinguish from "never asked" (pending) state.
  Future<void> denyConsent() async {
    // Clear any existing token
    await _tokenStorage?.deleteToken();
    _currentToken = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;

    // Update consent snapshot to mark as explicitly denied
    await updateConsent(
      ConsentSnapshot.none(explicitlyDenied: true),
    );

    SynheartLogger.log('[ConsentModule] Consent explicitly denied by user');
  }

  /// Refresh consent token if it's about to expire
  Future<ConsentToken?> refreshTokenIfNeeded() async {
    if (_currentToken == null || _apiClient == null || _consentConfig == null) {
      return null;
    }

    // Only refresh if token expires soon
    if (!_currentToken!.expiresSoon()) {
      return _currentToken;
    }

    try {
      // Get current profile ID from token
      final profileId = _currentToken!.profileId;

      // Fetch profiles to get the profile
      final profiles = await getAvailableProfiles();
      final profile = profiles.firstWhere(
        (p) => p.id == profileId,
        orElse: () => throw StateError('Profile $profileId not found'),
      );

      // Request new token
      final newToken = await requestConsent(profile);
      return newToken;
    } catch (e) {
      SynheartLogger.log(
        '[ConsentModule] Error refreshing token: $e',
        error: e,
      );
      return null;
    }
  }

  /// Update local consent snapshot from profile
  Future<void> _updateConsentFromProfile(ConsentProfile profile) async {
    final snapshot = ConsentSnapshot(
      biosignals: profile.channels.biosignals.vitals ||
          profile.channels.biosignals.sleep,
      behavior: profile.channels.behavior.enabled,
      motion: profile.channels.phoneContext.motion ||
          profile.channels.phoneContext.screenState,
      cloudUpload: profile.cloudEnabled,
      syni: false, // Not in profile yet
      timestamp: DateTime.now(),
      explicitlyDenied: false, // User accepted, so not denied
    );

    await updateConsent(snapshot);
  }

  /// Load token from storage
  Future<void> _loadTokenFromStorage() async {
    if (_tokenStorage != null) {
      final token = await _tokenStorage!.loadToken();
      if (token != null && token.isValid) {
        _currentToken = token;
        _startTokenRefreshTimer();
      } else if (token != null && token.isExpired) {
        // Clean up expired token
        await _tokenStorage!.deleteToken();
        _currentToken = null;
      }
    }
  }

  /// Start token refresh timer
  ///
  /// Optimized to check at appropriate intervals based on token expiry time.
  /// Checks 5 minutes before expiry, then every minute if close to expiry.
  void _startTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();

    if (_currentToken == null) {
      return;
    }

    // Calculate when to check next based on token expiry
    final now = DateTime.now();
    final expiresAt = _currentToken!.expiresAt;
    final timeUntilExpiry = expiresAt.difference(now);
    final refreshThreshold = const Duration(minutes: 5);

    // If token expires within 5 minutes, check every minute
    // Otherwise, check 5 minutes before expiry
    Duration checkInterval;
    if (timeUntilExpiry <= refreshThreshold) {
      // Close to expiry - check every minute
      checkInterval = const Duration(minutes: 1);
    } else {
      // Far from expiry - check 5 minutes before expiry
      final timeUntilRefresh = timeUntilExpiry - refreshThreshold;
      // Cap at 1 hour max interval to avoid very long timers
      checkInterval = timeUntilRefresh > const Duration(hours: 1)
          ? const Duration(hours: 1)
          : timeUntilRefresh;
    }

    SynheartLogger.log(
      '[ConsentModule] Token refresh timer: checking in ${checkInterval.inMinutes} minutes',
    );

    // Schedule next check
    _tokenRefreshTimer = Timer(
      checkInterval,
      () async {
        // Check if token needs refresh
        final refreshed = await refreshTokenIfNeeded();
        if (refreshed != null && refreshed != _currentToken) {
          // Token was refreshed, restart timer with new token
          _currentToken = refreshed;
          _startTokenRefreshTimer();
        } else if (_currentToken?.isExpired == true) {
          // Token expired and couldn't refresh
          SynheartLogger.log(
            '[ConsentModule] Token expired and refresh failed',
          );
          _tokenRefreshTimer?.cancel();
          _tokenRefreshTimer = null;
        } else {
          // Token still valid, schedule next check
          _startTokenRefreshTimer();
        }
      },
    );
  }

  /// Get or generate persistent device ID (UUID v4 format)
  ///
  /// Device ID is stored in secure storage and persists across app restarts.
  /// This ensures the same device is identified consistently.
  Future<String> _getOrGenerateDeviceId() async {
    // Try to load existing device ID
    final existingId = await _deviceIdStorage.read(key: _deviceIdKey);
    if (existingId != null && existingId.isNotEmpty) {
      return existingId;
    }

    // Generate new UUID v4
    final deviceId = _uuid.v4();
    
    // Store in secure storage for persistence
    await _deviceIdStorage.write(key: _deviceIdKey, value: deviceId);
    
    SynheartLogger.log('[ConsentModule] Generated new device ID: $deviceId');
    return deviceId;
  }


  @override
  Future<void> onInitialize() async {
    await loadConsent();

    // Load token from storage if consent service is configured
    if (_tokenStorage != null) {
      await _loadTokenFromStorage();
    }
  }

  @override
  Future<void> onStart() async {
    // Start token refresh timer if we have a token
    if (_currentToken != null) {
      _startTokenRefreshTimer();
    }
  }

  @override
  Future<void> onStop() async {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
  }

  @override
  Future<void> onDispose() async {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _apiClient?.dispose();
    await _consentStream.close();
    _listeners.clear();
    _currentConsent = null;
    _currentToken = null;
  }
}
