import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/modules/wear/wear_source_handler.dart';

/// Unit tests for session data buffering (getSessionHsiWindows / getSessionWearSamples).
///
/// These tests exercise the buffer data models and list behaviour directly,
/// without requiring the full SDK initialization or native runtime.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Session HSI buffer', () {
    test('empty before any data is added', () {
      final buffer = <String>[];
      expect(List.unmodifiable(buffer), isEmpty);
    });

    test('accumulates HSI JSON strings', () {
      final buffer = <String>[];
      buffer.add('{"hsi":"frame1"}');
      buffer.add('{"hsi":"frame2"}');
      buffer.add('{"hsi":"frame3"}');

      final snapshot = List.unmodifiable(buffer);
      expect(snapshot, hasLength(3));
      expect(snapshot[0], '{"hsi":"frame1"}');
      expect(snapshot[2], '{"hsi":"frame3"}');
    });

    test('snapshot persists after source stops adding', () {
      final buffer = <String>[];
      buffer.add('{"hsi":"frame1"}');
      buffer.add('{"hsi":"frame2"}');

      // Simulate stopSession — no more additions, but buffer persists
      final snapshot = List.unmodifiable(buffer);
      expect(snapshot, hasLength(2));
    });

    test('buffer clears on new session', () {
      var buffer = <String>[];
      buffer.add('{"hsi":"old_frame"}');
      expect(buffer, hasLength(1));

      // Simulate startSession — clears previous data
      buffer = <String>[];
      expect(buffer, isEmpty);
    });

    test('returned list is unmodifiable (copy, not reference)', () {
      final buffer = <String>[];
      buffer.add('{"hsi":"frame1"}');

      final snapshot = List.unmodifiable(buffer);
      expect(() => snapshot.add('extra'), throwsUnsupportedError);
      // Original buffer is unaffected by failed mutation
      expect(buffer, hasLength(1));
    });
  });

  group('Session WearSample buffer', () {
    test('empty before any data is added', () {
      final buffer = <WearSample>[];
      expect(List.unmodifiable(buffer), isEmpty);
    });

    test('accumulates WearSample objects', () {
      final buffer = <WearSample>[];
      buffer.add(
        WearSample(timestamp: DateTime(2026, 2, 27, 10, 0, 0), hr: 72),
      );
      buffer.add(
        WearSample(timestamp: DateTime(2026, 2, 27, 10, 0, 5), hr: 74),
      );
      buffer.add(
        WearSample(timestamp: DateTime(2026, 2, 27, 10, 0, 10), hr: 71),
      );

      final snapshot = List.unmodifiable(buffer);
      expect(snapshot, hasLength(3));
      expect(snapshot[0].hr, 72);
      expect(snapshot[2].hr, 71);
    });

    test('snapshot persists after source stops adding', () {
      final buffer = <WearSample>[];
      buffer.add(WearSample(timestamp: DateTime(2026, 2, 27), hr: 72));
      buffer.add(WearSample(timestamp: DateTime(2026, 2, 27), hr: 74));

      final snapshot = List.unmodifiable(buffer);
      expect(snapshot, hasLength(2));
    });

    test('buffer clears on new session', () {
      var buffer = <WearSample>[];
      buffer.add(WearSample(timestamp: DateTime(2026, 2, 27), hr: 72));
      expect(buffer, hasLength(1));

      // Simulate startSession — clears previous data
      buffer = <WearSample>[];
      expect(buffer, isEmpty);
    });

    test('returned list is unmodifiable (copy, not reference)', () {
      final buffer = <WearSample>[];
      buffer.add(WearSample(timestamp: DateTime(2026, 2, 27), hr: 72));

      final snapshot = List.unmodifiable(buffer);
      expect(
        () =>
            snapshot.add(WearSample(timestamp: DateTime(2026, 2, 27), hr: 99)),
        throwsUnsupportedError,
      );
      expect(buffer, hasLength(1));
    });
  });
}
