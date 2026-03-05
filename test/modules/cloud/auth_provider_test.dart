import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:synheart_core/src/modules/interfaces/auth_provider.dart';
import 'package:synheart_core/src/modules/cloud/upload_client.dart';
import 'package:synheart_core/src/modules/cloud/upload_models.dart';
import 'package:synheart_core/src/modules/cloud/hmac_signer.dart';
import 'package:synheart_core/src/modules/cloud/cloud_exceptions.dart';
import 'package:synheart_core/src/config/synheart_config.dart';

/// Mock AuthProvider for testing
class MockAuthProvider extends AuthProvider {
  final Map<String, String> headers;
  bool onAuthErrorCalled = false;
  bool onAuthErrorResult;
  int signRequestCallCount = 0;

  MockAuthProvider({
    this.headers = const {'Authorization': 'ECDSA test-sig-123'},
    this.onAuthErrorResult = false,
  });

  @override
  Future<Map<String, String>> signRequest({
    required String method,
    required String path,
    required Uint8List bodyBytes,
  }) async {
    signRequestCallCount++;
    return headers;
  }

  @override
  Future<bool> onAuthError({
    required int statusCode,
    required Map<String, String> responseHeaders,
  }) async {
    onAuthErrorCalled = true;
    return onAuthErrorResult;
  }
}

void main() {
  late UploadRequest testPayload;

  setUp(() {
    testPayload = UploadRequest(
      userId: 'user_123',
      metadata: UploadMetadata(
        sdkVersion: '1.0.0',
        platform: 'dart',
        capabilityLevel: 'core',
      ),
      snapshots: [
        {
          'hsi_json': '{"hsi_version":"1.1"}',
          'timestamp': '2025-01-01T00:00:00Z',
        },
      ],
    );
  });

  group('AuthProvider integration', () {
    test('upload with AuthProvider uses provider headers (not HMAC)', () async {
      http.Request? capturedRequest;

      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'status': 'success', 'timestamp': 1704067200}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final authProvider = MockAuthProvider(
        headers: {
          'Authorization': 'ECDSA device-sig-abc',
          'X-Device-Id': 'dev-123',
        },
      );

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      await client.upload(
        payload: testPayload,
        authProvider: authProvider,
      );

      expect(capturedRequest, isNotNull);
      expect(
        capturedRequest!.headers['Authorization'],
        equals('ECDSA device-sig-abc'),
      );
      expect(capturedRequest!.headers['X-Device-Id'], equals('dev-123'));
      expect(
        capturedRequest!.headers['Content-Type'],
        equals('application/json'),
      );
      // HMAC headers should NOT be present
      expect(capturedRequest!.headers['X-Synheart-Signature'], isNull);
      expect(capturedRequest!.headers['X-API-Key'], isNull);
      expect(authProvider.signRequestCallCount, equals(1));
    });

    test('upload without AuthProvider uses HMAC (backward compat)', () async {
      http.Request? capturedRequest;

      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'status': 'success', 'timestamp': 1704067200}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final signer = HMACSigner(hmacSecret: 'test_secret');

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      await client.upload(
        payload: testPayload,
        signer: signer,
        apiKey: 'test_api_key',
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.headers['X-API-Key'], equals('test_api_key'));
      expect(capturedRequest!.headers['X-Synheart-Signature'], isNotNull);
      expect(capturedRequest!.headers['X-Synheart-Nonce'], isNotNull);
    });

    test('401 calls onAuthError, retries if handled', () async {
      int requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response(
            jsonEncode({
              'status': 'error',
              'code': 'auth_failed',
              'message': 'Device key expired',
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'status': 'success', 'timestamp': 1704067200}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final authProvider = MockAuthProvider(onAuthErrorResult: true);

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      final response = await client.upload(
        payload: testPayload,
        authProvider: authProvider,
      );

      expect(authProvider.onAuthErrorCalled, isTrue);
      expect(requestCount, equals(2));
      expect(response.status, equals('success'));
    });

    test('401 throws if onAuthError returns false', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'error',
            'code': 'invalid_signature',
            'message': 'Signature verification failed',
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final authProvider = MockAuthProvider(onAuthErrorResult: false);

      final client = UploadClient(
        baseUrl: 'https://api.test.com',
        httpClient: mockClient,
      );

      expect(
        () => client.upload(
          payload: testPayload,
          authProvider: authProvider,
        ),
        throwsA(isA<InvalidSignatureError>()),
      );
    });

    test('CloudConfig requires at least one of hmacSecret or authProvider', () {
      // Valid: hmacSecret only
      expect(
        () => CloudConfig(
          tenantId: 'test',
          hmacSecret: 'secret',
          subjectId: 'user',
          instanceId: 'inst',
          apiKey: 'key',
        ),
        returnsNormally,
      );

      // Valid: authProvider only
      expect(
        () => CloudConfig(
          tenantId: 'test',
          authProvider: MockAuthProvider(),
          subjectId: 'user',
          instanceId: 'inst',
        ),
        returnsNormally,
      );

      // Invalid: neither
      expect(
        () => CloudConfig(
          tenantId: 'test',
          subjectId: 'user',
          instanceId: 'inst',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
