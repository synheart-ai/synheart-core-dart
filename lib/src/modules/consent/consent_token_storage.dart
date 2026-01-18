import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/logger.dart';
import 'consent_token.dart';
import 'consent_profile.dart';

/// Secure storage for consent tokens and profiles
class ConsentTokenStorage {
  static const _tokenKey = 'synheart_consent_token';
  static const _profilesCacheKey = 'synheart_consent_profiles_cache';
  static const _profilesCacheTimestampKey = 'synheart_consent_profiles_cache_ts';
  static const _profilesCacheTTL = Duration(hours: 24);

  final FlutterSecureStorage _storage;

  ConsentTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Save consent token
  Future<void> saveToken(ConsentToken token) async {
    try {
      final json = jsonEncode(token.toJson());
      await _storage.write(key: _tokenKey, value: json);
    } catch (e) {
      SynheartLogger.log(
        '[ConsentTokenStorage] Error saving token: $e',
        error: e,
      );
      rethrow;
    }
  }

  /// Load consent token
  Future<ConsentToken?> loadToken() async {
    try {
      final jsonString = await _storage.read(key: _tokenKey);
      if (jsonString == null) {
        return null;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return ConsentToken.fromStoredJson(json);
    } catch (e) {
      SynheartLogger.log(
        '[ConsentTokenStorage] Error loading token: $e',
        error: e,
      );
      return null;
    }
  }

  /// Delete consent token
  Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (e) {
      SynheartLogger.log(
        '[ConsentTokenStorage] Error deleting token: $e',
        error: e,
      );
    }
  }

  /// Check if token exists
  Future<bool> hasToken() async {
    final token = await loadToken();
    return token != null && token.isValid;
  }

  /// Cache consent profiles
  Future<void> cacheProfiles(List<ConsentProfile> profiles) async {
    try {
      final profilesJson = profiles.map((p) => p.toJson()).toList();
      final jsonString = jsonEncode(profilesJson);
      await _storage.write(key: _profilesCacheKey, value: jsonString);
      await _storage.write(
        key: _profilesCacheTimestampKey,
        value: DateTime.now().toIso8601String(),
      );
    } catch (e) {
      SynheartLogger.log(
        '[ConsentTokenStorage] Error caching profiles: $e',
        error: e,
      );
    }
  }

  /// Load cached consent profiles (if not expired)
  Future<List<ConsentProfile>?> loadCachedProfiles() async {
    try {
      final timestampStr = await _storage.read(key: _profilesCacheTimestampKey);
      if (timestampStr == null) {
        return null;
      }

      final timestamp = DateTime.parse(timestampStr);
      final age = DateTime.now().difference(timestamp);
      if (age > _profilesCacheTTL) {
        // Cache expired
        await clearProfilesCache();
        return null;
      }

      final profilesJsonString = await _storage.read(key: _profilesCacheKey);
      if (profilesJsonString == null) {
        return null;
      }

      final profilesJson = jsonDecode(profilesJsonString) as List<dynamic>;
      return profilesJson
          .map((p) => ConsentProfile.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      SynheartLogger.log(
        '[ConsentTokenStorage] Error loading cached profiles: $e',
        error: e,
      );
      return null;
    }
  }

  /// Clear profiles cache
  Future<void> clearProfilesCache() async {
    try {
      await _storage.delete(key: _profilesCacheKey);
      await _storage.delete(key: _profilesCacheTimestampKey);
    } catch (e) {
      SynheartLogger.log(
        '[ConsentTokenStorage] Error clearing profiles cache: $e',
        error: e,
      );
    }
  }

  /// Clear all consent data
  Future<void> clearAll() async {
    await deleteToken();
    await clearProfilesCache();
  }
}

