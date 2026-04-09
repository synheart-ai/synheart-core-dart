import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:synheart_wear/synheart_wear.dart' show WearMetrics, logDebug, logWarning, logError;

/// Garmin Cloud Provider for Synheart Wear SDK
///
/// Connects to Garmin Health API via backend connector service.
/// Implements OAuth2 PKCE flow with intermediate redirect per documentation.
class GarminProvider {
  // Storage keys
  static const String _userIdKey = 'garmin_user_id';
  static const String _baseUrlKey = 'sdk_base_url';
  static const String _appIdKey = 'sdk_app_id';
  static const String _apiKeyKey = 'sdk_api_key';
  static const String _projectIdKey = 'sdk_project_id';
  static const String _redirectUriKey = 'sdk_redirect_uri';

  // Default values
  static const String defaultBaseUrl = 'https://api.synheart.ai/wear/v1';
  static const String defaultRedirectUri = 'synheart://oauth/callback';

  String baseUrl;
  String? redirectUri;
  String appId; // REQUIRED
  String apiKey; // REQUIRED - x-api-key on every request
  String? projectId; // Optional - for Garmin data queries
  String? userId;
  final bool _baseUrlExplicitlyProvided;

  /// Base URL for all API requests (auth, data, events).
  String get _apiBase {
    final b = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return b;
  }

  // SSE subscription state removed — RAMEN is the sole real-time channel.

  GarminProvider({
    String? baseUrl,
    String? appId,
    String? apiKey,
    String? projectId,
    String? redirectUri,
    this.userId,
    bool loadFromStorage = true,
  }) : baseUrl = baseUrl ?? defaultBaseUrl,
       appId = appId ?? 'app_test_ios_XvHE1g',
       apiKey = apiKey ?? '',
       projectId = projectId,
       redirectUri = redirectUri ?? defaultRedirectUri,
       _baseUrlExplicitlyProvided = baseUrl != null {
    logDebug('🔧 GarminProvider initialized:');
    logDebug('  baseUrl: $baseUrl');
    logDebug('  appId: $appId');
    logDebug('  redirectUri: $redirectUri');
    logDebug('  userId: $userId');
    logDebug('  projectId: $projectId');
    logDebug('  loadFromStorage: $loadFromStorage');
    logDebug('  baseUrl explicitly provided: $_baseUrlExplicitlyProvided');
    if (loadFromStorage) {
      _loadFromStorage();
    }
    logDebug(
      '✅ GarminProvider ready - final baseUrl: ${this.baseUrl}, appId: ${this.appId}',
    );
  }

  /// Load configuration and userId from local storage
  Future<void> _loadFromStorage() async {
    try {
      logDebug('💾 [STORAGE] Loading configuration from storage...');
      final prefs = await SharedPreferences.getInstance();

      // Load configuration
      final savedBaseUrl = prefs.getString(_baseUrlKey);
      final savedAppId = prefs.getString(_appIdKey);
      final savedApiKey = prefs.getString(_apiKeyKey);
      final savedProjectId = prefs.getString(_projectIdKey);
      final savedRedirectUri = prefs.getString(_redirectUriKey);

      logDebug('💾 [STORAGE] Loaded from storage:');
      logDebug('  savedBaseUrl: $savedBaseUrl');
      logDebug('  savedAppId: $savedAppId');
      logDebug('  savedRedirectUri: $savedRedirectUri');

      if (savedBaseUrl != null) {
        final isDeprecatedUrl = savedBaseUrl.contains(
          'synheart-wear-service-leatest.onrender.com',
        );
        if (_baseUrlExplicitlyProvided) {
          if (isDeprecatedUrl) {
            logWarning(
              '🔄 [STORAGE] Migrating stored baseUrl (keeping explicit baseUrl)',
            );
            await prefs.setString(_baseUrlKey, defaultBaseUrl);
          }
          logDebug('  ✅ Keeping explicitly provided baseUrl: $baseUrl');
        } else {
          if (isDeprecatedUrl) {
            logWarning(
              '🔄 [STORAGE] Migrating baseUrl from deprecated value to default',
            );
            baseUrl = defaultBaseUrl;
            await prefs.setString(_baseUrlKey, defaultBaseUrl);
          } else {
            baseUrl = savedBaseUrl;
            logDebug('  ✅ Using saved baseUrl: $baseUrl');
          }
        }
      }
      if (savedAppId != null) {
        appId = savedAppId;
        logDebug('  ✅ Using saved appId: $appId');
      }
      if (savedApiKey != null) {
        apiKey = savedApiKey;
        logDebug('  ✅ Using saved apiKey');
      }
      if (savedProjectId != null) {
        projectId = savedProjectId;
        logDebug('  ✅ Using saved projectId: $projectId');
      }
      if (savedRedirectUri != null) {
        redirectUri = savedRedirectUri;
        logDebug('  ✅ Using saved redirectUri: $redirectUri');
      }

      // Load userId
      final savedUserId = prefs.getString(_userIdKey);
      logDebug('  savedUserId: $savedUserId');
      if (savedUserId != null) {
        userId = savedUserId;
        logDebug('  ✅ Using saved userId: $userId');
      }
      logDebug('✅ [STORAGE] Configuration loaded successfully');
    } catch (e, stackTrace) {
      logError(
        '⚠️ [STORAGE] Failed to load from storage, using defaults',
        e,
        stackTrace,
      );
      // Silently fail - use provided/default values
    }
  }

