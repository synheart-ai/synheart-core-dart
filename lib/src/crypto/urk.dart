import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// User Root Key management for E2EE sync (RFC-CORE-0005 §3).
///
/// URK is a 32-byte key used to derive per-artifact encryption keys for sync.
/// It is wrapped locally using a KEK stored in platform secure storage.
class URK {
  static const String _storageKeyWrapped = 'synheart.urk.wrapped';
  static const String _storageKeyKek = 'synheart.urk.kek';
  static const int _keyLengthBytes = 32;
  static const String _bundleKdfInfo = 'synheart-urk-bundle:v1';
  static const String _syncKdfInfo = 'synheart-sync:v1';

  final Uint8List bytes;

  URK._(this.bytes) {
    if (bytes.length != _keyLengthBytes) {
      throw ArgumentError('URK must be $_keyLengthBytes bytes');
    }
  }

  /// Generate a fresh 32-byte URK.
  static URK generate() {
    final rng = Random.secure();
    final bytes = Uint8List(_keyLengthBytes);
    for (var i = 0; i < _keyLengthBytes; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return URK._(bytes);
  }

  /// Construct from raw bytes.
  factory URK.fromBytes(Uint8List bytes) => URK._(Uint8List.fromList(bytes));

  /// Derive a Bundle Encryption Key from the auth session secret.
  static Future<Uint8List> deriveBEK({
    required String sessionSecret,
    required String subjectId,
  }) async {
    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: _keyLengthBytes);
    final inputKey = SecretKey(utf8.encode(sessionSecret));
    final derived = await hkdf.deriveKey(
      secretKey: inputKey,
      nonce: utf8.encode(subjectId),
      info: utf8.encode(_bundleKdfInfo),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  /// Derive a per-artifact encryption key for sync.
  static Future<Uint8List> deriveArtifactKey({
    required Uint8List urk,
    required String artifactId,
  }) async {
    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: _keyLengthBytes);
    final inputKey = SecretKey(urk);
    final derived = await hkdf.deriveKey(
      secretKey: inputKey,
      nonce: utf8.encode(artifactId),
      info: utf8.encode(_syncKdfInfo),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  /// Encrypt URK for cloud storage as a bundle.
  static Future<Map<String, String>> encryptBundle({
    required Uint8List urk,
    required String sessionSecret,
    required String subjectId,
  }) async {
    final bek = await deriveBEK(sessionSecret: sessionSecret, subjectId: subjectId);
    final cipher = Xchacha20.poly1305Aead();
    final key = SecretKey(bek);
    final box = await cipher.encrypt(urk, secretKey: key);

    return {
      'urk_bundle_version': '1',
      'ciphertext_b64': base64Encode(Uint8List.fromList(box.cipherText + box.mac.bytes)),
      'nonce_b64': base64Encode(Uint8List.fromList(box.nonce)),
      'kdf_info': _bundleKdfInfo,
    };
  }

  /// Decrypt a URK bundle downloaded from the server.
  static Future<URK> decryptBundle({
    required Map<String, dynamic> bundle,
    required String sessionSecret,
    required String subjectId,
  }) async {
    final bek = await deriveBEK(sessionSecret: sessionSecret, subjectId: subjectId);
    final cipher = Xchacha20.poly1305Aead();
    final key = SecretKey(bek);

    final ctAndMac = base64Decode(bundle['ciphertext_b64'] as String);
    final nonce = base64Decode(bundle['nonce_b64'] as String);

    const macLen = 16;
    final ct = ctAndMac.sublist(0, ctAndMac.length - macLen);
    final mac = ctAndMac.sublist(ctAndMac.length - macLen);

    final box = SecretBox(ct, nonce: nonce, mac: Mac(mac));
    final plaintext = await cipher.decrypt(box, secretKey: key);

    return URK._(Uint8List.fromList(plaintext));
  }

  /// Wrap and store URK locally using a KEK.
  Future<void> wrapAndStore({FlutterSecureStorage? storage}) async {
    final store = storage ?? const FlutterSecureStorage();

    // Get or create KEK
    var kekHex = await store.read(key: _storageKeyKek);
    Uint8List kek;
    if (kekHex != null) {
      kek = _hexDecode(kekHex);
    } else {
      kek = Uint8List(_keyLengthBytes);
      final rng = Random.secure();
      for (var i = 0; i < _keyLengthBytes; i++) {
        kek[i] = rng.nextInt(256);
      }
      await store.write(key: _storageKeyKek, value: _hexEncode(kek));
    }

    // Encrypt URK with KEK
    final cipher = Xchacha20.poly1305Aead();
    final key = SecretKey(kek);
    final box = await cipher.encrypt(bytes, secretKey: key);

    // Pack: nonce || ct || mac
    final packed = Uint8List.fromList(box.nonce + box.cipherText + box.mac.bytes);
    await store.write(key: _storageKeyWrapped, value: _hexEncode(packed));
  }

  /// Unwrap URK from local storage.
  static Future<URK?> unwrap({FlutterSecureStorage? storage}) async {
    final store = storage ?? const FlutterSecureStorage();
    final wrappedHex = await store.read(key: _storageKeyWrapped);
    final kekHex = await store.read(key: _storageKeyKek);
    if (wrappedHex == null || kekHex == null) return null;

    final wrapped = _hexDecode(wrappedHex);
    final kek = _hexDecode(kekHex);

    const nonceLen = 24;
    const macLen = 16;
    final nonce = wrapped.sublist(0, nonceLen);
    final ct = wrapped.sublist(nonceLen, wrapped.length - macLen);
    final mac = wrapped.sublist(wrapped.length - macLen);

    final cipher = Xchacha20.poly1305Aead();
    final key = SecretKey(kek);
    final box = SecretBox(ct, nonce: nonce, mac: Mac(mac));
    final plaintext = await cipher.decrypt(box, secretKey: key);

    return URK._(Uint8List.fromList(plaintext));
  }

  /// Delete URK and KEK from local storage.
  static Future<void> delete({FlutterSecureStorage? storage}) async {
    final store = storage ?? const FlutterSecureStorage();
    await store.delete(key: _storageKeyWrapped);
    await store.delete(key: _storageKeyKek);
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
