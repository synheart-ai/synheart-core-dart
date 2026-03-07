import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

import 'smk.dart';

/// Result of encrypting an artifact payload.
class EncryptedPayload {
  /// Ciphertext with authentication tag appended.
  final Uint8List ciphertext;

  /// SHA-256 hex digest of the compressed plaintext (pre-encryption).
  final String sha256;

  /// Algorithm identifier stored in the catalog.
  final String encAlg;

  const EncryptedPayload({
    required this.ciphertext,
    required this.sha256,
    required this.encAlg,
  });
}

/// Handles encryption and decryption of artifact payloads.
///
/// v1 flow (RFC-CORE-0004 Section 8):
///   encrypt: JSON bytes → (optional compress) → SHA-256 → AEAD encrypt
///   decrypt: AEAD decrypt → (optional decompress) → JSON bytes
///
/// Compression is deferred to Phase 2; v1 stores raw JSON bytes.
class ArtifactCrypto {
  static const String _encAlg = 'xchacha20poly1305';

  static final _cipher = Xchacha20.poly1305Aead();

  /// Encrypt an artifact JSON map using the given SMK.
  static Future<EncryptedPayload> encrypt(
    SMK smk,
    Map<String, dynamic> artifactJson,
  ) async {
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(artifactJson)));

    // SHA-256 of plaintext bytes (pre-encryption)
    final digest = hash.sha256.convert(plaintext);
    final sha256Hex = digest.toString();

    // AEAD encrypt
    final secretKey = SecretKey(smk.bytes);
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: secretKey,
    );

    // Pack as: nonce (24 bytes) || ciphertext || mac (16 bytes)
    final nonce = secretBox.nonce;
    final ct = secretBox.cipherText;
    final mac = secretBox.mac.bytes;

    final packed = Uint8List(nonce.length + ct.length + mac.length);
    packed.setAll(0, nonce);
    packed.setAll(nonce.length, ct);
    packed.setAll(nonce.length + ct.length, mac);

    return EncryptedPayload(
      ciphertext: packed,
      sha256: sha256Hex,
      encAlg: _encAlg,
    );
  }

  /// Decrypt an artifact payload back to a JSON map.
  static Future<Map<String, dynamic>> decrypt(
    SMK smk,
    Uint8List packed,
  ) async {
    // Unpack: nonce (24 bytes) || ciphertext || mac (16 bytes)
    const nonceLen = 24;
    const macLen = 16;
    if (packed.length < nonceLen + macLen) {
      throw ArgumentError('Payload too short to contain nonce + mac');
    }

    final nonce = packed.sublist(0, nonceLen);
    final ct = packed.sublist(nonceLen, packed.length - macLen);
    final macBytes = packed.sublist(packed.length - macLen);

    final secretBox = SecretBox(
      ct,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final secretKey = SecretKey(smk.bytes);
    final plaintext = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }
}
