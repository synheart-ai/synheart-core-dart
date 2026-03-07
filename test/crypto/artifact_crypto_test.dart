import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/crypto/smk.dart';
import 'package:synheart_core/src/crypto/artifact_crypto.dart';

void main() {
  group('ArtifactCrypto round-trip', () {
    test('encrypt then decrypt returns original payload', () async {
      final smk = SMK.generate();

      final original = {
        'type': 'hsi_window',
        'artifact_id': 'abc123',
        'window': {
          'start_ms': 1709251200000,
          'end_ms': 1709251230000,
          'hsi': {'focus': 0.72, 'arousal': 0.45},
        },
      };

      final encrypted = await ArtifactCrypto.encrypt(smk, original);

      expect(encrypted.encAlg, 'xchacha20poly1305');
      expect(encrypted.sha256, isNotEmpty);
      expect(encrypted.ciphertext.length, greaterThan(24 + 16)); // nonce + mac minimum

      final decrypted = await ArtifactCrypto.decrypt(smk, encrypted.ciphertext);

      expect(decrypted['type'], 'hsi_window');
      expect(decrypted['artifact_id'], 'abc123');
      expect((decrypted['window'] as Map)['hsi']['focus'], 0.72);
    });

    test('decrypt with wrong key fails', () async {
      final smk1 = SMK.generate();
      final smk2 = SMK.generate();

      final original = {'test': 'data'};
      final encrypted = await ArtifactCrypto.encrypt(smk1, original);

      expect(
        () => ArtifactCrypto.decrypt(smk2, encrypted.ciphertext),
        throwsA(anything),
      );
    });

    test('sha256 is consistent for same input', () async {
      final smk = SMK.generate();
      final payload = {'value': 42};

      final e1 = await ArtifactCrypto.encrypt(smk, payload);
      final e2 = await ArtifactCrypto.encrypt(smk, payload);

      // SHA-256 of the same plaintext should be identical
      expect(e1.sha256, e2.sha256);

      // Ciphertexts differ due to random nonces
      expect(e1.ciphertext, isNot(equals(e2.ciphertext)));
    });

    test('payload too short to decrypt throws', () async {
      final smk = SMK.generate();
      final tooShort = Uint8List(30); // less than nonce(24) + mac(16)

      expect(
        () => ArtifactCrypto.decrypt(smk, tooShort),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SMK', () {
    test('generate creates 32-byte key', () {
      final smk = SMK.generate();
      expect(smk.bytes.length, 32);
    });

    test('fromBytes accepts 32 bytes', () {
      final bytes = Uint8List(32);
      final smk = SMK.fromBytes(bytes);
      expect(smk.bytes.length, 32);
    });

    test('fromBytes rejects wrong length', () {
      expect(() => SMK.fromBytes(Uint8List(16)), throwsA(isA<ArgumentError>()));
      expect(() => SMK.fromBytes(Uint8List(64)), throwsA(isA<ArgumentError>()));
    });

    test('two generated keys differ', () {
      final a = SMK.generate();
      final b = SMK.generate();
      expect(a.bytes, isNot(equals(b.bytes)));
    });
  });
}
