import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/modules/cloud/hmac_signer.dart';

void main() {
  group('HMACSigner', () {
    test('generates valid nonce format', () {
      final signer = HMACSigner(hmacSecret: 'test_secret');
      final nonce = signer.generateNonce();

      expect(nonce, matches(RegExp(r'^\d+_[a-f0-9]{24}$')));
    });

    test('computes correct HMAC signature', () {
      final signer = HMACSigner(hmacSecret: 'test_secret');

      final signature = signer.computeSignature(
        method: 'POST',
        path: '/v1/ingest/hsi',
        tenantId: 'test_tenant',
        timestamp: 1704067200,
        nonce: '1704067200_abc123',
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
        method: 'POST',
        path: '/v1/ingest/hsi',
        tenantId: 'test_tenant',
        timestamp: 1704067200,
        nonce: '1704067200_abc123',
        bodyJson: '{"test":"data1"}',
      );

      final signature2 = signer.computeSignature(
        method: 'POST',
        path: '/v1/ingest/hsi',
        tenantId: 'test_tenant',
        timestamp: 1704067200,
        nonce: '1704067200_abc123',
        bodyJson: '{"test":"data2"}',
      );

      expect(signature1, isNot(equals(signature2)));
    });

    test('signature is deterministic for same inputs', () {
      final signer = HMACSigner(hmacSecret: 'test_secret');

      final signature1 = signer.computeSignature(
        method: 'POST',
        path: '/v1/ingest/hsi',
        tenantId: 'test_tenant',
        timestamp: 1704067200,
        nonce: '1704067200_abc123',
        bodyJson: '{"test":"data"}',
      );

      final signature2 = signer.computeSignature(
        method: 'POST',
        path: '/v1/ingest/hsi',
        tenantId: 'test_tenant',
        timestamp: 1704067200,
        nonce: '1704067200_abc123',
        bodyJson: '{"test":"data"}',
      );

      expect(signature1, equals(signature2));
    });
  });
}
