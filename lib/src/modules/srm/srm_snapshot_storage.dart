import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/logger.dart';
import 'srm_snapshot.dart';

/// Encrypted storage for SRM snapshots using FlutterSecureStorage.
///
/// Mirrors the consent storage pattern — single key, JSON serialization,
/// graceful error handling.
class SRMSnapshotStorage {
  static const _storageKey = 'synheart_srm_snapshot';
  final FlutterSecureStorage _storage;

  SRMSnapshotStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Save SRM snapshot (encrypted)
  Future<void> save(SRMSnapshot snapshot) async {
    final json = snapshot.toJson();
    final jsonString = jsonEncode(json);
    await _storage.write(key: _storageKey, value: jsonString);
  }

  /// Load SRM snapshot from secure storage
  Future<SRMSnapshot?> load() async {
    try {
      final jsonString = await _storage.read(key: _storageKey);
      if (jsonString == null) {
        return null;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return SRMSnapshot.fromJson(json);
    } catch (e) {
      SynheartLogger.log('Error loading SRM snapshot: $e', error: e);
      return null;
    }
  }

  /// Clear SRM snapshot data
  Future<void> clear() async {
    await _storage.delete(key: _storageKey);
  }
}
