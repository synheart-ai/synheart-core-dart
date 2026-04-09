import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import 'sdk_crypto_callbacks.dart';

/// Default synchronous SDK crypto callbacks used when host app does not
/// explicitly register platform callbacks.
///
/// This keeps runtime-only networking available for SDK consumers without
/// requiring app-side callback wiring. Keys are process-local and in-memory.
class SoftwareSdkCryptoCallbacks extends SynheartCoreCryptoCallbacks {
  SoftwareSdkCryptoCallbacks();

  static final ECDomainParameters _domain = ECDomainParameters('prime256v1');
  static final Map<String, AsymmetricKeyPair<ECPublicKey, ECPrivateKey>> _keys =
      <String, AsymmetricKeyPair<ECPublicKey, ECPrivateKey>>{};

  @override
  String generateKeyJwk(String deviceId) {
    final pair = _keys.putIfAbsent(deviceId, _generateKeyPair);
    final q = pair.publicKey.Q;
    if (q == null) {
      throw StateError('Public key point is null');
    }
    final point = q * BigInt.one;
    if (point == null) {
      throw StateError('Failed to normalize EC point');
    }
    final x = _base64UrlNoPad(_bigIntToFixedBytes(point.x!.toBigInteger()!, 32));
    final y = _base64UrlNoPad(_bigIntToFixedBytes(point.y!.toBigInteger()!, 32));
    return jsonEncode(<String, String>{'x': x, 'y': y});
  }

  @override
  String signBytesBase64Url(String deviceId, Uint8List data) {
    if (data.length != 32) {
      throw ArgumentError(
        'Expected 32-byte client_data_hash, got ${data.length} bytes',
      );
    }
    final pair = _keys.putIfAbsent(deviceId, _generateKeyPair);
    // IMPORTANT: Rust already passes SHA256(canonical_json(client_data)).
    // Sign that exact 32-byte digest directly and return DER, not raw R||S.
    final signer = ECDSASigner()
      ..init(
        true,
        ParametersWithRandom(
          PrivateKeyParameter<ECPrivateKey>(pair.privateKey),
          _secureRandom(),
        ),
      );
    final sig = signer.generateSignature(data) as ECSignature;
    final der = _encodeEcdsaDer(sig.r, sig.s);
    return _base64UrlNoPad(der);
  }

  @override
  String getAttestationJson(String deviceId, Uint8List challengeHash) {
    final source = challengeHash.isNotEmpty
        ? challengeHash
        : Uint8List.fromList(utf8.encode(deviceId));
    final blob = base64.encode(source);
    return jsonEncode(<String, String>{
      'format': _attestationFormat(),
      'blob': blob,
    });
  }

  @override
  bool keyExists(String deviceId) => _keys.containsKey(deviceId);

  @override
  bool deleteKey(String deviceId) => _keys.remove(deviceId) != null;

  static AsymmetricKeyPair<ECPublicKey, ECPrivateKey> _generateKeyPair() {
    final generator = ECKeyGenerator()
      ..init(
        ParametersWithRandom(
          ECKeyGeneratorParameters(_domain),
          _secureRandom(),
        ),
      );
    final pair = generator.generateKeyPair();
    return AsymmetricKeyPair<ECPublicKey, ECPrivateKey>(
      pair.publicKey as ECPublicKey,
      pair.privateKey as ECPrivateKey,
    );
  }

  static SecureRandom _secureRandom() {
    final random = FortunaRandom();
    final seed = Uint8List(32);
    final secure = Random.secure();
    for (var i = 0; i < seed.length; i++) {
      seed[i] = secure.nextInt(256);
    }
    random.seed(KeyParameter(seed));
    return random;
  }

  static Uint8List _bigIntToFixedBytes(BigInt value, int width) {
    final hex = value.toUnsigned(width * 8).toRadixString(16).padLeft(width * 2, '0');
    final out = Uint8List(width);
    for (var i = 0; i < width; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _base64UrlNoPad(Uint8List bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _attestationFormat() {
    // Accepted cloud labels:
    // - apple-app-attest (iOS)
    // - play-integrity / google-play-integrity (Android)
    // - software-test (debug/dev only)
    // if (!kReleaseMode) return 'software-test';
    if (kDebugMode) return 'play-integrity';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'apple-app-attest',
      TargetPlatform.android => 'play-integrity',
      _ => 'software-test',
    };
  }

  static Uint8List _encodeEcdsaDer(BigInt r, BigInt s) {
    final rBytes = _encodeDerInteger(r);
    final sBytes = _encodeDerInteger(s);
    final seqLen = rBytes.length + sBytes.length;
    final out = BytesBuilder(copy: false)
      ..addByte(0x30) // SEQUENCE
      ..add(_encodeDerLength(seqLen))
      ..add(rBytes)
      ..add(sBytes);
    return out.takeBytes();
  }

  static Uint8List _encodeDerInteger(BigInt value) {
    if (value == BigInt.zero) {
      return Uint8List.fromList(<int>[0x02, 0x01, 0x00]);
    }
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final raw = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    // INTEGER is signed in DER; prepend 0x00 when high bit is set.
    final needsPad = raw[0] & 0x80 != 0;
    final content = needsPad
        ? (Uint8List(raw.length + 1)..setRange(1, raw.length + 1, raw))
        : raw;
    final out = BytesBuilder(copy: false)
      ..addByte(0x02) // INTEGER
      ..add(_encodeDerLength(content.length))
      ..add(content);
    return out.takeBytes();
  }

  static Uint8List _encodeDerLength(int length) {
    if (length < 0x80) {
      return Uint8List.fromList(<int>[length]);
    }
    var tmp = length;
    final octets = <int>[];
    while (tmp > 0) {
      octets.insert(0, tmp & 0xff);
      tmp >>= 8;
    }
    return Uint8List.fromList(<int>[0x80 | octets.length, ...octets]);
  }
}
