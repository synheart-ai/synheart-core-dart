import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SynheartIngestion without runtime bridge', () {
    test('submitSessionArtifacts returns bridge unavailable', () async {
      final response = await Synheart.ingestion.submitSessionArtifacts({
        'session_metadata': {'id': 'demo'},
      });
      expect(response.success, isFalse);
      expect(response.statusCode, 503);
    });

    test('submitMetadata returns bridge unavailable', () async {
      final response = await Synheart.ingestion.submitMetadata({
        'app_metadata': {'id': 'demo'},
      });
      expect(response.success, isFalse);
      expect(response.statusCode, 503);
    });

    test(
      'ensureCloudConsentReady returns false when bridge unavailable',
      () async {
        final ready = await Synheart.ensureCloudConsentReady();
        expect(ready, isFalse);
      },
    );

    test('flushIfEligible reports runtime error and updates status', () async {
      final flush = await Synheart.ingestion.flushIfEligible();
      expect(flush.success, isFalse);
      expect(flush.errorMessage, isNotNull);

      final status = Synheart.ingestion.queueStatus;
      expect(status.lastUploadAttemptAt, isNotNull);
      expect(status.lastUploadError, isNotNull);
      expect(status.queueLength, greaterThanOrEqualTo(0));
    });
  });
}
