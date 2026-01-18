import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/logger.dart';
import 'consent_profile.dart';
import 'consent_token.dart';

/// REST client for consent service API
class ConsentAPIClient {
  final String baseUrl;
  final String appId;
  final String appApiKey;
  final http.Client _httpClient;

  ConsentAPIClient({
    required this.baseUrl,
    required this.appId,
    required this.appApiKey,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Fetch available consent profiles for this app
  ///
  /// GET /api/v1/apps/{app_id}/consent-profiles?active_only=true
  Future<List<ConsentProfile>> getAvailableProfiles({
    bool activeOnly = true,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/apps/$appId/consent-profiles')
          .replace(queryParameters: {
        'active_only': activeOnly.toString(),
      });

      SynheartLogger.log(
        '[ConsentAPI] Fetching profiles from: $uri',
      );
      SynheartLogger.log(
        '[ConsentAPI] Request headers: Authorization=Bearer ***, Content-Type=application/json',
      );
      SynheartLogger.log(
        '[ConsentAPI] Request parameters: active_only=$activeOnly',
      );

      final stopwatch = Stopwatch()..start();
      final response = await _httpClient.get(
        uri,
        headers: {
          'Authorization': 'Bearer $appApiKey',
          'Content-Type': 'application/json',
        },
      );
      stopwatch.stop();

      SynheartLogger.log(
        '[ConsentAPI] Response received: statusCode=${response.statusCode}, duration=${stopwatch.elapsedMilliseconds}ms',
      );

      if (response.statusCode == 200) {
        SynheartLogger.log(
          '[ConsentAPI] Response body length: ${response.body.length} bytes',
        );
        
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        SynheartLogger.log(
          '[ConsentAPI] Parsed response body keys: ${body.keys.join(", ")}',
        );
        
        final profilesJson = body['profiles'] as List<dynamic>?;
        if (profilesJson == null) {
          SynheartLogger.log(
            '[ConsentAPI] WARNING: Response body does not contain "profiles" key',
          );
          SynheartLogger.log(
            '[ConsentAPI] Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
          );
          throw ConsentAPIException('Invalid response: missing "profiles" key');
        }
        
        SynheartLogger.log(
          '[ConsentAPI] Found ${profilesJson.length} profiles in response',
        );
        
        final profiles = profilesJson
            .map((p) => ConsentProfile.fromJson(p as Map<String, dynamic>))
            .toList();
        
        SynheartLogger.log(
          '[ConsentAPI] Successfully parsed ${profiles.length} profiles',
        );
        
        return profiles;
      } else if (response.statusCode == 401) {
        SynheartLogger.log(
          '[ConsentAPI] ERROR: 401 Unauthorized - Invalid app API key',
        );
        SynheartLogger.log(
          '[ConsentAPI] Response body: ${response.body}',
        );
        throw ConsentAPIException('Invalid app API key');
      } else if (response.statusCode == 404) {
        SynheartLogger.log(
          '[ConsentAPI] ERROR: 404 Not Found - App not found',
        );
        SynheartLogger.log(
          '[ConsentAPI] Response body: ${response.body}',
        );
        throw ConsentAPIException('App not found');
      } else {
        SynheartLogger.log(
          '[ConsentAPI] ERROR: Unexpected status code ${response.statusCode}',
        );
        SynheartLogger.log(
          '[ConsentAPI] Response body: ${response.body}',
        );
        throw ConsentAPIException(
          'Failed to fetch profiles: ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      if (e is ConsentAPIException) {
        SynheartLogger.log(
          '[ConsentAPI] ConsentAPIException: ${e.message}',
        );
        rethrow;
      }
      SynheartLogger.log(
        '[ConsentAPI] Network/parsing error: $e',
        error: e,
        stackTrace: stackTrace,
      );
      SynheartLogger.log(
        '[ConsentAPI] Stack trace: $stackTrace',
      );
      throw ConsentAPIException('Network error: $e');
    }
  }

  /// Issue SDK token after user consent
  ///
  /// POST /api/v1/sdk/consent-token
  Future<ConsentToken> issueToken({
    required String deviceId,
    required String consentProfileId,
    required String platform,
    String? userId,
    String? region,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/sdk/consent-token');

      final body = {
        'app_id': appId,
        'device_id': deviceId,
        'platform': platform,
        'consent_profile_id': consentProfileId,
        if (userId != null) 'user_id': userId,
        if (region != null) 'region': region,
      };

      final response = await _httpClient.post(
        uri,
        headers: {
          'Authorization': 'Bearer $appApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        SynheartLogger.log(
          '[ConsentAPI] Token response received: statusCode=${response.statusCode}',
        );
        SynheartLogger.log(
          '[ConsentAPI] Response body: ${response.body}',
        );
        
        final bodyJson = jsonDecode(response.body) as Map<String, dynamic>;
        SynheartLogger.log(
          '[ConsentAPI] Parsed response keys: ${bodyJson.keys.join(", ")}',
        );
        
        // Log each field before parsing
        SynheartLogger.log(
          '[ConsentAPI] token field: ${bodyJson['token']} (type: ${bodyJson['token']?.runtimeType})',
        );
        SynheartLogger.log(
          '[ConsentAPI] access_token field: ${bodyJson['access_token']} (type: ${bodyJson['access_token']?.runtimeType})',
        );
        SynheartLogger.log(
          '[ConsentAPI] expires_at field: ${bodyJson['expires_at']} (type: ${bodyJson['expires_at']?.runtimeType})',
        );
        SynheartLogger.log(
          '[ConsentAPI] expires_in field: ${bodyJson['expires_in']} (type: ${bodyJson['expires_in']?.runtimeType})',
        );
        SynheartLogger.log(
          '[ConsentAPI] profile_id field: ${bodyJson['profile_id']} (type: ${bodyJson['profile_id']?.runtimeType})',
        );
        SynheartLogger.log(
          '[ConsentAPI] consent_profile_id field: ${bodyJson['consent_profile_id']} (type: ${bodyJson['consent_profile_id']?.runtimeType})',
        );
        SynheartLogger.log(
          '[ConsentAPI] token_type field: ${bodyJson['token_type']} (type: ${bodyJson['token_type']?.runtimeType})',
        );
        SynheartLogger.log(
          '[ConsentAPI] scopes field: ${bodyJson['scopes']} (type: ${bodyJson['scopes']?.runtimeType})',
        );
        
        try {
          final token = ConsentToken.fromJson(bodyJson);
          SynheartLogger.log(
            '[ConsentAPI] Successfully parsed consent token: profileId=${token.profileId}, expiresAt=${token.expiresAt}',
          );
          return token;
        } catch (e, stackTrace) {
          SynheartLogger.log(
            '[ConsentAPI] ERROR parsing token from JSON: $e',
            error: e,
            stackTrace: stackTrace,
          );
          SynheartLogger.log(
            '[ConsentAPI] Full response body for debugging: ${response.body}',
          );
          rethrow;
        }
      } else if (response.statusCode == 401) {
        throw ConsentAPIException('Invalid app API key');
      } else if (response.statusCode == 400) {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
        throw ConsentAPIException(
          errorBody['message'] as String? ?? 'Invalid request',
        );
      } else {
        throw ConsentAPIException(
          'Failed to issue token: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is ConsentAPIException) {
        rethrow;
      }
      SynheartLogger.log(
        '[ConsentAPI] Error issuing token: $e',
        error: e,
      );
      throw ConsentAPIException('Network error: $e');
    }
  }

  /// Revoke consent (notify cloud service)
  ///
  /// POST /api/v1/sdk/consent-revoke
  Future<void> revokeConsent({
    required String deviceId,
    required String profileId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/sdk/consent-revoke');

      final body = {
        'app_id': appId,
        'device_id': deviceId,
        'profile_id': profileId,
      };

      final response = await _httpClient.post(
        uri,
        headers: {
          'Authorization': 'Bearer $appApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        SynheartLogger.log(
          '[ConsentAPI] Failed to revoke consent: ${response.statusCode}',
        );
        // Don't throw - revocation is best-effort
      }
    } catch (e) {
      SynheartLogger.log(
        '[ConsentAPI] Error revoking consent: $e',
        error: e,
      );
      // Don't throw - revocation is best-effort
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Exception thrown by consent API client
class ConsentAPIException implements Exception {
  final String message;

  ConsentAPIException(this.message);

  @override
  String toString() => 'ConsentAPIException: $message';
}