  /// Save userId to local storage
  Future<void> saveUserId(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, userId);
      this.userId = userId;
    } catch (e) {
      // Silently fail
    }
  }

  /// Load userId from local storage
  Future<String?> loadUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString(_userIdKey);
      if (savedUserId != null) {
        userId = savedUserId;
        return savedUserId;
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }

  /// Clear userId from local storage
  Future<void> clearUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userIdKey);
      userId = null;
    } catch (e) {
      // Silently fail
    }
  }

  /// Security headers for every request (Managed OAuth v2).
  Map<String, String> _authHeaders() {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (appId.isNotEmpty) h['x-app-id'] = appId;
    if (apiKey.isNotEmpty) h['x-api-key'] = apiKey;
    return h;
  }

  /// Save configuration to local storage
  Future<void> saveConfiguration({
    String? baseUrl,
    String? appId,
    String? apiKey,
    String? projectId,
    String? redirectUri,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (baseUrl != null) {
        await prefs.setString(_baseUrlKey, baseUrl);
        this.baseUrl = baseUrl;
      }

      if (appId != null) {
        await prefs.setString(_appIdKey, appId);
        this.appId = appId;
      }

      if (apiKey != null) {
        await prefs.setString(_apiKeyKey, apiKey);
        this.apiKey = apiKey;
      }

      if (projectId != null) {
        await prefs.setString(_projectIdKey, projectId);
        this.projectId = projectId;
      } else if (projectId == null) {
        await prefs.remove(_projectIdKey);
        this.projectId = null;
      }

      if (redirectUri != null) {
        await prefs.setString(_redirectUriKey, redirectUri);
        this.redirectUri = redirectUri;
      }
    } catch (e) {
      // Silently fail
    }
  }

  /// Load configuration from local storage
  Future<Map<String, String?>> loadConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'baseUrl': prefs.getString(_baseUrlKey),
        'appId': prefs.getString(_appIdKey),
        'apiKey': prefs.getString(_apiKeyKey),
        'projectId': prefs.getString(_projectIdKey),
        'redirectUri': prefs.getString(_redirectUriKey),
      };
    } catch (e) {
      return {};
    }
  }

  /// Call when app receives success from return URL deep link (Managed OAuth v2).
  /// Real-time Garmin data is delivered via RAMEN gRPC when app is active.
  Future<void> markConnected(String userId) async {
    await saveUserId(userId);
  }

  /// Reload configuration and userId from storage
  Future<void> reloadFromStorage() async {
    await _loadFromStorage();
  }

  /// Managed OAuth v2: POST /auth/connect/garmin with app_id, user_id.
  /// Returns authorization_url and state. Callback handled by wear service; app calls [markConnected] on return URL success.
  Future<Map<String, String>> initiateOAuthConnection({String? userId}) async {
    final effectiveUserId = userId ?? this.userId;
    logWarning('🔐 [AUTH] Starting initiateOAuthConnection (Garmin)');
    logDebug('  baseUrl: $baseUrl _apiBase: $_apiBase');
    logDebug('  appId: $appId');
    logDebug('  userId: $effectiveUserId');

    final serviceUrl = Uri.parse('$_apiBase/auth/connect/garmin');

    final requestBody = <String, dynamic>{
      'app_id': appId,
      if (effectiveUserId != null && effectiveUserId.isNotEmpty)
        'user_id': effectiveUserId,
    };

    logWarning('📡 [AUTH] POST to: $serviceUrl');
    logDebug('📤 [AUTH] Request body: $requestBody');

    try {
      final response = await http.post(
        serviceUrl,
        headers: _authHeaders(),
        body: jsonEncode(requestBody),
      );

      logWarning('📥 [AUTH] Response status: ${response.statusCode}');
      logDebug('📥 [AUTH] Response headers: ${response.headers}');
      logWarning('📥 [AUTH] Response body: ${response.body}');

      if (response.statusCode != 200) {
        logError(
          '❌ [AUTH] Failed to initiate Garmin OAuth connection',
          Exception('Status ${response.statusCode}'),
          StackTrace.current,
        );
        throw Exception(
          'Failed to initiate Garmin OAuth connection (${response.statusCode}): ${response.body}',
        );
      }

      final json = jsonDecode(response.body);
      logDebug('📋 [AUTH] Parsed JSON response: $json');

      final String? authorizationUrl = json['authorization_url'] as String?;
      final String? state = json['state'] as String?;

      if (authorizationUrl == null || authorizationUrl.isEmpty) {
        logError(
          '❌ [AUTH] authorization_url is missing in response',
          Exception('Empty authorization_url'),
          StackTrace.current,
        );
        throw Exception('authorization_url is missing in response');
      }

      if (state == null || state.isEmpty) {
        logError(
          '❌ [AUTH] state is missing in response',
          Exception('Empty state'),
          StackTrace.current,
        );
        throw Exception('state is missing in response');
      }

      logWarning(
        '✅ [AUTH] Successfully obtained Garmin authorization URL and state',
      );
      return {'authorization_url': authorizationUrl, 'state': state};
    } catch (e, stackTrace) {
      logError('❌ [AUTH] Error in initiateOAuthConnection: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Start OAuth flow: initiate connection, get URL, and launch browser.
  /// [userId] optional; passed to POST /auth/connect/garmin.
  Future<Map<String, String>> startOAuthFlow({String? userId}) async {
    logWarning('🚀 [AUTH] Starting OAuth flow (Garmin)');

    try {
      final result = await initiateOAuthConnection(userId: userId);
      final authorizationUrl = result['authorization_url']!;
      final state = result['state']!;

      logWarning(
        '🌐 [AUTH] Obtained Garmin URL, attempting to launch browser...',
      );
      logWarning('  URL: $authorizationUrl');
      logWarning(
        '  State: ${state.substring(0, state.length > 30 ? 30 : state.length)}...',
      );

      final launched = await launchUrl(
        Uri.parse(authorizationUrl),
        mode: LaunchMode.externalApplication,
      );

      logWarning('📱 [AUTH] Browser launch result: $launched');

      if (!launched) {
        logError(
          '❌ [AUTH] Cannot open browser',
          Exception('Browser launch failed'),
          StackTrace.current,
        );
        throw Exception('Cannot open browser');
      }

      logWarning(
        '✅ [AUTH] OAuth flow started successfully, state: ${state.substring(0, 30)}...',
      );
      return result;
    } catch (e, stackTrace) {
      logError('❌ [AUTH] Error in startOAuthFlow: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Handle return URL deep link after Managed OAuth v2.
  /// Supports ?status=success&user_id=xxx or ?success=true&user_id=xxx.
  Future<String?> handleDeepLinkCallback(Uri uri) async {
    logWarning('🔄 [AUTH] Handling deep link callback (Garmin)');
    logWarning('  URI: $uri');

    final status = uri.queryParameters['status'];
    final success = uri.queryParameters['success'];
    final userID = uri.queryParameters['user_id'];
    final error = uri.queryParameters['error'];

    final isSuccess = status == 'success' || success == 'true';

    logWarning(
      '🔍 [AUTH] Callback parameters: status=$status success=$success userID=$userID error=$error',
    );

    if (isSuccess && userID != null && userID.isNotEmpty) {
      logWarning('✅ [AUTH] Connection successful, saving userId: $userID');
      await saveUserId(userID);
      logWarning('💾 [AUTH] userId saved successfully');

      // Validate data freshness after connection
      try {
        logDebug(
          '🔍 [AUTH] Validating data freshness after Garmin connection...',
        );
        final testData = await _fetchData(
          'dailies',
          userID,
          DateTime.now().subtract(const Duration(days: 7)),
          DateTime.now(),
        );
        _validateDataFreshness(testData, 'Garmin connection');
        logDebug('✅ [AUTH] Garmin connection validated: Data is fresh');
      } catch (e, stackTrace) {
        logWarning('⚠️ [AUTH] Garmin connection data validation failed: $e');
        logError('⚠️ [AUTH] Validation error details', e, stackTrace);
        // Don't fail connection if validation fails, just log warning
      }

      logWarning(
        '✅ [AUTH] handleDeepLinkCallback completed successfully, userId: $userID',
      );
      return userID;
    } else if (status == 'error' || error != null) {
      // Connection failed
      final errorMessage = error ?? 'Unknown error';
      logError(
        '❌ [AUTH] OAuth callback failed: $errorMessage',
        Exception(errorMessage),
        StackTrace.current,
      );
      throw Exception('OAuth callback failed: $errorMessage');
    }

    logWarning('⚠️ [AUTH] Callback missing status/userID or error');
    return null;
  }

  /// Convenience method for connection success
  Future<void> onConnectionSuccess(String userID) async {
    await saveUserId(userID);
  }

  /// Convenience method for connection error (matches documentation - async)
  Future<void> onConnectionError(String error) async {
    throw Exception('Garmin connection error: $error');
  }

  /// Connect: initiates Managed OAuth v2, returns auth URL (opens browser).
  /// [userId] optional. After login, wear service redirects to return URL; app calls [markConnected(userId)] or [handleDeepLinkCallback(uri)].
  Future<String> connect([dynamic context, String? userId]) async {
    logWarning('🔌 [AUTH] connect() called (Garmin)');
    try {
      final result = await startOAuthFlow(userId: userId);
      final state = result['state'] ?? '';
      logWarning(
        '✅ [AUTH] connect() completed, state: ${state.substring(0, state.length > 30 ? 30 : state.length)}...',
      );
      // Return the state - the actual user_id will come from deep link callback
      return state;
    } catch (e, stackTrace) {
      logError('❌ [AUTH] Error in connect(): $e', e, stackTrace);
      rethrow;
    }
  }

  /// Ensure subscription is active before making data requests
  /// This is required by the backend to process historical data requests
  ///
  /// Note: SSE connections can close normally (network issues, server restarts, etc.)
  /// Fetch Garmin data - generic method for all summary types
  Future<Map<String, dynamic>> _fetchData(
    String summaryType,
    String userId,
    DateTime? start,
    DateTime? end,
  ) async {

    logWarning('📊 [DATA] Fetching Garmin $summaryType data');
    logWarning('  userId: $userId');
    logWarning('  start: $start');
    logWarning('  end: $end');

    final params = <String, String>{
      'app_id': appId,
      if (projectId != null && projectId!.isNotEmpty) 'project_id': projectId!,
      if (start != null) 'start': start.toUtc().toIso8601String(),
      if (end != null) 'end': end.toUtc().toIso8601String(),
    };

    final uri = Uri.parse(
      '$_apiBase/garmin/data/$userId/$summaryType',
    ).replace(queryParameters: params);

    // Always print URI for debugging (even if debug logs are disabled)
    debugPrint('📡 [Garmin] Request URI: $uri');
    logWarning('📡 [DATA] Request URI: $uri');
    try {
      final res = await http.get(uri, headers: _authHeaders());
      logWarning('📥 [DATA] Response status: ${res.statusCode}');
      if (res.statusCode == 200) {
        final bodyPreview = res.body.length > 500
            ? '${res.body.substring(0, 500)}...'
            : res.body;
        logWarning('📥 [DATA] Response body preview: $bodyPreview');
      } else {
        logWarning('📥 [DATA] Response body: ${res.body}');
      }

      if (res.statusCode != 200) {
        logError(
          '❌ [DATA] Failed to fetch Garmin $summaryType',
          Exception('Status ${res.statusCode}'),
          StackTrace.current,
        );

        // Provide helpful error message for 404
        String errorMessage =
            'Failed to fetch Garmin $summaryType (${res.statusCode}): ${res.body}';
        if (res.statusCode == 404) {
          errorMessage +=
              '\n\n💡 Tip: Garmin data may need to be synced first. '
              'Try requesting a backfill for $summaryType before fetching data.';
        }

        throw Exception(errorMessage);
      }

      final data = jsonDecode(res.body);

      // Validate data freshness
      _validateDataFreshness(data, 'Garmin $summaryType fetch');

      logWarning('✅ [DATA] Successfully fetched Garmin $summaryType data');
      return data;
    } catch (e, stackTrace) {
      logError(
        '❌ [DATA] Error fetching Garmin $summaryType: $e',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Extract latest timestamp from API response
  /// Handles various response formats: array, object with data array, or single object
  DateTime? _extractLatestTimestamp(Map<String, dynamic> response) {
    try {
      // Check if response has a 'data' array
      if (response.containsKey('data') && response['data'] is List) {
        final dataList = response['data'] as List;
        if (dataList.isEmpty) return null;

        DateTime? latest;
        for (final item in dataList) {
          if (item is Map<String, dynamic>) {
            final timestamp = _extractTimestampFromItem(item);
            if (timestamp != null &&
                (latest == null || timestamp.isAfter(latest))) {
              latest = timestamp;
            }
          }
        }
        return latest;
      }

      // Check if response is directly an array (wrapped in a map somehow)
      // Or check for common timestamp fields
      if (response.containsKey('timestamp')) {
        return _parseTimestamp(response['timestamp']);
      }

      // Check for common array fields
      for (final key in ['records', 'items', 'results', 'summaries']) {
        if (response.containsKey(key) && response[key] is List) {
          final list = response[key] as List;
          if (list.isNotEmpty && list.first is Map<String, dynamic>) {
            return _extractTimestampFromItem(
              list.first as Map<String, dynamic>,
            );
          }
        }
      }

      // If response itself might be an array (shouldn't happen but handle it)
      // This case is unlikely but we'll return null if we can't find timestamp
      return null;
    } catch (e) {
      logWarning('Error extracting timestamp from Garmin response: $e');
      return null;
    }
  }

  /// Extract timestamp from a single item (object)
  DateTime? _extractTimestampFromItem(Map<String, dynamic> item) {
    // Try common timestamp field names for Garmin
    final timestampFields = [
      'timestamp',
      'created_at',
      'start_time',
      'end_time',
      'date',
      'calendarDate',
      'startTimeInSeconds',
      'endTimeInSeconds',
    ];
    for (final field in timestampFields) {
      if (item.containsKey(field)) {
        return _parseTimestamp(item[field]);
      }
    }
    return null;
  }

  /// Parse timestamp from various formats
  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    if (value is int) {
      // Unix timestamp (seconds or milliseconds)
      if (value > 1000000000000) {
        // Milliseconds
        return DateTime.fromMillisecondsSinceEpoch(value);
      } else {
        // Seconds
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
    }
    return null;
  }

  /// Convert Garmin API response to list of WearMetrics
  /// Extracts bio signals (HR, HRV, steps, calories, etc.) from API response
  List<WearMetrics> _convertToWearMetricsList(
    dynamic response,
    String source,
    String userId,
  ) {
    final List<WearMetrics> metricsList = [];

    try {
      // Handle if response is already a List
      if (response is List) {
        for (final item in response) {
          if (item is Map<String, dynamic>) {
            final metric = _convertSingleItemToWearMetrics(
              item,
              source,
              userId,
            );
            if (metric != null) {
              metricsList.add(metric);
            }
          }
        }
        return metricsList;
      }

      // Handle if response is a Map
      if (response is! Map<String, dynamic>) {
        return metricsList;
      }

      // Extract data array from response
      List<dynamic>? dataList;
      if (response.containsKey('data') && response['data'] is List) {
        dataList = response['data'] as List;
      } else if (response.containsKey('records') &&
          response['records'] is List) {
        dataList = response['records'] as List;
      } else if (response.containsKey('summaries') &&
          response['summaries'] is List) {
        dataList = response['summaries'] as List;
      } else if (response.containsKey('items') && response['items'] is List) {
        dataList = response['items'] as List;
      }

      if (dataList == null || dataList.isEmpty) {
        // If no array, try to convert single object
        final singleMetric = _convertSingleItemToWearMetrics(
          response,
          source,
          userId,
        );
        if (singleMetric != null) {
          metricsList.add(singleMetric);
        }
        return metricsList;
      }

      // Convert each item in the array
      for (final item in dataList) {
        if (item is Map<String, dynamic>) {
          final metric = _convertSingleItemToWearMetrics(item, source, userId);
          if (metric != null) {
            metricsList.add(metric);
          }
        }
      }
    } catch (e) {
      logWarning('Error converting Garmin response to WearMetrics: $e');
    }

    return metricsList;
  }

  /// Convert a single Garmin API item to WearMetrics
  WearMetrics? _convertSingleItemToWearMetrics(
    Map<String, dynamic> item,
    String source,
    String userId,
  ) {
    try {
      final metrics = <String, num?>{};
      final meta = <String, Object?>{};

      // Extract timestamp
      DateTime? timestamp = _extractTimestampFromItem(item);
      if (timestamp == null) {
        // Try to use current time if no timestamp found
        timestamp = DateTime.now();
      }

      // Extract bio signals from Garmin API response
      // Garmin dailies typically contain: steps, calories, distance, heartRate, etc.

      // Heart rate
      if (item.containsKey('averageHeartRate')) {
        metrics['hr'] = _toNum(item['averageHeartRate']);
      } else if (item.containsKey('heartRate')) {
        metrics['hr'] = _toNum(item['heartRate']);
      } else if (item.containsKey('hr')) {
        metrics['hr'] = _toNum(item['hr']);
      } else if (item.containsKey('restingHeartRate')) {
        metrics['hr'] = _toNum(item['restingHeartRate']);
      }

      // HRV
      if (item.containsKey('hrv')) {
        final hrv = _toNum(item['hrv']);
        metrics['hrv_rmssd'] = hrv;
        metrics['hrv_sdnn'] = hrv;
      } else if (item.containsKey('hrvRmssd')) {
        metrics['hrv_rmssd'] = _toNum(item['hrvRmssd']);
      } else if (item.containsKey('hrvSdnn')) {
        metrics['hrv_sdnn'] = _toNum(item['hrvSdnn']);
      } else if (item.containsKey('hrv_rmssd')) {
        metrics['hrv_rmssd'] = _toNum(item['hrv_rmssd']);
      } else if (item.containsKey('hrv_sdnn')) {
        metrics['hrv_sdnn'] = _toNum(item['hrv_sdnn']);
      }

      // Steps
      if (item.containsKey('steps')) {
        metrics['steps'] = _toNum(item['steps']);
      } else if (item.containsKey('stepCount')) {
        metrics['steps'] = _toNum(item['stepCount']);
      } else if (item.containsKey('totalSteps')) {
        metrics['steps'] = _toNum(item['totalSteps']);
      }

      // Calories
      if (item.containsKey('calories')) {
        metrics['calories'] = _toNum(item['calories']);
      } else if (item.containsKey('activeKilocalories')) {
        metrics['calories'] = _toNum(item['activeKilocalories']);
      } else if (item.containsKey('totalKilocalories')) {
        metrics['calories'] = _toNum(item['totalKilocalories']);
      }

      // Distance (Garmin typically returns in meters, convert to km)
      if (item.containsKey('distanceInMeters')) {
        final meters = _toNum(item['distanceInMeters']);
        if (meters != null) {
          metrics['distance'] = meters / 1000.0;
        }
      } else if (item.containsKey('distance')) {
        // Check if already in km or meters
        final distance = _toNum(item['distance']);
        if (distance != null) {
          // Assume meters if value is large (>1000), otherwise assume km
          metrics['distance'] = distance > 1000 ? distance / 1000.0 : distance;
        }
      }

      // Stress (from stress level or body battery)
      if (item.containsKey('stressLevel')) {
        metrics['stress'] = _toNum(item['stressLevel']);
      } else if (item.containsKey('stress')) {
        metrics['stress'] = _toNum(item['stress']);
      } else if (item.containsKey('bodyBattery')) {
        // Use body battery as inverse stress (lower battery = higher stress)
        final battery = _toNum(item['bodyBattery']);
        if (battery != null) {
          metrics['stress'] = 100 - battery;
        }
      }

      // Store original Garmin data in meta for reference
      meta['garmin_data'] = item;
      meta['synced'] = true;
      meta['source_type'] = 'garmin_cloud';

      // Store additional Garmin-specific metrics in meta
      if (item.containsKey('bodyBattery')) {
        meta['body_battery'] = item['bodyBattery'];
      }
      if (item.containsKey('vo2Max')) {
        meta['vo2_max'] = item['vo2Max'];
      }
      if (item.containsKey('fitnessAge')) {
        meta['fitness_age'] = item['fitnessAge'];
      }

      return WearMetrics(
        timestamp: timestamp,
        deviceId: 'garmin_$userId',
        source: source,
        metrics: metrics,
        meta: meta,
      );
    } catch (e) {
      logWarning('Error converting Garmin item to WearMetrics: $e');
      return null;
    }
  }

  /// Helper to safely convert dynamic value to num
  num? _toNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is String) {
      return num.tryParse(value);
    }
    return null;
  }

  /// Validate data freshness (within 24 hours)
  void _validateDataFreshness(Map<String, dynamic> response, String context) {
    final latestTimestamp = _extractLatestTimestamp(response);

    if (latestTimestamp == null) {
      logWarning('⚠️ $context: Could not extract timestamp from response');
      return; // Don't fail if we can't extract timestamp
    }

    final dataAge = DateTime.now().difference(latestTimestamp);
    const maxStaleAge = Duration(hours: 24);

    // Handle timezone differences
    final isFutureData = dataAge.isNegative;
    final absoluteAge = isFutureData ? -dataAge : dataAge;

    if (absoluteAge > maxStaleAge) {
      final errorMessage =
          'Garmin data is stale (${absoluteAge.inHours} hours old). '
          'Please check if your wearable device is connected to get latest data.';
      logWarning('❌ $context: $errorMessage');
      throw Exception(errorMessage);
    }

    if (isFutureData) {
      logWarning(
        '⏰ $context: Data timestamp is ${absoluteAge.inHours} hours in the future (likely timezone difference) - treating as valid',
      );
    } else {
      logWarning(
        '✅ $context: Data is fresh (${absoluteAge.inHours} hours old)',
      );
    }
  }

  // ========== Data Fetching Methods (12 Summary Types) ==========

  /// Fetch daily summaries (steps, calories, heart rate, stress, body battery)
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchDailies({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData('dailies', effectiveUserId, start, end);
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch 15-minute granular activity periods
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchEpochs({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData('epochs', effectiveUserId, start, end);
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch sleep data (duration, levels, scores)
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchSleeps({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData('sleeps', effectiveUserId, start, end);
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch raw Garmin data for Flux processing
  /// Combines dailies and sleeps data into the format expected by Flux
  /// userId is optional, uses stored userId if not provided
  Future<Map<String, dynamic>> fetchRawDataForFlux({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }

    // Fetch dailies and sleeps data
    final dailies = await _fetchData('dailies', effectiveUserId, start, end);
    final sleeps = await _fetchData('sleeps', effectiveUserId, start, end);

    // Extract arrays from responses
    // _fetchData always returns Map<String, dynamic> from jsonDecode
    List<dynamic> dailiesArray = [];
    if (dailies.containsKey('data') && dailies['data'] is List) {
      dailiesArray = dailies['data'] as List;
    } else if (dailies.containsKey('records') && dailies['records'] is List) {
      dailiesArray = dailies['records'] as List;
    } else if (dailies.containsKey('items') && dailies['items'] is List) {
      dailiesArray = dailies['items'] as List;
    } else if (dailies.containsKey('dailies') && dailies['dailies'] is List) {
      dailiesArray = dailies['dailies'] as List;
    }

    List<dynamic> sleepsArray = [];
    if (sleeps.containsKey('data') && sleeps['data'] is List) {
      sleepsArray = sleeps['data'] as List;
    } else if (sleeps.containsKey('records') && sleeps['records'] is List) {
      sleepsArray = sleeps['records'] as List;
    } else if (sleeps.containsKey('items') && sleeps['items'] is List) {
      sleepsArray = sleeps['items'] as List;
    } else if (sleeps.containsKey('sleep') && sleeps['sleep'] is List) {
      sleepsArray = sleeps['sleep'] as List;
    } else if (sleeps.containsKey('sleeps') && sleeps['sleeps'] is List) {
      sleepsArray = sleeps['sleeps'] as List;
    }

    // Return in the format Flux expects: { "dailies": [...], "sleep": [...] }
    return {'dailies': dailiesArray, 'sleep': sleepsArray};
  }

  /// Fetch detailed stress values and body battery events
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchStressDetails({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData(
      'stressDetails',
      effectiveUserId,
      start,
      end,
    );
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch heart rate variability metrics
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchHRV({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData('hrv', effectiveUserId, start, end);
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch user metrics (VO2 Max, Fitness Age)
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchUserMetrics({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData(
      'userMetrics',
      effectiveUserId,
      start,
      end,
    );
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch body composition (weight, BMI, body fat, etc.)
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchBodyComps({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData('bodyComps', effectiveUserId, start, end);
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch pulse oximetry data
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchPulseOx({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData('pulseox', effectiveUserId, start, end);
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch respiration rate data
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchRespiration({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData(
      'respiration',
      effectiveUserId,
      start,
      end,
    );
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch health snapshot data
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchHealthSnapshot({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData(
      'healthSnapshot',
      effectiveUserId,
      start,
      end,
    );
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch blood pressure measurements
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchBloodPressures({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData(
      'bloodPressures',
      effectiveUserId,
      start,
      end,
    );
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  /// Fetch skin temperature data
  /// userId is optional, uses stored userId if not provided
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchSkinTemp({
    String? userId,
    DateTime? start,
    DateTime? end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetchData('skinTemp', effectiveUserId, start, end);
    return _convertToWearMetricsList(response, 'garmin', effectiveUserId);
  }

  // ========== Additional Garmin Methods ==========

  /// Get Garmin User ID (Garmin's API User ID)
  Future<String> getGarminUserId(String userId) async {
    final uri = Uri.parse(
      '$_apiBase/garmin/data/$userId/user_id',
    ).replace(queryParameters: {'app_id': appId});

    final res = await http.get(uri, headers: _authHeaders());
    if (res.statusCode != 200) {
      throw Exception('Failed to get Garmin User ID: ${res.body}');
    }

    final json = jsonDecode(res.body);
    return json['user_id'] as String;
  }

  /// Get Garmin user permissions
  Future<List<String>> getUserPermissions(String userId) async {
    final uri = Uri.parse(
      '$_apiBase/garmin/data/$userId/user_permissions',
    ).replace(queryParameters: {'app_id': appId});

    final res = await http.get(uri, headers: _authHeaders());
    if (res.statusCode != 200) {
      throw Exception('Failed to get user permissions: ${res.body}');
    }

    final json = jsonDecode(res.body);
    return List<String>.from(json);
  }

  /// Request historical Garmin data (max 90 days per request)
  /// Data is delivered asynchronously via webhooks
  ///
  /// [userId] - User ID (optional, uses stored userId if not provided)
  /// [summaryType] - One of: dailies, epochs, sleeps, stressDetails, hrv,
  ///   userMetrics, bodyComps, pulseox, respiration, healthSnapshot,
  ///   bloodPressures, skinTemp
  /// [start] - Start time (RFC3339 format)
  /// [end] - End time (RFC3339 format, max 90 days range)
  ///
  /// Returns a map with status, message, user_id, summary_type, start, and end
  Future<Map<String, dynamic>> requestBackfill({
    String? userId,
    required String summaryType,
    required DateTime start,
    required DateTime end,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }

    final uri = Uri.parse(
      '$_apiBase/garmin/backfill/$effectiveUserId/$summaryType',
    );

    // Use actual DateTime values without normalization to avoid duplicate detection
    // Each request will have unique timestamps based on when it was made
    final requestBody = {
      'app_id': appId,
      'start_time': start.toUtc().toIso8601String(),
      'end_time': end.toUtc().toIso8601String(),
    };

    logWarning('📡 [BACKFILL] Request URI: $uri');
    logWarning('📡 [BACKFILL] Request body: ${jsonEncode(requestBody)}');

    final res = await http.post(
      uri,
      headers: _authHeaders(),
      body: jsonEncode(requestBody),
    );

    logWarning('📥 [BACKFILL] Response status: ${res.statusCode}');
    logWarning('📥 [BACKFILL] Response body: ${res.body}');

    if (res.statusCode != 202) {
      final errorBody = res.body;
      String errorMessage = 'Failed to request backfill: $errorBody';

      // Provide helpful guidance for common errors
      if (res.statusCode == 400) {
        if (errorBody.contains('connection not found') ||
            errorBody.contains('failed to get tokens')) {
          errorMessage =
              'Backfill request failed: Connection tokens not yet available.\n\n'
              '💡 This usually means:\n'
              '  1. OAuth connection was just completed - tokens may still be syncing on the backend\n'
              '  2. Try waiting a few seconds and retry the backfill request\n'
              '  3. Or disconnect and reconnect Garmin to refresh tokens\n\n'
              'Error details: $errorBody';
          logWarning(
            '⚠️ [BACKFILL] Connection tokens not available - this is a backend timing issue',
          );
        } else if (errorBody.contains('timestamp must be positive')) {
          errorMessage =
              'Backfill request failed: Invalid timestamp format.\n\n'
              '💡 Ensure start and end are in RFC3339 format (e.g., "2025-01-20T18:30:00.000Z")\n\n'
              'Error details: $errorBody';
        } else if (errorBody.contains('date range') ||
            errorBody.contains('90 days')) {
          errorMessage =
              'Backfill request failed: Date range exceeds limit.\n\n'
              '💡 Maximum date range is 90 days. Please select a smaller range.\n\n'
              'Error details: $errorBody';
        }
      } else if (res.statusCode == 404) {
        errorMessage =
            'Backfill request failed: Endpoint not found.\n\n'
            '💡 Check that the summaryType is valid and the user is connected.\n\n'
            'Error details: $errorBody';
      }

      throw Exception(errorMessage);
    }

    return jsonDecode(res.body);
  }

  /// Disconnect Garmin integration (x-app-id and x-api-key sent).
  Future<void> disconnect(String userId) async {
    final uri = Uri.parse(
      '$_apiBase/garmin/oauth/disconnect',
    ).replace(queryParameters: {'user_id': userId, 'app_id': appId});

    final res = await http.delete(uri, headers: _authHeaders());
    if (res.statusCode != 200) {
      throw Exception('Failed to disconnect: ${res.body}');
    }

    // Clear local storage
    await clearUserId();
  }

}
