import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:synheart_core/src/crypto/urk.dart';

void main() {
  group('URK', () {
    test('generates 32-byte key', () {
      final urk = URK.generate();
      expect(urk.bytes.length, equals(32));
    });

    test('fromBytes validates length', () {
      expect(() => URK.fromBytes(Uint8List(16)), throwsArgumentError);
      final urk = URK.fromBytes(Uint8List(32));
      expect(urk.bytes.length, equals(32));
    });

    test('generates unique keys', () {
      final a = URK.generate();
      final b = URK.generate();
      expect(a.bytes, isNot(equals(b.bytes)));
    });

    test('derives BEK deterministically', () async {
      final bek1 = await URK.deriveBEK(
        sessionSecret: 'test_secret',
        subjectId: 'usr_123',
      );
      final bek2 = await URK.deriveBEK(
        sessionSecret: 'test_secret',
        subjectId: 'usr_123',
      );
      expect(bek1, equals(bek2));
      expect(bek1.length, equals(32));
    });

    test('different subjects produce different BEKs', () async {
      final bek1 = await URK.deriveBEK(
        sessionSecret: 'test_secret',
        subjectId: 'usr_123',
      );
      final bek2 = await URK.deriveBEK(
        sessionSecret: 'test_secret',
        subjectId: 'usr_456',
      );
      expect(bek1, isNot(equals(bek2)));
    });

    test('derives artifact key deterministically', () async {
      final urk = Uint8List(32);
      for (var i = 0; i < 32; i++) urk[i] = i;

      final key1 = await URK.deriveArtifactKey(
        urk: urk,
        artifactId: 'art_123',
      );
      final key2 = await URK.deriveArtifactKey(
        urk: urk,
        artifactId: 'art_123',
      );
      expect(key1, equals(key2));
      expect(key1.length, equals(32));
    });

    test('different artifact IDs produce different keys', () async {
      final urk = Uint8List(32);
      for (var i = 0; i < 32; i++) urk[i] = i;

      final key1 = await URK.deriveArtifactKey(
        urk: urk,
        artifactId: 'art_123',
      );
      final key2 = await URK.deriveArtifactKey(
        urk: urk,
        artifactId: 'art_456',
      );
      expect(key1, isNot(equals(key2)));
    });

    test('encrypts and decrypts bundle round-trip', () async {
      final urk = URK.generate();
      final bundle = await URK.encryptBundle(
        urk: urk.bytes,
        sessionSecret: 'my_secret',
        subjectId: 'usr_abc',
      );

      expect(bundle['urk_bundle_version'], equals('1'));
      expect(bundle['ciphertext_b64'], isNotEmpty);
      expect(bundle['nonce_b64'], isNotEmpty);
      expect(bundle['kdf_info'], equals('synheart-urk-bundle:v1'));

      final decrypted = await URK.decryptBundle(
        bundle: bundle,
        sessionSecret: 'my_secret',
        subjectId: 'usr_abc',
      );
      expect(decrypted.bytes, equals(urk.bytes));
    });

    test('wrong secret fails to decrypt bundle', () async {
      final urk = URK.generate();
      final bundle = await URK.encryptBundle(
        urk: urk.bytes,
        sessionSecret: 'correct_secret',
        subjectId: 'usr_abc',
      );

      expect(
        () => URK.decryptBundle(
          bundle: bundle,
          sessionSecret: 'wrong_secret',
          subjectId: 'usr_abc',
        ),
        throwsA(anything),
      );
    });
  });
}
