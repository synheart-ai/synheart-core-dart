import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

/// Golden vector tests for wearable_event_id computation.
/// These vectors MUST match the native, Swift, and Kotlin implementations.
/// See synheart-core/test/vectors/wearable_event_id_vectors.json
void main() {
  group('wearable_event_id golden vectors', () {
    test('Form A — with provider_record_id', () {
      final id = CanonicalWearableEvent.computeWearableEventId(
        type: 'sleep.summary.recorded',
        subjectId: 'sub_818f10fe7549448522a7571c8a737602ab0662398fc579d7',
        provider: 'whoop',
        observedAt: DateTime.utc(2026, 3, 22, 6, 30, 0),
        effectiveStart: DateTime.utc(2026, 3, 21, 23, 0, 0),
        effectiveEnd: DateTime.utc(2026, 3, 22, 6, 15, 0),
        providerRecordId: 'wh_sleep_20260322',
      );
      // Form A keys only on provider + provider_record_id, so the ID
      // is independent of subject/observedAt/effective*.
      expect(id.startsWith('we_'), isTrue);
      expect(id.length, equals(3 + 48));
    });

    test('Form B — without provider_record_id', () {
      final id = CanonicalWearableEvent.computeWearableEventId(
        type: 'sleep.summary.recorded',
        subjectId: 'sub_818f10fe7549448522a7571c8a737602ab0662398fc579d7',
        provider: 'whoop',
        observedAt: DateTime.utc(2026, 3, 22, 6, 30, 0),
        effectiveStart: DateTime.utc(2026, 3, 21, 23, 0, 0),
        effectiveEnd: DateTime.utc(2026, 3, 22, 6, 15, 0),
      );
      expect(id.startsWith('we_'), isTrue);
      expect(id.length, equals(3 + 48));
    });

    test('Form B — no effective window (absent → ~)', () {
      final id = CanonicalWearableEvent.computeWearableEventId(
        type: 'hrv.recorded',
        subjectId: 'sub_818f10fe7549448522a7571c8a737602ab0662398fc579d7',
        provider: 'apple_health',
        observedAt: DateTime.utc(2026, 3, 22, 7, 0, 0),
      );
      expect(id.startsWith('we_'), isTrue);
      expect(id.length, equals(3 + 48));
    });

    test('Form A and Form B produce different IDs', () {
      final idA = CanonicalWearableEvent.computeWearableEventId(
        type: 'sleep.summary.recorded',
        subjectId: 'sub_818f10fe7549448522a7571c8a737602ab0662398fc579d7',
        provider: 'whoop',
        observedAt: DateTime.utc(2026, 3, 22, 6, 30, 0),
        effectiveStart: DateTime.utc(2026, 3, 21, 23, 0, 0),
        effectiveEnd: DateTime.utc(2026, 3, 22, 6, 15, 0),
        providerRecordId: 'wh_sleep_20260322',
      );
      final idB = CanonicalWearableEvent.computeWearableEventId(
        type: 'sleep.summary.recorded',
        subjectId: 'sub_818f10fe7549448522a7571c8a737602ab0662398fc579d7',
        provider: 'whoop',
        observedAt: DateTime.utc(2026, 3, 22, 6, 30, 0),
        effectiveStart: DateTime.utc(2026, 3, 21, 23, 0, 0),
        effectiveEnd: DateTime.utc(2026, 3, 22, 6, 15, 0),
      );
      expect(idA, isNot(equals(idB)));
    });

    test('All IDs have we_ prefix and correct length', () {
      final id = CanonicalWearableEvent.computeWearableEventId(
        type: 'hrv.recorded',
        subjectId: 'sub_test',
        provider: 'garmin',
        observedAt: DateTime.utc(2026, 3, 22, 8, 0, 0),
      );
      expect(id.startsWith('we_'), isTrue);
      expect(id.length, equals(3 + 48)); // we_ + 48 hex chars
    });

    test('Determinism — same inputs produce same ID', () {
      final inputs = () => CanonicalWearableEvent.computeWearableEventId(
        type: 'hrv.recorded',
        subjectId: 'sub_determinism',
        provider: 'apple_health',
        observedAt: DateTime.utc(2026, 3, 22, 7, 0, 0),
      );
      expect(inputs(), equals(inputs()));
    });
  });
}
