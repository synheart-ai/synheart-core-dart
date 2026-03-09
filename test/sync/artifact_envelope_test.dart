import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/sync/artifact_envelope.dart';

void main() {
  group('ArtifactEnvelope', () {
    test('serializes to and from JSON', () {
      final envelope = ArtifactEnvelope(
        artifactId: 'art_123',
        subjectId: 'usr_456',
        sessionId: 'sess_789',
        type: 'hsi_window',
        startMs: 1000,
        endMs: 2000,
        seq: 1,
        schemaName: 'hsi_window',
        schemaVersion: '1.0',
        nonceB64: 'bm9uY2U=',
        payloadSha256: 'abc123',
        ciphertextB64: 'Y2lwaGVydGV4dA==',
      );

      final json = envelope.toJson();
      expect(json['artifact_id'], equals('art_123'));
      expect(json['subject_id'], equals('usr_456'));
      expect(json['session_id'], equals('sess_789'));
      expect(json['type'], equals('hsi_window'));
      expect(json['time_range']['start_ms'], equals(1000));
      expect(json['time_range']['end_ms'], equals(2000));
      expect(json['seq'], equals(1));
      expect(json['schema']['name'], equals('hsi_window'));
      expect(json['crypto']['alg'], equals('XCHACHA20POLY1305'));

      final deserialized = ArtifactEnvelope.fromJson(json);
      expect(deserialized.artifactId, equals('art_123'));
      expect(deserialized.subjectId, equals('usr_456'));
      expect(deserialized.sessionId, equals('sess_789'));
      expect(deserialized.startMs, equals(1000));
      expect(deserialized.endMs, equals(2000));
      expect(deserialized.seq, equals(1));
      expect(deserialized.nonceB64, equals('bm9uY2U='));
      expect(deserialized.ciphertextB64, equals('Y2lwaGVydGV4dA=='));
    });

    test('handles null session_id', () {
      final envelope = ArtifactEnvelope(
        artifactId: 'art_123',
        subjectId: 'usr_456',
        type: 'baseline_snapshot',
        startMs: 1000,
        endMs: 2000,
        schemaName: 'baseline',
        schemaVersion: '1.0',
        nonceB64: 'bm9uY2U=',
        payloadSha256: 'abc123',
        ciphertextB64: 'Y2lwaGVydGV4dA==',
      );

      final json = envelope.toJson();
      expect(json.containsKey('session_id'), isFalse);

      final deserialized = ArtifactEnvelope.fromJson(json);
      expect(deserialized.sessionId, isNull);
    });
  });

  group('SyncResult', () {
    test('defaults to zero', () {
      const result = SyncResult();
      expect(result.pushed, equals(0));
      expect(result.pulled, equals(0));
      expect(result.conflictsResolved, equals(0));
      expect(result.errors, isEmpty);
    });
  });

  group('SyncStatus', () {
    test('holds all fields', () {
      const status = SyncStatus(
        enabled: true,
        lastSuccessMs: 1234567890,
        pendingUploadCount: 5,
        cursor: 'abc',
      );
      expect(status.enabled, isTrue);
      expect(status.lastSuccessMs, equals(1234567890));
      expect(status.pendingUploadCount, equals(5));
      expect(status.cursor, equals('abc'));
    });
  });
}
