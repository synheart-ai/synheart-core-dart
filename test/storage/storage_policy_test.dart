import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/config/synheart_mode.dart';
import 'package:synheart_core/src/storage/storage_policy.dart';

void main() {
  group('StoragePolicy — Personal', () {
    final policy = StoragePolicy.forMode(SynheartMode.personal);

    test('allows Tier A artifact types', () {
      expect(policy.canPersistArtifact('hsi_window'), isTrue);
      expect(policy.canPersistArtifact('session_summary'), isTrue);
      expect(policy.canPersistArtifact('baseline_snapshot'), isTrue);
      expect(policy.canPersistArtifact('tombstone'), isTrue);
    });

    test('rejects non-Tier-A artifact types', () {
      expect(policy.canPersistArtifact('raw_ecg'), isFalse);
      expect(policy.canPersistArtifact('bio_stream'), isFalse);
    });

    test('allows hsi.snapshot stream', () {
      expect(policy.canPersistStream('hsi.snapshot'), isTrue);
    });

    test('rejects app.metrics and behavior.events streams', () {
      expect(policy.canPersistStream('app.metrics'), isFalse);
      expect(policy.canPersistStream('behavior.events'), isFalse);
      expect(policy.canPersistStream('bio.ecg'), isFalse);
    });

    test('does not allow metrics', () {
      expect(policy.canIncludeMetrics(), isFalse);
    });
  });

  group('StoragePolicy — Insight', () {
    final policy = StoragePolicy.forMode(SynheartMode.insight);

    test('allows Tier A artifact types', () {
      expect(policy.canPersistArtifact('hsi_window'), isTrue);
      expect(policy.canPersistArtifact('session_summary'), isTrue);
      expect(policy.canPersistArtifact('baseline_snapshot'), isTrue);
      expect(policy.canPersistArtifact('tombstone'), isTrue);
    });

    test('rejects non-Tier-A artifact types', () {
      expect(policy.canPersistArtifact('raw_ecg'), isFalse);
    });

    test('allows hsi.snapshot, app.metrics, behavior.events streams', () {
      expect(policy.canPersistStream('hsi.snapshot'), isTrue);
      expect(policy.canPersistStream('app.metrics'), isTrue);
      expect(policy.canPersistStream('behavior.events'), isTrue);
    });

    test('rejects bio streams', () {
      expect(policy.canPersistStream('bio.ecg'), isFalse);
    });

    test('allows metrics', () {
      expect(policy.canIncludeMetrics(), isTrue);
    });
  });

  group('StoragePolicy — Research', () {
    final policy = StoragePolicy.forMode(SynheartMode.research);

    test('allows all artifact types', () {
      expect(policy.canPersistArtifact('hsi_window'), isTrue);
      expect(policy.canPersistArtifact('raw_ecg'), isTrue);
      expect(policy.canPersistArtifact('anything'), isTrue);
    });

    test('allows all stream types', () {
      expect(policy.canPersistStream('hsi.snapshot'), isTrue);
      expect(policy.canPersistStream('app.metrics'), isTrue);
      expect(policy.canPersistStream('bio.ecg'), isTrue);
      expect(policy.canPersistStream('anything'), isTrue);
    });

    test('allows metrics', () {
      expect(policy.canIncludeMetrics(), isTrue);
    });
  });
}
