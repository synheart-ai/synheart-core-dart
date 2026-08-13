import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/core/bounded_buffer.dart';
import 'package:synheart_core/synheart_core.dart';

/// Tests for the bounded session buffers behind `getSessionHsiWindows()` and
/// `getSessionWearSamples()`.
///
/// These previously asserted on a locally-constructed `List<String>`, which
/// exercised Dart's own list semantics rather than any SDK code — they passed
/// regardless of what the SDK did. They now drive [BoundedBuffer], the type
/// `Synheart` actually stores session data in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoundedBuffer', () {
    test('starts empty', () {
      final buffer = BoundedBuffer<String>(4);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, 0);
      expect(buffer.snapshot(), isEmpty);
    });

    test('accumulates in insertion order below capacity', () {
      final buffer = BoundedBuffer<String>(4)
        ..add('{"hsi":"frame1"}')
        ..add('{"hsi":"frame2"}')
        ..add('{"hsi":"frame3"}');

      expect(buffer.snapshot(), [
        '{"hsi":"frame1"}',
        '{"hsi":"frame2"}',
        '{"hsi":"frame3"}',
      ]);
      expect(buffer.isSaturated, isFalse);
    });

    test('evicts oldest first once capacity is reached', () {
      final buffer = BoundedBuffer<int>(3);
      for (var i = 1; i <= 5; i++) {
        buffer.add(i);
      }

      // 1 and 2 were evicted; newest three survive, still oldest-first.
      expect(buffer.length, 3);
      expect(buffer.snapshot(), [3, 4, 5]);
      expect(buffer.isSaturated, isTrue);
    });

    test('stays at capacity under sustained writes', () {
      // The regression this guards: the session buffers were unbounded lists,
      // so a 24h session retained every window ever produced.
      final buffer = BoundedBuffer<int>(100);
      for (var i = 0; i < 10000; i++) {
        buffer.add(i);
      }

      expect(buffer.length, 100);
      expect(buffer.snapshot().first, 9900);
      expect(buffer.snapshot().last, 9999);
    });

    test('a zero capacity disables the buffer rather than unbounding it', () {
      final buffer = BoundedBuffer<int>(0);
      for (var i = 0; i < 50; i++) {
        buffer.add(i);
      }
      expect(buffer.isEmpty, isTrue);
    });

    test('clear empties without changing capacity', () {
      final buffer = BoundedBuffer<int>(2)
        ..add(1)
        ..add(2);
      expect(buffer.length, 2);

      buffer.clear();
      expect(buffer.isEmpty, isTrue);

      buffer
        ..add(9)
        ..add(8)
        ..add(7);
      expect(buffer.snapshot(), [8, 7]);
    });

    test('snapshot is immutable and detached from later writes', () {
      final buffer = BoundedBuffer<String>(4)..add('frame1');
      final snapshot = buffer.snapshot();

      expect(() => snapshot.add('extra'), throwsUnsupportedError);

      buffer.add('frame2');
      expect(snapshot, hasLength(1), reason: 'snapshot must not alias buffer');
      expect(buffer.length, 2);
    });

    test('holds WearSample values with the same eviction rule', () {
      final buffer = BoundedBuffer<WearSample>(2)
        ..add(WearSample(timestamp: DateTime(2026, 2, 27, 10), hr: 72))
        ..add(WearSample(timestamp: DateTime(2026, 2, 27, 10, 0, 5), hr: 74))
        ..add(WearSample(timestamp: DateTime(2026, 2, 27, 10, 0, 10), hr: 71));

      final snapshot = buffer.snapshot();
      expect(snapshot, hasLength(2));
      expect(snapshot.map((s) => s.hr), [74, 71]);
    });
  });

  group('Synheart session buffer caps', () {
    test('expose the documented capacities', () {
      expect(Synheart.maxSessionHsiWindows, 2000);
      expect(Synheart.maxSessionWearSamples, 5000);
    });

    test('session getters return empty snapshots before any session', () {
      expect(Synheart.getSessionHsiWindows(), isEmpty);
      expect(Synheart.getSessionWearSamples(), isEmpty);
    });

    test('session getters return unmodifiable snapshots', () {
      expect(
        () => Synheart.getSessionHsiWindows().add('x'),
        throwsUnsupportedError,
      );
    });
  });
}
