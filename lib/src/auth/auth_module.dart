import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:synheart_auth/synheart_auth.dart' as device_auth;
import '../modules/consent/consent_api_client.dart';
import 'token_storage.dart';

/// Authentication status (RFC-CORE-0008).
class AuthStatus {
  final bool authenticated;
  final String? subjectId;
  final String? provider;
  final bool syncReady;

  const AuthStatus({
    required this.authenticated,
    this.subjectId,
    this.provider,
    required this.syncReady,
  });

  static const unauthenticated = AuthStatus(
    authenticated: false,
    syncReady: false,
  );
}

/// Result of an authentication attempt.
class AuthResult {
  final String subjectId;
  final String? accessToken;
  final String? sessionSecret;
  final bool syncReady;

  const AuthResult({
    required this.subjectId,
    this.accessToken,
    this.sessionSecret,
    required this.syncReady,
  });
}

/// Manages authentication via device attestation + consent token (RFC-CORE-0008).
///
/// Flow: synheart-auth.registerDevice() → POST /consent/v1/sdk/consent-token → JWT
/// No refresh tokens — re-attestation on expiry.
class AuthModule {
  AuthStatus _status = AuthStatus.unauthenticated;
  String? _accessToken;
  String? _sessionSecret;
  String? _lastProfileId;
  Timer? _reattestTimer;
  final TokenStorage _tokenStorage;
  final String _appId;
  final String _platform;
  final device_auth.SynheartAuth _auth;
  final ConsentAPIClient _consentClient;

  AuthModule({
    required String appId,
    required device_auth.SynheartAuth auth,
    required ConsentAPIClient consentClient,
    String platform = 'mobile',
    TokenStorage? tokenStorage,
  })  : _appId = appId,
        _auth = auth,
        _consentClient = consentClient,
        _platform = platform,
        _tokenStorage = tokenStorage ?? TokenStorage();

  AuthStatus get status => _status;
  String? get subjectId => _status.subjectId;
  bool get isAuthenticated => _status.authenticated;
  String? get accessToken => _accessToken;
  String? get sessionSecret => _sessionSecret;

  /// Anonymous auth — generates a local subject_id, no sync capability.
  Future<AuthResult> authenticateAnonymous() async {
    final id = _generateUUID();
    await _tokenStorage.saveSubjectId(id);

    _status = AuthStatus(
      authenticated: false,
      subjectId: id,
      provider: 'anonymous',
      syncReady: false,
    );

    return AuthResult(
      subjectId: id,
      syncReady: false,
    );
  }

  /// Attestation-based auth — register device, then obtain consent token.
  ///
  /// 1. Ensure device is registered via synheart-auth
  /// 2. Request consent token (server verifies device attestation)
  /// 3. Store JWT in-memory, extract subject_id from claims
  /// 4. Generate or load session_secret for URK derivation
  /// 5. Schedule re-attestation 60s before token expiry
  Future<AuthResult> authenticate({
    required String consentProfileId,
  }) async {
    // Step 1: Ensure device is registered
    final isRegistered = await _auth.isRegistered(_appId);
    if (!isRegistered) {
      await _auth.registerDevice(_appId);
    }

    // Step 2: Get device ID
    final deviceId = await _auth.getDeviceId(_appId);
    if (deviceId == null) {
      throw AuthError('Device registration succeeded but no device_id returned');
    }

    // Step 3: Request consent token (signed by device via ConsentAPIClient)
    final consentToken = await _consentClient.issueToken(
      deviceId: deviceId,
      consentProfileId: consentProfileId,
      platform: _platform,
    );

    // Step 4: Store JWT in-memory only
    _accessToken = consentToken.token;

    // Step 5: Extract subject_id from JWT claims (fallback to device_id)
    final subjectId = consentToken.claims['sub'] as String? ?? deviceId;
    await _tokenStorage.saveSubjectId(subjectId);

    // Step 6: Generate or load session_secret (32 random bytes, locally generated)
    var ss = await _tokenStorage.loadSessionSecret();
    if (ss == null) {
      ss = _generateSessionSecret();
      await _tokenStorage.saveSessionSecret(ss);
    }
    _sessionSecret = ss;

    // Step 7: Persist consent profile ID for restore
    _lastProfileId = consentProfileId;
    await _tokenStorage.saveConsentProfileId(consentProfileId);

    // Step 8: Schedule re-attestation 60s before expiry
    _scheduleReattestation(consentToken.expiresAt);

    // Step 9: Update status
    _status = AuthStatus(
      authenticated: true,
      subjectId: subjectId,
      provider: 'device',
      syncReady: false,
    );

    return AuthResult(
      subjectId: subjectId,
      accessToken: _accessToken,
      sessionSecret: ss,
      syncReady: false,
    );
  }

  /// Mark sync as ready (called after URK provisioning).
  void markSyncReady() {
    _status = AuthStatus(
      authenticated: _status.authenticated,
      subjectId: _status.subjectId,
      provider: _status.provider,
      syncReady: true,
    );
  }

  /// Log out — clear tokens and reset state.
  Future<void> logout() async {
    _reattestTimer?.cancel();
    _reattestTimer = null;
    _accessToken = null;
    _sessionSecret = null;
    _lastProfileId = null;
    await _tokenStorage.clearAll();
    _status = AuthStatus.unauthenticated;
  }

  /// Restore auth state from stored credentials (call on SDK init).
  ///
  /// If the device is registered and a consent profile is saved,
  /// requests a fresh consent token (re-attestation).
  Future<bool> restoreSession() async {
    final sid = await _tokenStorage.loadSubjectId();
    if (sid == null) return false;

    final ss = await _tokenStorage.loadSessionSecret();
    _sessionSecret = ss;

    final profileId = await _tokenStorage.loadConsentProfileId();
    _lastProfileId = profileId;

    final isRegistered = await _auth.isRegistered(_appId);
    if (isRegistered && profileId != null) {
      try {
        await authenticate(consentProfileId: profileId);
        return true;
      } catch (_) {
        // Re-attestation failed — offline or server issue.
        // Keep subject_id for local operations.
        _status = AuthStatus(
          authenticated: false,
          subjectId: sid,
          provider: 'device',
          syncReady: false,
        );
        return false;
      }
    }

    // Anonymous session
    _status = AuthStatus(
      authenticated: false,
      subjectId: sid,
      provider: 'anonymous',
      syncReady: false,
    );
    return true;
  }

  /// Schedule re-attestation 60 seconds before token expiry.
  void _scheduleReattestation(DateTime expiresAt) {
    _reattestTimer?.cancel();
    final delay = expiresAt.difference(DateTime.now()) - const Duration(seconds: 60);
    if (delay.isNegative) return;
    _reattestTimer = Timer(delay, () async {
      if (_lastProfileId != null) {
        try {
          await authenticate(consentProfileId: _lastProfileId!);
        } catch (_) {
          // Silent failure — will retry on next API call.
        }
      }
    });
  }

  /// Dispose resources. Cancel any pending re-attestation timer.
  void dispose() {
    _reattestTimer?.cancel();
    _reattestTimer = null;
  }

  String _generateUUID() {
    final r = DateTime.now().microsecondsSinceEpoch;
    return 'anon_${r.toRadixString(16)}';
  }

  /// Generate a 32-byte random session secret, base64 encoded.
  String _generateSessionSecret() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Encode(bytes);
  }
}

class AuthError implements Exception {
  final String message;
  AuthError(this.message);
  @override
  String toString() => 'AuthError: $message';
}
