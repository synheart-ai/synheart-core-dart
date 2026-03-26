import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_endpoints.dart';
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
  final String? refreshToken;
  final String? sessionSecret;
  final bool syncReady;

  const AuthResult({
    required this.subjectId,
    this.accessToken,
    this.refreshToken,
    this.sessionSecret,
    required this.syncReady,
  });
}

/// Manages authentication and token lifecycle (RFC-CORE-0008).
class AuthModule {
  static const int _defaultExpirySeconds = 3600;

  AuthStatus _status = AuthStatus.unauthenticated;
  String? _accessToken;
  String? _sessionSecret;
  Timer? _refreshTimer;
  final TokenStorage _tokenStorage;
  final String _baseUrl;
  final String _appId;

  AuthModule({
    required String appId,
    String baseUrl = ApiEndpoints.defaultAuthBaseUrl,
    TokenStorage? tokenStorage,
  })  : _appId = appId,
        _baseUrl = baseUrl,
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

  /// Token-based auth — exchanges a provider token for Synheart credentials.
  Future<AuthResult> authenticate({
    required String provider,
    required String token,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl${ApiEndpoints.authExchangePath}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'provider': provider,
        'token': token,
        'app_id': _appId,
      }),
    );

    if (response.statusCode != 200) {
      throw AuthError('Authentication failed: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final sid = body['subject_id'] as String;
    final at = body['access_token'] as String;
    final rt = body['refresh_token'] as String;
    final ss = body['session_secret'] as String?;

    _accessToken = at;
    _sessionSecret = ss;

    await _tokenStorage.saveRefreshToken(rt);
    await _tokenStorage.saveSubjectId(sid);
    if (ss != null) {
      await _tokenStorage.saveSessionSecret(ss);
    }

    _status = AuthStatus(
      authenticated: true,
      subjectId: sid,
      provider: provider,
      syncReady: false,
    );

    final expiresIn = body.containsKey('expires_in')
        ? (body['expires_in'] as num).toInt()
        : _defaultExpirySeconds;
    _scheduleRefresh(expiresIn);

    return AuthResult(
      subjectId: sid,
      accessToken: at,
      refreshToken: rt,
      sessionSecret: ss,
      syncReady: false,
    );
  }

  /// Refresh the access token using the stored refresh token.
  Future<void> refreshToken() async {
    final rt = await _tokenStorage.loadRefreshToken();
    if (rt == null) {
      throw AuthError('No refresh token available');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl${ApiEndpoints.authRefreshPath}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': rt}),
    );

    if (response.statusCode != 200) {
      _status = AuthStatus(
        authenticated: false,
        subjectId: _status.subjectId,
        provider: _status.provider,
        syncReady: false,
      );
      throw AuthError('ERR_AUTH_EXPIRED');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    _accessToken = body['access_token'] as String;

    if (body.containsKey('refresh_token')) {
      await _tokenStorage.saveRefreshToken(body['refresh_token'] as String);
    }

    final expiresIn = body.containsKey('expires_in')
        ? (body['expires_in'] as num).toInt()
        : _defaultExpirySeconds;
    _scheduleRefresh(expiresIn);
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
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _accessToken = null;
    _sessionSecret = null;
    await _tokenStorage.clearAll();
    _status = AuthStatus.unauthenticated;
  }

  /// Restore auth state from stored tokens (call on SDK init).
  Future<bool> restoreSession() async {
    final sid = await _tokenStorage.loadSubjectId();
    if (sid == null) return false;

    final rt = await _tokenStorage.loadRefreshToken();
    final ss = await _tokenStorage.loadSessionSecret();
    _sessionSecret = ss;

    if (rt != null) {
      _status = AuthStatus(
        authenticated: true,
        subjectId: sid,
        provider: 'restored',
        syncReady: false,
      );
      try {
        await refreshToken();
        return true;
      } catch (_) {
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

  /// Schedule a proactive token refresh at 80% of the token lifetime.
  void _scheduleRefresh(int expiresInSeconds) {
    _refreshTimer?.cancel();
    final delaySeconds = (expiresInSeconds * 0.8).round();
    _refreshTimer = Timer(Duration(seconds: delaySeconds), () async {
      try {
        await refreshToken();
      } catch (e) {
        // Silent failure — token refresh will be retried on next API call.
      }
    });
  }

  /// Dispose resources. Cancel any pending refresh timer.
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  String _generateUUID() {
    // Simple UUID v4 — in production, use package:uuid
    final r = DateTime.now().microsecondsSinceEpoch;
    return 'anon_${r.toRadixString(16)}';
  }
}

class AuthError implements Exception {
  final String message;
  AuthError(this.message);
  @override
  String toString() => 'AuthError: $message';
}
