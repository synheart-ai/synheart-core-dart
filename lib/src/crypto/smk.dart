import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage Master Key — 32-byte symmetric key for local encryption-at-rest.
///
/// Generated once per installation and persisted in platform secure storage
/// (iOS Keychain / Android Keystore). Never leaves the device.
///
/// See RFC-CORE-0004 Section 9.1.
class SMK {
  static const String _storageKey = 'synheart.smk';
  static const int _keyLengthBytes = 32;

  final Uint8List bytes;

  SMK._(this.bytes) {
    if (bytes.length != _keyLengthBytes) {
      throw ArgumentError('SMK must be $_keyLengthBytes bytes');
    }
  }

  /// Load an existing SMK from secure storage or generate a new one.
  static Future<SMK> loadOrCreate({
    FlutterSecureStorage? storage,
    String? keySuffix,
  }) async {
    final store = storage ?? const FlutterSecureStorage();
    final key = keySuffix != null ? '$_storageKey.$keySuffix' : _storageKey;

    final existing = await store.read(key: key);
    if (existing != null) {
      final bytes = _hexDecode(existing);
      return SMK._(bytes);
    }

    final smk = generate();
    await store.write(key: key, value: _hexEncode(smk.bytes));
    return smk;
  }

  /// Generate a fresh 32-byte SMK using a secure random source.
  static SMK generate() {
    final rng = Random.secure();
    final bytes = Uint8List(_keyLengthBytes);
    for (var i = 0; i < _keyLengthBytes; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return SMK._(bytes);
  }

  /// Construct from raw bytes (e.g. for testing).
  factory SMK.fromBytes(Uint8List bytes) => SMK._(Uint8List.fromList(bytes));

  /// Delete the SMK from secure storage (irreversible — all encrypted data
  /// becomes unrecoverable).
  static Future<void> delete({
    FlutterSecureStorage? storage,
    String? keySuffix,
  }) async {
    final store = storage ?? const FlutterSecureStorage();
    final key = keySuffix != null ? '$_storageKey.$keySuffix' : _storageKey;
    await store.delete(key: key);
  }

  static String _hexEncode(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexDecode(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
