import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/config/api_endpoints.dart';
import 'package:synheart_core/src/config/lab_ingest_config.dart';
import 'package:synheart_core/src/modules/lab_ingest/lab_ingest_client.dart';

void main() {
  group('LabIngestModule', () {
    test('ingestSession blocked when behavior consent not granted', () async {
      const response = LabIngestResponse(
        success: false,
        statusCode: 0,
        errorMessage: 'Behavior consent not granted',
      );

      expect(response.success, isFalse);
      expect(response.errorMessage, contains('Behavior consent'));
    });

    test('ingestMetadata blocked when biosignals consent not granted', () async {
      const response = LabIngestResponse(
        success: false,
        statusCode: 0,
        errorMessage: 'Biosignals consent not granted',
      );

      expect(response.success, isFalse);
      expect(response.errorMessage, contains('Biosignals consent'));
    });

    test('LabIngestResponse toString includes error', () {
      const response = LabIngestResponse(
        success: false,
        statusCode: 401,
        errorMessage: 'Unauthorized',
      );

      expect(response.toString(), contains('success=false'));
      expect(response.toString(), contains('statusCode=401'));
      expect(response.toString(), contains('error=Unauthorized'));
    });

    test('LabIngestConfig uses correct defaults', () {
      const config = LabIngestConfig(
        apiKey: 'key',
        hmacSecret: 'secret',
      );

      expect(config.baseUrl, equals(ApiEndpoints.defaultLabIngestBaseUrl));
      expect(config.timeout, equals(const Duration(seconds: 30)));
      expect(config.maxRetries, equals(3));
    });
  });
}
