import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:synheart_auth/synheart_auth.dart';
import '../../config/api_endpoints.dart';
import '../../core/logger.dart';
import 'capability_token.dart';
import 'capability_token_fetcher.dart';
import 'capability_verifier.dart';

/// Fetches capability tokens from the server using device-signed requests.
///
/// The device must be registered via [SynheartAuth.registerDevice] before
/// calling [fetch]. The returned token is verified by the caller
/// (either HMAC-verified or trusted as-is depending on config).
class RemoteCapabilityTokenFetcher implements CapabilityTokenFetcher {
  final SynheartAuth _auth;
  final String _appId;
  final String _baseUrl;
  final http.Client _httpClient;

  RemoteCapabilityTokenFetcher({
    required String appId,
    required String baseUrl,
    SynheartAuth? auth,
    http.Client? httpClient,
  })  : _appId = appId,
        _baseUrl = baseUrl,
        _auth = auth ?? SynheartAuth.instance,
        _httpClient = httpClient ?? http.Client();

  @override
  Future<CapabilityToken> fetch() async {
    ApiEndpoints.assertConfigured(_baseUrl, 'DeviceAuthConfig.authBaseUrl');

    const method = 'GET';
    const path = ApiEndpoints.deviceCapabilitiesPath;
    final uri = Uri.parse('$_baseUrl$path');

    final signed = await _auth.signRequest(
      appId: _appId,
      method: method,
      path: path,
      bodyBytes: Uint8List(0),
    );

    SynheartLogger.log('[CapabilityFetcher] Fetching capabilities from $uri');

    final response = await _httpClient.get(
      uri,
      headers: {
        ...signed.toMap(),
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw CapabilityException(
        'Failed to fetch capability token: HTTP ${response.statusCode}',
        code: 'FETCH_FAILED',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return CapabilityToken.fromJson(body);
  }

  void dispose() {
    _httpClient.close();
  }
}
