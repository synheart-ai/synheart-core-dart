import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/modules/cloud/hmac_signer.dart';

void main() {
  group('HMACSigner', () {
    test('generates valid UUID v4 nonce format', () {
      final signer = HMACSigner(hmacSecret: 'test_secret');
      final nonce = signer.generateNonce();

      // UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      expect(nonce, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('computes correct HMAC signature', () {
      final signer = HMACSigner(hmacSecret: 'test_secret');

      final signature = signer.computeSignature(
        timestamp: '1704067200',
        bodyJson: '{"test":"data"}',
      );

      expect(signature, isNotEmpty);
      expect(signature.length, equals(64)); // SHA256 hex length
    });

    test('generates different nonces each time', () {
      final signer = HMACSigner(hmacSecret: 'test_secret');

      final nonce1 = signer.generateNonce();
      final nonce2 = signer.generateNonce();

      expect(nonce1, isNot(equals(nonce2)));
    });

    test('signature changes with different body content', () {
      final signer = HMACSigner(hmacSecret: 'test_secret');

      final signature1 = signer.computeSignature(
        timestamp: '1704067200',
        bodyJson: '{"test":"data1"}',
      );

      final signature2 = signer.computeSignature(
        timestamp: '1704067200',
        bodyJson: '{"test":"data2"}',
      );

      expect(signature1, isNot(equals(signature2)));
    });

    test('signature is deterministic for same inputs', () {
      final signer = HMACSigner(hmacSecret: 'test_secret');

      final signature1 = signer.computeSignature(
        timestamp: '1704067200',
        bodyJson: '{"test":"data"}',
      );

      final signature2 = signer.computeSignature(
        timestamp: '1704067200',
        bodyJson: '{"test":"data"}',
      );

      expect(signature1, equals(signature2));
    });
  });
}
