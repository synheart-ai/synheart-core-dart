import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure token storage for auth credentials (RFC-CORE-0008 §1.5).
///
/// Uses flutter_secure_storage which maps to:
/// - iOS: Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
/// - Android: EncryptedSharedPreferences (AndroidKeyStore-backed)
class TokenStorage {
  static const String _keyRefreshToken = 'synheart.auth.refresh_token';
  static const String _keySubjectId = 'synheart.auth.subject_id';
  static const String _keySessionSecret = 'synheart.auth.session_secret';

  final FlutterSecureStorage _storage;

  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _keyRefreshToken, value: token);

  Future<String?> loadRefreshToken() =>
      _storage.read(key: _keyRefreshToken);

  Future<void> saveSubjectId(String id) =>
      _storage.write(key: _keySubjectId, value: id);

  Future<String?> loadSubjectId() =>
      _storage.read(key: _keySubjectId);

  Future<void> saveSessionSecret(String secret) =>
      _storage.write(key: _keySessionSecret, value: secret);

  Future<String?> loadSessionSecret() =>
      _storage.read(key: _keySessionSecret);

  Future<void> clearAll() async {
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keySubjectId);
    await _storage.delete(key: _keySessionSecret);
  }
}
