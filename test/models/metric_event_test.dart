import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/models/metric_event.dart';

void main() {
  group('MetricEvent', () {
    test('toJson serializes correctly', () {
      final event = MetricEvent(
        name: 'reaction_time_ms',
        timestampMs: 1700000000000,
        value: 250.5,
        tags: {'task': 'flanker', 'trial': '1'},
      );

      final json = event.toJson();
      expect(json['name'], 'reaction_time_ms');
      expect(json['timestamp_ms'], 1700000000000);
      expect(json['value'], 250.5);
      expect(json['tags'], {'task': 'flanker', 'trial': '1'});
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'name': 'accuracy',
        'timestamp_ms': 1700000000000,
        'value': 0.95,
        'tags': {'condition': 'congruent'},
      };

      final event = MetricEvent.fromJson(json);
      expect(event.name, 'accuracy');
      expect(event.value, 0.95);
      expect(event.tags?['condition'], 'congruent');
    });

    test('valueEncoded handles different types', () {
      expect(
        MetricEvent(name: 'n', timestampMs: 0, value: 42).valueEncoded,
        '42',
      );
      expect(
        MetricEvent(name: 'n', timestampMs: 0, value: 'hello').valueEncoded,
        '"hello"',
      );
      expect(
        MetricEvent(name: 'n', timestampMs: 0, value: true).valueEncoded,
        'true',
      );
    });

    test('tagsEncoded returns null when no tags', () {
      final event = MetricEvent(name: 'n', timestampMs: 0, value: 1);
      expect(event.tagsEncoded, isNull);
    });

    test('tagsEncoded returns JSON string when tags present', () {
      final event = MetricEvent(
        name: 'n',
        timestampMs: 0,
        value: 1,
        tags: {'a': 'b'},
      );
      expect(jsonDecode(event.tagsEncoded!), {'a': 'b'});
    });
  });
}
