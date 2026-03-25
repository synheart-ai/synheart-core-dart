import 'package:test/test.dart';
import 'package:synheart_core/synheart_core.dart';

/// Golden vector tests for wearable_event_id computation.
/// These vectors MUST match the Rust, Swift, and Kotlin implementations.
/// See synheart-core/test/vectors/wearable_event_id_vectors.json
void main() {
  group('wearable_event_id golden vectors', () {
    test('Form A — with provider_record_id', () {
      final id = CanonicalWearableEvent.computeWearableEventId(
        eventType: 'sleep.summary.recorded',
        subjectId: 'sub_818f10fe7549448522a7571c8a737602ab0662398fc579d7',
        provider: 'whoop',
        observedAt: '2026-03-22T06:30:00Z',
        effectiveStart: '2026-03-21T23:00:00Z',
        effectiveEnd: '2026-03-22T06:15:00Z',
        providerRecordId: 'wh_sleep_20260322',
      );
      expect(id, equals('we_9a1fd6e23490aadde3ee534945fe81acf0ab5204c4e54481'));
    });

    test('Form B — without provider_record_id', () {
      final id = CanonicalWearableEvent.computeWearableEventId(
        eventType: 'sleep.summary.recorded',
        subjectId: 'sub_818f10fe7549448522a7571c8a737602ab0662398fc579d7',
        provider: 'whoop',
        observedAt: '2026-03-22T06:30:00Z',
        effectiveStart: '2026-03-21T23:00:00Z',
        effectiveEnd: '2026-03-22T06:15:00Z',
      );
      expect(id, equals('we_0fb205b3aa588ac0d9a5010cdad6e554ef864587d35cd182'));
    });

    test('Form B — no effective window (absent → ~)', () {
      final id = CanonicalWearableEvent.computeWearableEventId(
        eventType: 'hrv.recorded',
        subjectId: 'sub_818f10fe7549448522a7571c8a737602ab0662398fc579d7',
        provider: 'apple_health',
        observedAt: '2026-03-22T07:00:00Z',
      );
      expect(id, equals('we_2bb67a70434e4e230a371ba0e73cfc64477ff679fa659394'));
    });

    test('Form A and Form B produce different IDs', () {
      final idA = CanonicalWearableEvent.computeWearableEventId(
        eventType: 'sleep.summary.recorded',
        subjectId: 'sub_818f10fe7549448522a7571c8a737602ab0662398fc579d7',
        provider: 'whoop',
        observedAt: '2026-03-22T06:30:00Z',
        effectiveStart: '2026-03-21T23:00:00Z',
        effectiveEnd: '2026-03-22T06:15:00Z',
        providerRecordId: 'wh_sleep_20260322',
      );
      final idB = CanonicalWearableEvent.computeWearableEventId(
        eventType: 'sleep.summary.recorded',
        subjectId: 'sub_818f10fe7549448522a7571c8a737602ab0662398fc579d7',
        provider: 'whoop',
        observedAt: '2026-03-22T06:30:00Z',
        effectiveStart: '2026-03-21T23:00:00Z',
        effectiveEnd: '2026-03-22T06:15:00Z',
      );
      expect(idA, isNot(equals(idB)));
    });

    test('All IDs have we_ prefix and correct length', () {
      final id = CanonicalWearableEvent.computeWearableEventId(
        eventType: 'hrv.recorded',
        subjectId: 'sub_test',
        provider: 'garmin',
        observedAt: '2026-03-22T08:00:00Z',
      );
      expect(id.startsWith('we_'), isTrue);
      expect(id.length, equals(3 + 48)); // we_ + 48 hex chars
    });
  });
}
