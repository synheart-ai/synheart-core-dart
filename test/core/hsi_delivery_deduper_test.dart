import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/core/hsi_delivery_deduper.dart';

/// Drives [HsiDeliveryDeduper] — the type `Synheart._deliverHsiWindow`
/// actually calls.
///
/// The previous version of this file re-implemented the id extraction inside
/// the test and asserted against that copy, so it passed regardless of what the
/// SDK did. These call the real class.
void main() {
  String window(String? id) => jsonEncode({
    'hsi_version': '1.3',
    'timestamp_ms': 1750000000000,
    if (id != null)
      'meta': {
        'ids': {'hsi_id': id},
      },
  });

  group('duplicate suppression', () {
    test('A, A — the repeat is dropped', () {
      final d = HsiDeliveryDeduper();
      expect(d.shouldDeliver(window('A')), isTrue);
      expect(d.shouldDeliver(window('A')), isFalse);
    });

    test('A, B, A — the interleaved repeat is still dropped', () {
      // The case a single last-id slot got wrong. `_ingestSingleEvent` delivers
      // synchronously while the native callback arrives asynchronously, so a
      // window closed by the background tick can land between the two
      // deliveries of the same window.
      final d = HsiDeliveryDeduper();
      expect(d.shouldDeliver(window('A')), isTrue, reason: 'A first time');
      expect(d.shouldDeliver(window('B')), isTrue, reason: 'B is new');
      expect(d.shouldDeliver(window('A')), isFalse, reason: 'A is a repeat');
    });

    test('distinct windows all pass', () {
      final d = HsiDeliveryDeduper();
      for (final id in ['A', 'B', 'C', 'D']) {
        expect(d.shouldDeliver(window(id)), isTrue);
      }
      expect(d.length, 4);
    });
  });

  group('unidentifiable payloads are delivered, never dropped', () {
    test('a payload with no meta.ids.hsi_id always passes', () {
      // It cannot be identified, and losing a window is worse than repeating
      // one — matching the runtime's own behaviour on non-conformant rows.
      final d = HsiDeliveryDeduper();
      expect(d.shouldDeliver(window(null)), isTrue);
      expect(d.shouldDeliver(window(null)), isTrue);
      expect(d.length, 0, reason: 'nothing identifiable to remember');
    });

    test('malformed and non-object payloads pass', () {
      final d = HsiDeliveryDeduper();
      for (final raw in ['not json', '[1,2,3]', '{"meta":{}}', '""']) {
        expect(d.shouldDeliver(raw), isTrue, reason: raw);
      }
    });

    test('an empty hsi_id is treated as absent', () {
      final d = HsiDeliveryDeduper();
      expect(d.shouldDeliver(window('')), isTrue);
      expect(d.shouldDeliver(window('')), isTrue);
    });
  });

  group('bounded memory', () {
    test('never grows past capacity', () {
      final d = HsiDeliveryDeduper(capacity: 10);
      for (var i = 0; i < 1000; i++) {
        expect(d.shouldDeliver(window('id_$i')), isTrue);
      }
      expect(d.length, 10);
    });

    test('evicts oldest first, so recent repeats are still caught', () {
      final d = HsiDeliveryDeduper(capacity: 3);
      for (final id in ['A', 'B', 'C']) {
        d.shouldDeliver(window(id));
      }
      d.shouldDeliver(window('D')); // evicts A

      expect(d.shouldDeliver(window('A')), isTrue, reason: 'A aged out');
      expect(d.shouldDeliver(window('D')), isFalse, reason: 'D still recent');
    });
  });

  group('reset', () {
    test('a new session can re-deliver a previously seen id', () {
      // Sessions are independent; a stale id must not suppress the next
      // session's first window.
      final d = HsiDeliveryDeduper();
      expect(d.shouldDeliver(window('A')), isTrue);
      expect(d.shouldDeliver(window('A')), isFalse);

      d.reset();
      expect(d.length, 0);
      expect(d.shouldDeliver(window('A')), isTrue);
    });
  });

  group('extractHsiId', () {
    test('reads meta.ids.hsi_id', () {
      expect(HsiDeliveryDeduper.extractHsiId(window('hsi_abc')), 'hsi_abc');
    });

    test('returns null for anything else', () {
      for (final raw in [
        window(null),
        'not json',
        '[1,2,3]',
        '{"meta":{"ids":{}}}',
        '{"meta":{"ids":{"hsi_id":42}}}',
      ]) {
        expect(HsiDeliveryDeduper.extractHsiId(raw), isNull, reason: raw);
      }
    });
  });
}
