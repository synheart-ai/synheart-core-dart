import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for auth credentials (RFC-CORE-0008 §1.5).
///
/// Uses flutter_secure_storage which maps to:
/// - iOS: Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
/// - Android: EncryptedSharedPreferences (AndroidKeyStore-backed)
///
/// NOTE: Refresh tokens are NOT stored here — the SDK flow uses
/// re-attestation via synheart-auth, not refresh tokens.
class TokenStorage {
  static const String _keySubjectId = 'synheart.auth.subject_id';
  static const String _keySessionSecret = 'synheart.auth.session_secret';
  static const String _keyConsentProfileId = 'synheart.auth.consent_profile_id';

  final FlutterSecureStorage _storage;

  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveSubjectId(String id) =>
      _storage.write(key: _keySubjectId, value: id);

  Future<String?> loadSubjectId() =>
      _storage.read(key: _keySubjectId);

  Future<void> saveSessionSecret(String secret) =>
      _storage.write(key: _keySessionSecret, value: secret);

  Future<String?> loadSessionSecret() =>
      _storage.read(key: _keySessionSecret);

  Future<void> saveConsentProfileId(String profileId) =>
      _storage.write(key: _keyConsentProfileId, value: profileId);

  Future<String?> loadConsentProfileId() =>
      _storage.read(key: _keyConsentProfileId);

  /// Clear auth state. Preserves sessionSecret for URK continuity.
  Future<void> clearAll() async {
    await _storage.delete(key: _keySubjectId);
    await _storage.delete(key: _keyConsentProfileId);
    // sessionSecret is intentionally preserved — it's used for URK
    // derivation and must survive across auth cycles to avoid
    // re-encrypting stored artifacts.
  }

  /// Full wipe including session secret (for wipeLocalData).
  Future<void> clearEverything() async {
    await _storage.delete(key: _keySubjectId);
    await _storage.delete(key: _keySessionSecret);
    await _storage.delete(key: _keyConsentProfileId);
  }
}
