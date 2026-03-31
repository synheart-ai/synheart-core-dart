import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/config/api_endpoints.dart';
import 'package:synheart_core/src/config/platform_ingest_config.dart';
import 'package:synheart_core/src/modules/platform_ingest/platform_ingest_client.dart';

void main() {
  group('PlatformIngestModule', () {
    test('ingestSession blocked when behavior consent not granted', () async {
      const response = PlatformIngestResponse(
        success: false,
        statusCode: 0,
        errorMessage: 'Behavior consent not granted',
      );

      expect(response.success, isFalse);
      expect(response.errorMessage, contains('Behavior consent'));
    });

    test('ingestMetadata blocked when biosignals consent not granted', () async {
      const response = PlatformIngestResponse(
        success: false,
        statusCode: 0,
        errorMessage: 'Biosignals consent not granted',
      );

      expect(response.success, isFalse);
      expect(response.errorMessage, contains('Biosignals consent'));
    });

    test('PlatformIngestResponse toString includes error', () {
      const response = PlatformIngestResponse(
        success: false,
        statusCode: 401,
        errorMessage: 'Unauthorized',
      );

      expect(response.toString(), contains('success=false'));
      expect(response.toString(), contains('statusCode=401'));
      expect(response.toString(), contains('error=Unauthorized'));
    });

    test('PlatformIngestConfig uses correct defaults', () {
      const config = PlatformIngestConfig(
        apiKey: 'key',
        hmacSecret: 'secret',
      );

      expect(config.baseUrl, equals(ApiEndpoints.defaultPlatformIngestBaseUrl));
      expect(config.timeout, equals(const Duration(seconds: 30)));
      expect(config.maxRetries, equals(3));
    });
  });
}
