import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:synheart_core/src/modules/cloud/hmac_signer.dart';
import 'package:synheart_core/src/modules/platform_ingest/platform_ingest_client.dart';

void main() {
  late HMACSigner signer;
  const apiKey = 'test_api_key';
  const baseUrl = 'https://ingest.test.io';

  setUp(() {
    signer = HMACSigner(hmacSecret: 'test_secret');
  });

  group('PlatformIngestClient', () {
    test('successful session ingest returns success response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'ok', 'batch_id': 'b123'}),
          200,
        );
      });

      final client = PlatformIngestClient(
        baseUrl: baseUrl,
        httpClient: mockClient,
      );

      final response = await client.ingestSession(
        payload: {'sessions': []},
        signer: signer,
        apiKey: apiKey,
      );

      expect(response.success, isTrue);
      expect(response.statusCode, equals(200));
      expect(response.body?['batch_id'], equals('b123'));
    });

    test('successful metadata ingest returns success response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'status': 'ok'}), 202);
      });

      final client = PlatformIngestClient(
        baseUrl: baseUrl,
        httpClient: mockClient,
      );

      final response = await client.ingestMetadata(
        payload: {'user_metadata': {}},
        signer: signer,
        apiKey: apiKey,
        consentToken: 'jwt_token_here',
      );

      expect(response.success, isTrue);
      expect(response.statusCode, equals(202));
    });

    test('request includes correct HMAC headers', () async {
      http.Request? captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final client = PlatformIngestClient(
        baseUrl: baseUrl,
        httpClient: mockClient,
      );

      await client.ingestSession(
        payload: {'sessions': []},
        signer: signer,
        apiKey: apiKey,
        consentToken: 'my_token',
      );

      expect(captured, isNotNull);
      expect(captured!.headers['X-API-Key'], equals(apiKey));
      expect(captured!.headers['X-Synheart-Signature'], isNotNull);
      expect(captured!.headers['X-Synheart-Timestamp'], isNotNull);
      expect(captured!.headers['X-Synheart-Nonce'], isNotNull);
      expect(captured!.headers['X-Consent-Token'], equals('my_token'));
      expect(captured!.headers['Content-Type'], equals('application/json'));
    });

    test('consent token header omitted when null', () async {
      http.Request? captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final client = PlatformIngestClient(
        baseUrl: baseUrl,
        httpClient: mockClient,
      );

      await client.ingestSession(
        payload: {'sessions': []},
        signer: signer,
        apiKey: apiKey,
      );

      expect(captured!.headers.containsKey('X-Consent-Token'), isFalse);
    });

    test('session ingest posts to correct path', () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final client = PlatformIngestClient(
        baseUrl: baseUrl,
        httpClient: mockClient,
      );

      await client.ingestSession(
        payload: {'sessions': []},
        signer: signer,
        apiKey: apiKey,
      );

      expect(capturedUri?.path, equals('/v1/platform/session/ingest'));
    });

    test('metadata ingest posts to correct path', () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final client = PlatformIngestClient(
        baseUrl: baseUrl,
        httpClient: mockClient,
      );

      await client.ingestMetadata(
        payload: {'user_metadata': {}},
        signer: signer,
        apiKey: apiKey,
      );

      expect(capturedUri?.path, equals('/v1/platform/metadata/ingest'));
    });

    test('4xx returns failure without retrying', () async {
      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response(
          jsonEncode({'error': 'bad request'}),
          400,
        );
      });

      final client = PlatformIngestClient(
        baseUrl: baseUrl,
        httpClient: mockClient,
        maxRetries: 3,
      );

      final response = await client.ingestSession(
        payload: {'sessions': []},
        signer: signer,
        apiKey: apiKey,
      );

      expect(response.success, isFalse);
      expect(response.statusCode, equals(400));
      expect(callCount, equals(1)); // No retries for client errors
    });

    test('5xx retries with exponential backoff', () async {
      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount < 3) {
          return http.Response('Server Error', 500);
        }
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final client = PlatformIngestClient(
        baseUrl: baseUrl,
        httpClient: mockClient,
        maxRetries: 3,
      );

      final response = await client.ingestSession(
        payload: {'sessions': []},
        signer: signer,
        apiKey: apiKey,
      );

      expect(response.success, isTrue);
      expect(callCount, equals(3));
    });

    test('network error retries and eventually fails', () async {
      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        throw Exception('Connection refused');
      });

      final client = PlatformIngestClient(
        baseUrl: baseUrl,
        httpClient: mockClient,
        maxRetries: 2,
      );

      final response = await client.ingestSession(
        payload: {'sessions': []},
        signer: signer,
        apiKey: apiKey,
      );

      expect(response.success, isFalse);
      expect(response.statusCode, equals(0));
      expect(response.errorMessage, contains('2 attempts'));
      expect(callCount, equals(2));
    });
  });
}
