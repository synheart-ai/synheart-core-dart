import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../interfaces/consent_provider.dart';
import '../../core/logger.dart';

/// Encrypted storage for consent snapshots
class ConsentStorage {
  static const _storageKey = 'synheart_consent_snapshot';
  final FlutterSecureStorage _storage;

  ConsentStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Save consent snapshot (encrypted)
  Future<void> save(ConsentSnapshot consent) async {
    final json = consent.toJson();
    final jsonString = jsonEncode(json);
    await _storage.write(key: _storageKey, value: jsonString);
  }

  /// Load consent snapshot from secure storage
  Future<ConsentSnapshot?> load() async {
    try {
      final jsonString = await _storage.read(key: _storageKey);
      if (jsonString == null) {
        return null;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return ConsentSnapshot.fromJson(json);
    } catch (e) {
      // If there's an error reading/parsing, return null
      SynheartLogger.log('Error loading consent: $e', error: e);
      return null;
    }
  }

  /// Clear consent data
  Future<void> clear() async {
    await _storage.delete(key: _storageKey);
  }

  /// Check if consent data exists
  Future<bool> exists() async {
    final value = await _storage.read(key: _storageKey);
    return value != null;
  }
}
