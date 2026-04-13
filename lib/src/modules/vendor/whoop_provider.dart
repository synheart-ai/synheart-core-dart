import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:synheart_wear/synheart_wear.dart' show WearMetrics, logDebug, logWarning, logError;

/// Provider for Whoop cloud API integration
///
/// Handles OAuth 2.0 authentication and data fetching from Whoop devices.
/// Supports cycles, recovery, sleep, and workout data retrieval.
class WhoopProvider {
  // Storage keys
  static const String _userIdKey = 'whoop_user_id';
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
  String apiKey; // REQUIRED - sent as x-api-key on every request
  String? projectId; // Optional - for WHOOP data queries
  String? userId;
  final bool _baseUrlExplicitlyProvided;

  /// Base URL for all API requests (auth, data, events).
  String get _apiBase {
    final b = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return b;
  }

  WhoopProvider({
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
    logDebug('🔧 WhoopProvider initialized:');
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
      '✅ WhoopProvider ready - final baseUrl: ${this.baseUrl}, appId: ${this.appId}',
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
  /// Wear service completes token exchange and redirects to platform return URL;
  /// app parses deep link and calls this to mark user connected.
  Future<void> markConnected(String userId) async {
    await saveUserId(userId);
  }

  /// Reload configuration and userId from storage
  Future<void> reloadFromStorage() async {
    await _loadFromStorage();
  }

  /// Managed OAuth v2: POST /auth/connect/whoop with app_id, user_id.
  /// Returns authorization_url and state. Wear service handles callback and
  /// redirects to platform-configured return URL; app calls [markConnected] when it receives success.
  Future<Map<String, String>> initiateOAuthConnection({String? userId}) async {
    final effectiveUserId = userId ?? this.userId;
    logWarning('🔐 [AUTH] Starting initiateOAuthConnection (WHOOP)');
    logDebug('  baseUrl: $baseUrl _apiBase: $_apiBase');
    logDebug('  appId: $appId');
    logDebug('  userId: $effectiveUserId');

    final serviceUrl = Uri.parse('$_apiBase/auth/connect/whoop');

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
          '❌ [AUTH] Failed to initiate WHOOP OAuth connection',
          Exception('Status ${response.statusCode}'),
          StackTrace.current,
        );
        throw Exception(
          'Failed to initiate WHOOP OAuth connection (${response.statusCode}): ${response.body}',
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
        '✅ [AUTH] Successfully obtained WHOOP authorization URL and state',
      );
      return {'authorization_url': authorizationUrl, 'state': state};
    } catch (e, stackTrace) {
      logError('❌ [AUTH] Error in initiateOAuthConnection: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Start OAuth flow: initiate connection, get URL, and launch browser.
  /// [userId] optional; passed to POST /auth/connect/whoop.
  Future<String> startOAuthFlow({String? userId}) async {
    logWarning('🚀 [AUTH] Starting OAuth flow (WHOOP)');

    try {
      final result = await initiateOAuthConnection(userId: userId);
      final authorizationUrl = result['authorization_url']!;
      final state = result['state']!;

      logWarning(
        '🌐 [AUTH] Obtained WHOOP URL, attempting to launch browser...',
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
      return state;
    } catch (e, stackTrace) {
      logError('❌ [AUTH] Error in startOAuthFlow: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Connect: initiates Managed OAuth v2, returns auth URL (and opens browser).
  /// [userId] optional; if provided used in connect request and can be stored after success.
  /// Returns state string. After user completes login, wear service redirects to return URL;
  /// app parses deep link and calls [markConnected(userId)] or [handleDeepLinkCallback(uri)].
  Future<String> connect([dynamic context, String? userId]) async {
    logDebug('🔌 [AUTH] connect() called');
    try {
      final state = await startOAuthFlow(userId: userId);
      logDebug('✅ [AUTH] connect() completed, state: $state');
      return state;
    } catch (e, stackTrace) {
      logError('❌ [AUTH] Error in connect(): $e', e, stackTrace);
      rethrow;
    }
  }

  /// Handle return URL deep link after Managed OAuth v2.
  /// Wear service redirects to platform-configured return URL with success and user_id.
  /// Supports ?status=success&user_id=xxx or ?success=true&user_id=xxx.
  Future<String?> handleDeepLinkCallback(Uri uri) async {
    logWarning('🔄 [AUTH] Handling deep link callback (WHOOP)');
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
          '🔍 [AUTH] Validating data freshness after WHOOP connection...',
        );
        final testData = await _fetch(
          'recovery',
          userID,
          DateTime.now().subtract(const Duration(days: 7)),
          DateTime.now(),
          1, // Just fetch 1 record to check freshness
          null,
        );
        _validateDataFreshness(testData, 'WHOOP connection');
        logDebug('✅ [AUTH] WHOOP connection validated: Data is fresh');
      } catch (e, stackTrace) {
        logWarning('⚠️ [AUTH] WHOOP connection data validation failed: $e');
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

  // 3. Fetch methods – CORRECT PATH + app_id in query
  /// Fetch recovery data (userId is optional, uses stored userId if not provided)
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchRecovery({
    String? userId,
    DateTime? start,
    DateTime? end,
    int limit = 100,
    String? cursor,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetch(
      'recovery',
      effectiveUserId,
      start,
      end,
      limit,
      cursor,
    );
    return _convertToWearMetricsList(response, 'whoop', effectiveUserId);
  }

  /// Fetch sleep data (userId is optional, uses stored userId if not provided)
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchSleep({
    String? userId,
    DateTime? start,
    DateTime? end,
    int limit = 100,
    String? cursor,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetch(
      'sleep',
      effectiveUserId,
      start,
      end,
      limit,
      cursor,
    );
    return _convertToWearMetricsList(response, 'whoop', effectiveUserId);
  }

  /// Fetch workouts data (userId is optional, uses stored userId if not provided)
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchWorkouts({
    String? userId,
    DateTime? start,
    DateTime? end,
    int limit = 100,
    String? cursor,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetch(
      'workouts',
      effectiveUserId,
      start,
      end,
      limit,
      cursor,
    );
    return _convertToWearMetricsList(response, 'whoop', effectiveUserId);
  }

  /// Fetch cycles data (userId is optional, uses stored userId if not provided)
  /// Returns list of WearMetrics in unified format
  Future<List<WearMetrics>> fetchCycles({
    String? userId,
    DateTime? start,
    DateTime? end,
    int limit = 100,
    String? cursor,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }
    final response = await _fetch(
      'cycles',
      effectiveUserId,
      start,
      end,
      limit,
      cursor,
    );
    return _convertToWearMetricsList(response, 'whoop', effectiveUserId);
  }

  /// Fetch raw WHOOP data in Flux-expected format (sleep, recovery, cycle)
  /// Returns a map with 'sleep', 'recovery', and 'cycle' arrays
  Future<Map<String, dynamic>> fetchRawDataForFlux({
    String? userId,
    DateTime? start,
    DateTime? end,
    int limit = 50,
  }) async {
    final effectiveUserId = userId ?? this.userId;
    if (effectiveUserId == null) {
      throw Exception(
        'userId is required. Either provide it or connect first.',
      );
    }

    // Fetch all three data types
    final sleep = await _fetch(
      'sleep',
      effectiveUserId,
      start,
      end,
      limit,
      null,
    );
    final recovery = await _fetch(
      'recovery',
      effectiveUserId,
      start,
      end,
      limit,
      null,
    );
    final cycles = await _fetch(
      'cycles',
      effectiveUserId,
      start,
      end,
      limit,
      null,
    );

    // Extract arrays from responses
    // _fetch always returns Map<String, dynamic> from jsonDecode
    List<dynamic> sleepArray = [];
    if (sleep.containsKey('data') && sleep['data'] is List) {
      sleepArray = sleep['data'] as List;
    } else if (sleep.containsKey('records') && sleep['records'] is List) {
      sleepArray = sleep['records'] as List;
    } else if (sleep.containsKey('items') && sleep['items'] is List) {
      sleepArray = sleep['items'] as List;
    }

    List<dynamic> recoveryArray = [];
    if (recovery.containsKey('data') && recovery['data'] is List) {
      recoveryArray = recovery['data'] as List;
    } else if (recovery.containsKey('records') && recovery['records'] is List) {
      recoveryArray = recovery['records'] as List;
    } else if (recovery.containsKey('items') && recovery['items'] is List) {
      recoveryArray = recovery['items'] as List;
    }

    List<dynamic> cycleArray = [];
    if (cycles.containsKey('data') && cycles['data'] is List) {
      cycleArray = cycles['data'] as List;
    } else if (cycles.containsKey('records') && cycles['records'] is List) {
      cycleArray = cycles['records'] as List;
    } else if (cycles.containsKey('items') && cycles['items'] is List) {
      cycleArray = cycles['items'] as List;
    }

    // Transform data to match Flux expectations:
    // - Remove UUID string 'id' fields (Flux expects Option<i64> but WHOOP returns UUID strings)
    // - Ensure stage_summary has all required fields, especially total_sleep_time_milli
    sleepArray = sleepArray.map((item) {
      if (item is Map<String, dynamic>) {
        final transformed = Map<String, dynamic>.from(item);
        transformed.remove('id'); // Remove UUID string id

        // Fix stage_summary if it exists
        if (transformed.containsKey('score') &&
            transformed['score'] is Map<String, dynamic>) {
          final score = transformed['score'] as Map<String, dynamic>;
          if (score.containsKey('stage_summary') &&
              score['stage_summary'] is Map<String, dynamic>) {
            final stageSummary = score['stage_summary'] as Map<String, dynamic>;

            // Calculate total_sleep_time_milli if missing
            if (!stageSummary.containsKey('total_sleep_time_milli')) {
              int totalSleep = 0;
              if (stageSummary.containsKey('total_light_sleep_time_milli') &&
                  stageSummary['total_light_sleep_time_milli'] is num) {
                totalSleep +=
                    (stageSummary['total_light_sleep_time_milli'] as num)
                        .toInt();
              }
              if (stageSummary.containsKey(
                    'total_slow_wave_sleep_time_milli',
                  ) &&
                  stageSummary['total_slow_wave_sleep_time_milli'] is num) {
                totalSleep +=
                    (stageSummary['total_slow_wave_sleep_time_milli'] as num)
                        .toInt();
              }
              if (stageSummary.containsKey('total_rem_sleep_time_milli') &&
                  stageSummary['total_rem_sleep_time_milli'] is num) {
                totalSleep +=
                    (stageSummary['total_rem_sleep_time_milli'] as num).toInt();
              }

              // If we couldn't calculate it, set to 0 (Flux requires the field to exist)
              stageSummary['total_sleep_time_milli'] = totalSleep;
            }

            // Ensure all required fields exist with defaults if missing
            if (!stageSummary.containsKey('total_in_bed_time_milli')) {
              stageSummary['total_in_bed_time_milli'] = 0;
            }
            if (!stageSummary.containsKey('total_awake_time_milli')) {
              stageSummary['total_awake_time_milli'] = 0;
            }
            if (!stageSummary.containsKey('total_light_sleep_time_milli')) {
              stageSummary['total_light_sleep_time_milli'] = 0;
            }
            if (!stageSummary.containsKey('total_slow_wave_sleep_time_milli')) {
              stageSummary['total_slow_wave_sleep_time_milli'] = 0;
            }
            if (!stageSummary.containsKey('total_rem_sleep_time_milli')) {
              stageSummary['total_rem_sleep_time_milli'] = 0;
            }
            if (!stageSummary.containsKey('disturbance_count')) {
              stageSummary['disturbance_count'] = 0;
            }
          }
        }

        return transformed;
      }
      return item;
    }).toList();

    cycleArray = cycleArray.map((item) {
      if (item is Map<String, dynamic>) {
        final transformed = Map<String, dynamic>.from(item);
        transformed.remove('id'); // Remove UUID string id
        return transformed;
      }
      return item;
    }).toList();

    // Note: cycle_id in recovery might be an integer, so we keep it
    // If it causes issues, we can remove it too

    return {
      'sleep': sleepArray,
      'recovery': recoveryArray,
      'cycle': cycleArray,
    };
  }

  /// GET /whoop/data/{user_id}/{type} with app_id, project_id, start, end, limit, cursor.
  /// x-app-id and x-api-key sent on every request.
  Future<Map<String, dynamic>> _fetch(
    String type,
    String userId,
    DateTime? start,
    DateTime? end,
    int limit,
    String? cursor,
  ) async {
    final params = <String, String>{
      'app_id': appId,
      if (projectId != null && projectId!.isNotEmpty) 'project_id': projectId!,
      if (start != null) 'start': start.toUtc().toIso8601String(),
      if (end != null) 'end': end.toUtc().toIso8601String(),
      'limit': limit.toString(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };

    final uri = Uri.parse(
      '$_apiBase/whoop/data/$userId/$type',
    ).replace(queryParameters: params);
    logDebug('WHOOP data request URI: $uri');
    final res = await http.get(uri, headers: _authHeaders());
    logDebug('WHOOP data response: ${res.body}');
    if (res.statusCode != 200) throw Exception(res.body);
    final data = jsonDecode(res.body);

    // Validate data freshness
    _validateDataFreshness(data, 'WHOOP $type fetch');

    return data;
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
      for (final key in ['records', 'items', 'results']) {
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
      logWarning('Error extracting timestamp from WHOOP response: $e');
      return null;
    }
  }

  /// Extract timestamp from a single item (object)
  DateTime? _extractTimestampFromItem(Map<String, dynamic> item) {
    // Try common timestamp field names
    final timestampFields = [
      'timestamp',
      'created_at',
      'start_time',
      'end_time',
      'date',
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

  /// Convert WHOOP API response to list of WearMetrics
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
      logWarning('Error converting WHOOP response to WearMetrics: $e');
    }

    return metricsList;
  }

  /// Convert a single WHOOP API item to WearMetrics
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

      // Extract bio signals from WHOOP API response
      // WHOOP recovery data typically contains: recovery_score, hr, hrv, etc.
      if (item.containsKey('recovery_score')) {
        meta['recovery_score'] = item['recovery_score'];
      }
      if (item.containsKey('strain_score')) {
        meta['strain_score'] = item['strain_score'];
      }
      if (item.containsKey('sleep_score')) {
        meta['sleep_score'] = item['sleep_score'];
      }

      // Heart rate
      if (item.containsKey('heart_rate')) {
        metrics['hr'] = _toNum(item['heart_rate']);
      } else if (item.containsKey('hr')) {
        metrics['hr'] = _toNum(item['hr']);
      } else if (item.containsKey('heartRate')) {
        metrics['hr'] = _toNum(item['heartRate']);
      }

      // HRV (WHOOP typically provides HRV in recovery data)
      if (item.containsKey('hrv')) {
        final hrv = _toNum(item['hrv']);
        metrics['hrv_rmssd'] = hrv;
        metrics['hrv_sdnn'] =
            hrv; // Use same value for both if only one provided
      } else if (item.containsKey('hrv_rmssd')) {
        metrics['hrv_rmssd'] = _toNum(item['hrv_rmssd']);
      } else if (item.containsKey('hrv_sdnn')) {
        metrics['hrv_sdnn'] = _toNum(item['hrv_sdnn']);
      }

      // Steps (from workout data)
      if (item.containsKey('steps')) {
        metrics['steps'] = _toNum(item['steps']);
      } else if (item.containsKey('step_count')) {
        metrics['steps'] = _toNum(item['step_count']);
      }

      // Calories
      if (item.containsKey('calories')) {
        metrics['calories'] = _toNum(item['calories']);
      } else if (item.containsKey('kilojoule')) {
        // WHOOP sometimes uses kilojoules, convert to kcal (1 kJ = 0.239 kcal)
        final kj = _toNum(item['kilojoule']);
        if (kj != null) {
          metrics['calories'] = kj * 0.239;
        }
      } else if (item.containsKey('calorie')) {
        metrics['calories'] = _toNum(item['calorie']);
      }

      // Distance (from workout data)
      if (item.containsKey('distance')) {
        metrics['distance'] = _toNum(item['distance']);
      } else if (item.containsKey('distance_meter')) {
        // Convert meters to km
        final meters = _toNum(item['distance_meter']);
        if (meters != null) {
          metrics['distance'] = meters / 1000.0;
        }
      }

      // Stress (recovery score can be used as stress indicator)
      if (item.containsKey('recovery_score')) {
        final recovery = _toNum(item['recovery_score']);
        if (recovery != null) {
          // Invert recovery score as stress (lower recovery = higher stress)
          metrics['stress'] = 100 - recovery;
        }
      }

      // Store original WHOOP data in meta for reference
      meta['whoop_data'] = item;
      meta['synced'] = true;
      meta['source_type'] = 'whoop_cloud';

      return WearMetrics(
        timestamp: timestamp,
        deviceId: 'whoop_$userId',
        source: source,
        metrics: metrics,
        meta: meta,
      );
    } catch (e) {
      logWarning('Error converting WHOOP item to WearMetrics: $e');
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
          'WHOOP data is stale (${absoluteAge.inHours} hours old). '
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

  /// Disconnect WHOOP integration (x-app-id and x-api-key sent).
  Future<void> disconnect(String userId) async {
    final uri = Uri.parse(
      '$_apiBase/whoop/oauth/disconnect',
    ).replace(queryParameters: {'user_id': userId, 'app_id': appId});
    final res = await http.delete(uri, headers: _authHeaders());
    if (res.statusCode != 200) throw Exception(res.body);
  }

}
