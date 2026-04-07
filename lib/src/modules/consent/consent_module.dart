import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/logger.dart';
import '../base/synheart_module.dart';
import '../interfaces/consent_provider.dart';
import '../../config/synheart_config.dart';
import 'consent_token.dart';
import 'consent_profile.dart';

/// Function type for device-signed HTTP requests.
typedef DeviceRequestSigner = Future<Map<String, String>> Function({
  required String method,
  required String path,
  required List<int> bodyBytes,
});

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

  final BehaviorSubject<ConsentSnapshot> _consentStream =
      BehaviorSubject<ConsentSnapshot>();

  ConsentSnapshot? _currentConsent;

  /// Callbacks for when consent changes
  final List<void Function(ConsentSnapshot)> _listeners = [];

  // Cloud consent service integration (optional)
  ConsentConfig? _consentConfig;
  ConsentToken? _currentToken;
  Timer? _tokenRefreshTimer;

  // Device ID storage
  static const _deviceIdKey = 'synheart_device_id';
  final FlutterSecureStorage _deviceIdStorage = const FlutterSecureStorage();
  final Uuid _uuid = const Uuid();

  ConsentModule({ConsentConfig? consentConfig})
    : _consentConfig = consentConfig;

  /// Set the device request signer.
  /// Called by Synheart entry point once device auth is initialized.
  /// Retained for API compatibility; actual signing is handled by the core runtime bridge.
  void setDeviceSigner(DeviceRequestSigner signer) {
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

  /// Load consent defaults.
  ///
  /// Per documentation: All consents default to false.
  /// SDK should return empty/null state until consent is granted.
  /// Actual persistence is handled by the core runtime bridge.
  Future<void> loadConsent() async {
    // Default to all denied — explicit consent required.
    _currentConsent = ConsentSnapshot.none();
    SynheartLogger.log(
      '[ConsentModule] Using defaults (all denied - explicit consent required)',
    );
    _consentStream.add(_currentConsent!);
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
      phoneContext: type == ConsentType.phoneContext ? granted : _currentConsent!.phoneContext,
      cloudUpload: type == ConsentType.cloudUpload
          ? granted
          : _currentConsent!.cloudUpload,
      syni: type == ConsentType.syni ? granted : _currentConsent!.syni,
      focusEstimation: type == ConsentType.focusEstimation
          ? granted
          : _currentConsent!.focusEstimation,
      emotionEstimation: type == ConsentType.emotionEstimation
          ? granted
          : _currentConsent!.emotionEstimation,
      vendorSync: type == ConsentType.vendorSync
          ? granted
          : _currentConsent!.vendorSync,
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
    final fields = {
      'biosignals': (oldConsent.biosignals, newConsent.biosignals),
      'behavior': (oldConsent.behavior, newConsent.behavior),
      'phoneContext': (oldConsent.phoneContext, newConsent.phoneContext),
      'focusEstimation': (oldConsent.focusEstimation, newConsent.focusEstimation),
      'emotionEstimation': (oldConsent.emotionEstimation, newConsent.emotionEstimation),
      'cloudUpload': (oldConsent.cloudUpload, newConsent.cloudUpload),
      'vendorSync': (oldConsent.vendorSync, newConsent.vendorSync),
      'syni': (oldConsent.syni, newConsent.syni),
    };
    for (final e in fields.entries) {
      if (e.value.$1 != e.value.$2) {
        SynheartLogger.log('Consent changed: ${e.key} ${e.value.$2 ? "granted" : "revoked"}');
      }
    }
  }

  /// Get available consent profiles from cloud service.
  ///
  /// This stub remains for API compatibility.
  Future<List<ConsentProfile>> getAvailableProfiles() async {
    SynheartLogger.log('[ConsentModule] getAvailableProfiles() called');

    if (_consentConfig == null || !(_consentConfig!.isConfigured)) {
      throw StateError(
        'Consent service not configured. Provide ConsentConfig with appId and appApiKey.',
      );
    }

    // Return empty list — callers should use the bridge directly.
    SynheartLogger.log('[ConsentModule] getAvailableProfiles: returning empty list');
    return [];
  }

  /// Request consent by issuing a token for the selected profile.
  ///
  /// This updates local consent state based on the profile.
  Future<ConsentToken> requestConsent(ConsentProfile profile) async {
    if (_consentConfig == null) {
      throw StateError(
        'Consent service not configured. Provide ConsentConfig with appId and appApiKey.',
      );
    }

    // Update local consent snapshot based on profile
    await _updateConsentFromProfile(profile);

    SynheartLogger.log(
      '[ConsentModule] Consent updated for profile: ${profile.id}',
    );

    // Return a placeholder token — actual token issuance is handled by bridge.
    final token = ConsentToken(
      token: '',
      profileId: profile.id,
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
      scopes: const [],
      claims: const {},
    );
    _currentToken = token;
    return token;
  }

  /// Request consent token directly by profile id (without fetching profiles first).
  /// Useful when integrator already knows the consent_profile_id.
  ///
  /// [grantedChannels] and [tier] enable granular consent (RFC-CONSENT-GRANULAR-001).
  /// When null, all profile channels are granted at the local tier (backward compat).
  ///
  Future<ConsentToken> requestConsentByProfileId(
    String profileId, {
    String? ipAddress,
    String? userAgent,
    ConsentChannels? grantedChannels,
    ConsentTier? tier,
    bool? cloud,
    bool? vendorSync,
    bool research = false,
  }) async {
    if (_consentConfig == null) {
      throw StateError(
        'Consent service not configured. Provide ConsentConfig with appId and appApiKey.',
      );
    }

    // Return a placeholder token — actual token issuance is handled by bridge.
    final token = ConsentToken(
      token: '',
      profileId: profileId,
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
      scopes: const [],
      claims: const {},
    );
    _currentToken = token;
    SynheartLogger.log(
      '[ConsentModule] Consent updated for profile: $profileId (tier: ${tier?.name ?? "legacy"})',
    );
    return token;
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

  /// Revoke consent (clears token locally).
  Future<void> revokeConsent() async {
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
      await updateConsent(ConsentSnapshot.none(explicitlyDenied: true));
    }

    SynheartLogger.log('[ConsentModule] Consent revoked');
  }

  /// Mark consent as explicitly denied by user
  ///
  /// This should be called when user declines consent in the UI,
  /// to distinguish from "never asked" (pending) state.
  Future<void> denyConsent() async {
    _currentToken = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;

    // Update consent snapshot to mark as explicitly denied
    await updateConsent(ConsentSnapshot.none(explicitlyDenied: true));

    SynheartLogger.log('[ConsentModule] Consent explicitly denied by user');
  }

  /// Refresh consent token if it's about to expire.
  Future<ConsentToken?> refreshTokenIfNeeded() async {
    if (_currentToken == null || _consentConfig == null) {
      return null;
    }

    // Only refresh if token expires soon
    if (!_currentToken!.expiresSoon()) {
      return _currentToken;
    }

    return null;
  }

  /// Update local consent snapshot from profile
  Future<void> _updateConsentFromProfile(
    ConsentProfile profile, {
    ConsentChannels? grantedChannels,
    ConsentTier? tier,
  }) async {
    // Use granted channels if provided, otherwise use all profile channels
    final effectiveChannels = grantedChannels ?? profile.channels;

    final snapshot = ConsentSnapshot(
      biosignals:
          effectiveChannels.biosignals.vitals ||
          effectiveChannels.biosignals.cardioAdvanced ||
          effectiveChannels.biosignals.neuromuscular ||
          effectiveChannels.biosignals.wearableMotion ||
          effectiveChannels.biosignals.sleep,
      behavior: effectiveChannels.behavior.enabled,
      phoneContext:
          effectiveChannels.phoneContext.deviceMotion ||
          effectiveChannels.phoneContext.deviceContext ||
          effectiveChannels.phoneContext.systemState,
      cloudUpload: profile.cloudEnabled,
      syni: false, // Not in profile yet
      focusEstimation: effectiveChannels.interpretation.focusEstimation,
      emotionEstimation: effectiveChannels.interpretation.emotionEstimation,
      vendorSync: profile.vendorSyncEnabled,
      timestamp: DateTime.now(),
      explicitlyDenied: false, // User accepted, so not denied
      tier: tier ?? ConsentTier.local,
      channels: effectiveChannels,
    );

    await updateConsent(snapshot);
  }

  /// Load token from storage.
  Future<void> _loadTokenFromStorage() async {
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
    _tokenRefreshTimer = Timer(checkInterval, () async {
      // Check if token needs refresh
      final refreshed = await refreshTokenIfNeeded();
      if (refreshed != null && refreshed != _currentToken) {
        // Token was refreshed, restart timer with new token
        _currentToken = refreshed;
        _startTokenRefreshTimer();
      } else if (_currentToken?.isExpired == true) {
        // Token expired and couldn't refresh
        SynheartLogger.log('[ConsentModule] Token expired and refresh failed');
        _tokenRefreshTimer?.cancel();
        _tokenRefreshTimer = null;
      } else {
        // Token still valid, schedule next check
        _startTokenRefreshTimer();
      }
    });
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
    await _consentStream.close();
    _listeners.clear();
    _currentConsent = null;
    _currentToken = null;
  }
}
