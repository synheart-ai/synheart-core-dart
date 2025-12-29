import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:synheart_core/src/modules/cloud/upload_client.dart';
import 'package:synheart_core/src/modules/cloud/upload_models.dart';
import 'package:synheart_core/src/modules/cloud/hmac_signer.dart';
import 'package:synheart_core/src/modules/cloud/cloud_exceptions.dart';
import 'dart:convert';

void main() {
  group('UploadClient', () {
    late HMACSigner signer;
    late UploadRequest testPayload;

    setUp(() {
      signer = HMACSigner(hmacSecret: 'test_secret');
      testPayload = UploadRequest(
        subject: Subject(
          subjectType: 'test_user',
          subjectId: 'user_123',
        ),
        snapshots: [
          {'hsi_version': '1.0', 'test': 'data'}
        ],
      );
    });

    test('successful upload returns UploadResponse', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'snapshot_id': 'snap_123',
            'timestamp': 1704067200,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      final response = await client.upload(
        payload: testPayload,
        signer: signer,
        tenantId: 'test_tenant',
      );

      expect(response.status, equals('success'));
      expect(response.snapshotId, equals('snap_123'));
      expect(response.timestamp, equals(1704067200));
    });

    test('401 invalid_signature throws InvalidSignatureError', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'error',
            'code': 'invalid_signature',
            'message': 'HMAC signature validation failed',
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      expect(
        () => client.upload(
          payload: testPayload,
          signer: signer,
          tenantId: 'test_tenant',
        ),
        throwsA(isA<InvalidSignatureError>()),
      );
    });

    test('403 invalid_tenant throws InvalidTenantError', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'error',
            'code': 'invalid_tenant',
            'message': 'Tenant ID not found',
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      expect(
        () => client.upload(
          payload: testPayload,
          signer: signer,
          tenantId: 'test_tenant',
        ),
        throwsA(isA<InvalidTenantError>()),
      );
    });

    test('400 schema_validation_failed throws SchemaValidationError', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'error',
            'code': 'schema_validation_failed',
            'message': 'Invalid HSI 1.0 format',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      expect(
        () => client.upload(
          payload: testPayload,
          signer: signer,
          tenantId: 'test_tenant',
        ),
        throwsA(isA<SchemaValidationError>()),
      );
    });

    test('429 rate limit throws RateLimitExceededError', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'error',
            'code': 'rate_limit_exceeded',
            'message': 'Too many requests',
            'retry_after': 60,
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      expect(
        () => client.upload(
          payload: testPayload,
          signer: signer,
          tenantId: 'test_tenant',
        ),
        throwsA(isA<RateLimitExceededError>()),
      );
    });

    test('request includes all required headers', () async {
      http.Request? capturedRequest;

      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'timestamp': 1704067200,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      await client.upload(
        payload: testPayload,
        signer: signer,
        tenantId: 'test_tenant',
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.headers['Content-Type'], equals('application/json'));
      expect(capturedRequest!.headers['X-Synheart-Tenant'], equals('test_tenant'));
      expect(capturedRequest!.headers['X-Synheart-Signature'], isNotNull);
      expect(capturedRequest!.headers['X-Synheart-Nonce'], isNotNull);
      expect(capturedRequest!.headers['X-Synheart-Timestamp'], isNotNull);
      expect(capturedRequest!.headers['X-Synheart-SDK-Version'], equals('1.0.0'));
    });

    test('retries on transient errors up to max attempts', () async {
      int attemptCount = 0;

      final mockClient = MockClient((request) async {
        attemptCount++;
        if (attemptCount < 3) {
          throw Exception('Network error');
        }
        return http.Response(
          jsonEncode({
            'status': 'success',
            'timestamp': 1704067200,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      final response = await client.upload(
        payload: testPayload,
        signer: signer,
        tenantId: 'test_tenant',
      );

      expect(attemptCount, equals(3));
      expect(response.status, equals('success'));
    });

    test('throws NetworkError after max retry attempts', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network error');
      });

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      expect(
        () => client.upload(
          payload: testPayload,
          signer: signer,
          tenantId: 'test_tenant',
        ),
        throwsA(isA<NetworkError>()),
      );
    });
  });
}
