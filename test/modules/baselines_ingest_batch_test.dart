import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

/// Unit tests for the public ingest-batch API on [Baselines].
///
/// These exercise lifecycle invariants only — depth counting, pending
/// flag, exception cleanup. Verifying that `_settleDerivedScores`
/// actually fires once per batch end requires a live FFI bridge and
/// belongs in integration tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Baselines.runIngestBatch lifecycle', () {
    setUp(() {
      Baselines.debugResetBatchState();
    });

    tearDown(() {
      Baselines.debugResetBatchState();
    });

    test('depth starts at zero', () {
      expect(Baselines.debugBatchDepth, 0);
      expect(Baselines.debugPendingDerivedSettle, isFalse);
    });

    test('beginIngestBatch / endIngestBatch increments and decrements', () {
      Baselines.beginIngestBatch();
      expect(Baselines.debugBatchDepth, 1);
      Baselines.endIngestBatch();
      expect(Baselines.debugBatchDepth, 0);
    });

    test('nested batches settle on outermost end', () {
      Baselines.beginIngestBatch();
      Baselines.beginIngestBatch();
      expect(Baselines.debugBatchDepth, 2);

      Baselines.endIngestBatch();
      // Inner end should not yet fire the settle — we're still in the
      // outer batch.
      expect(Baselines.debugBatchDepth, 1);

      Baselines.endIngestBatch();
      expect(Baselines.debugBatchDepth, 0);
    });

    test('runIngestBatch returns the body value and balances depth', () async {
      final result = await Baselines.runIngestBatch<int>(() async {
        expect(Baselines.debugBatchDepth, 1);
        return 42;
      });
      expect(result, 42);
      expect(Baselines.debugBatchDepth, 0);
    });

    test(
      'runIngestBatch propagates exceptions and still calls endIngestBatch',
      () async {
        await expectLater(
          () => Baselines.runIngestBatch<void>(() async {
            expect(Baselines.debugBatchDepth, 1);
            throw StateError('boom');
          }),
          throwsA(isA<StateError>()),
        );
        // Depth must be back to zero — the guard form's whole reason
        // for existing.
        expect(Baselines.debugBatchDepth, 0);
      },
    );

    test('endIngestBatch with depth=0 is a no-op (no throw)', () {
      // Defensive: defensive call without a matching begin. Logs a
      // warning but must not throw or move the counter into negatives.
      expect(() => Baselines.endIngestBatch(), returnsNormally);
      expect(Baselines.debugBatchDepth, 0);
    });

    test('concurrent runIngestBatch calls nest correctly', () async {
      final outer = Baselines.runIngestBatch<void>(() async {
        await Baselines.runIngestBatch<void>(() async {
          expect(Baselines.debugBatchDepth, 2);
        });
        // Inner should have decremented; outer still active.
        expect(Baselines.debugBatchDepth, 1);
      });
      await outer;
      expect(Baselines.debugBatchDepth, 0);
    });
  });
}
