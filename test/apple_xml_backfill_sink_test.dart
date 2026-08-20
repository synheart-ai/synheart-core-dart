// SPDX-License-Identifier: Apache-2.0
//
// Pure-Dart unit tests for the Apple XML backfill sink. The
// integration with a real native runtime is exercised by the
// runtime's own internal tests; here we only verify the type surface
// and the error-handling contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/backfill/apple_xml_backfill_sink.dart';

void main() {
  group('BackfillBatchResult', () {
    test('holds inserted + skipped counts', () {
      const r = BackfillBatchResult(inserted: 100, skippedAsDuplicate: 5);
      expect(r.inserted, 100);
      expect(r.skippedAsDuplicate, 5);
    });
  });

  group('BackfillImportResult', () {
    test('holds final tally', () {
      const r = BackfillImportResult(
        importId: 'import-001',
        totalSamples: 1000,
        inserted: 950,
        skippedAsDuplicate: 50,
        durationMs: 1234,
      );
      expect(r.importId, 'import-001');
      expect(r.totalSamples, 1000);
      expect(r.inserted, 950);
      expect(r.skippedAsDuplicate, 50);
      expect(r.durationMs, 1234);
    });
  });

  group('BackfillSinkError types', () {
    test('all variants stringify usefully', () {
      const errs = <BackfillSinkError>[
        BackfillRuntimeUnavailable(),
        BackfillOpenFailed('open failed'),
        BackfillBatchFailed('batch failed'),
        BackfillFinalizeFailed('finalize failed'),
      ];
      for (final e in errs) {
        final s = e.toString();
        expect(s, startsWith('BackfillSinkError:'));
        expect(s, contains(e.message));
      }
    });

    test('runtime-unavailable names the fix, not a version number', () {
      // Previously asserted the literal '5.4.0'. That version string was
      // already stale — the runtime versions as 0.x — so the assertion pinned
      // misinformation. What matters is that the message tells the developer
      // what to do about it.
      const e = BackfillRuntimeUnavailable();
      expect(e.message, contains('synheart install runtime'));
      expect(e.message, isNot(contains('5.4.0')));
    });

    test('errors are sealed — only the four known variants exist', () {
      const BackfillSinkError e = BackfillRuntimeUnavailable();
      // Exhaustive switch must compile; if a new variant is added
      // and this switch is missing a branch, dart analyzer flags it.
      final tag = switch (e) {
        BackfillRuntimeUnavailable() => 'unavailable',
        BackfillOpenFailed() => 'open',
        BackfillBatchFailed() => 'batch',
        BackfillFinalizeFailed() => 'finalize',
      };
      expect(tag, 'unavailable');
    });
  });
}
