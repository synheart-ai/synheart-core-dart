import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/models/hsi_state.dart';

void main() {
  group('HSIState', () {
    test('parses nested HSI JSON', () {
      final json = jsonEncode({
        'subject_id': 'usr_123',
        'timestamp_ms': 1700000000000,
        'hsi': {
          'focus': {'value': 0.8, 'confidence': 0.9},
          'arousal': {'value': 0.5, 'confidence': 0.7},
          'capacity': {'value': 0.6, 'confidence': 0.8},
          'sleep': {'value': 0.3, 'confidence': 0.95},
        },
      });

      final state = HSIState.fromJson(json);
      expect(state.subjectId, 'usr_123');
      expect(state.timestampMs, 1700000000000);
      expect(state.hsi.focus!.value, 0.8);
      expect(state.hsi.focus!.confidence, 0.9);
      expect(state.hsi.arousal!.value, 0.5);
      expect(state.hsi.capacity!.value, 0.6);
      expect(state.hsi.sleep!.value, 0.3);
      expect(state.rawJson, json);
    });

    test('parses flat axes JSON', () {
      final json = jsonEncode({
        'focus': {'value': 0.7, 'confidence': 0.8},
        'arousal': {'value': 0.4, 'confidence': 0.6},
      });

      final state = HSIState.fromJson(json, subjectId: 'usr_ext');
      expect(state.subjectId, 'usr_ext');
      expect(state.hsi.focus!.value, 0.7);
      expect(state.hsi.arousal!.value, 0.4);
      expect(state.hsi.capacity, isNull);
      expect(state.hsi.sleep, isNull);
    });

    test('handles malformed JSON gracefully', () {
      final state = HSIState.fromJson('not-json', subjectId: 'usr_x');
      expect(state.subjectId, 'usr_x');
      expect(state.rawJson, 'not-json');
      expect(state.hsi.focus, isNull);
    });

    test('uses observed_at_ms as fallback timestamp', () {
      final json = jsonEncode({
        'observed_at_ms': 1234567890000,
        'focus': {'value': 0.5, 'confidence': 0.5},
      });

      final state = HSIState.fromJson(json);
      expect(state.timestampMs, 1234567890000);
    });
  });

  group('HSIAxisValue', () {
    test('fromJson handles missing fields', () {
      final axis = HSIAxisValue.fromJson({});
      expect(axis.value, 0.0);
      expect(axis.confidence, 0.0);
    });

    test('toJson round trips', () {
      final axis = HSIAxisValue(value: 0.75, confidence: 0.85);
      final json = axis.toJson();
      expect(json['value'], 0.75);
      expect(json['confidence'], 0.85);
    });
  });
}
