import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/artifacts/artifact_id.dart';

void main() {
  group('computeArtifactId golden vectors', () {
    // All vectors from synheart-core/test/vectors/artifact_id_vectors.json

    test('Vector 1 — HSIWindow', () {
      final id = computeArtifactId(
        type: 'hsi_window',
        subjectId: 'usr_abc123',
        sessionId: 'sess_def456',
        startMs: 1709251200000,
        endMs: 1709251230000,
        schemaName: 'hsi_window',
        schemaVersion: '1',
      );
      expect(id,
          '5e9f3c5a3c3279397da3fcd9361dd87b865b84843354a97bdedf8d8925190470');
    });

    test('Vector 2 — BaselineSnapshot (no session)', () {
      final id = computeArtifactId(
        type: 'baseline_snapshot',
        subjectId: 'usr_abc123',
        sessionId: null,
        startMs: 1709164800000,
        endMs: 1709251200000,
        schemaName: 'baseline_snapshot',
        schemaVersion: '1',
      );
      expect(id,
          '3eb16bd8bfffa0314bf1c62f101ac3c1d118bdfe0080c10109db8dc2bdeeed87');
    });

    test('Vector 3 — Tombstone', () {
      final id = computeArtifactId(
        type: 'tombstone',
        subjectId: 'usr_abc123',
        sessionId: null,
        startMs: 1709251230000,
        endMs: 1709251230000,
        schemaName: 'tombstone',
        schemaVersion: '1',
      );
      expect(id,
          '6cb42834a752f7cc9dd4c435a00500480754b5f271711fc34f7dc75596428807');
    });

    test('Vector 4 — SessionSummary', () {
      final id = computeArtifactId(
        type: 'session_summary',
        subjectId: 'usr_abc123',
        sessionId: 'sess_def456',
        startMs: 1709251200000,
        endMs: 1709251260000,
        schemaName: 'session_summary',
        schemaVersion: '1',
      );
      expect(id,
          '78325014084c858ca8e38b568c68cfe011e10d5d720a0acb89fddaf1bd5d00ff');
    });
  });

  group('computeArtifactId validation', () {
    test('rejects empty type', () {
      expect(
        () => computeArtifactId(
          type: '',
          subjectId: 'usr_abc',
          startMs: 0,
          endMs: 0,
          schemaName: 'test',
          schemaVersion: '1',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects field containing pipe delimiter', () {
      expect(
        () => computeArtifactId(
          type: 'hsi_window',
          subjectId: 'usr|bad',
          startMs: 0,
          endMs: 0,
          schemaName: 'test',
          schemaVersion: '1',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
