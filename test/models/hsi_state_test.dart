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

  group('Modalities + Tiers (signal-modality contract)', () {
    test('derives all three modalities from a wearable + phone session', () {
      final json = jsonEncode({
        'meta': {
          'provenance': {
            'sources': {
              'watch-1': {
                'type': 'sensor',
                'signals': ['hrv', 'rr'],
                'source_tier': 2,
              },
              'phone-os': {
                'type': 'app',
                'signals': ['touch', 'scroll', 'app_switch'],
              },
            },
          },
          'synheart': {
            'tiers': {'digital': 1},
          },
        },
      });
      final state = HSIState.fromJson(json);
      expect(state.modalities.physiological, isTrue);
      expect(state.modalities.digital, isTrue);
      expect(state.modalities.kinematic, isFalse);
      expect(state.tiers.physiological, 2);
      expect(state.tiers.digital, 1);
      expect(state.tiers.kinematic, isNull);
    });

    test(
      'digital-only producer (no biosensor) reports physiological=false',
      () {
        final json = jsonEncode({
          'meta': {
            'provenance': {
              'sources': {
                'desktop-os': {
                  'type': 'app',
                  'signals': ['touch', 'typing', 'app_switch'],
                },
              },
            },
            'synheart': {
              'tiers': {'digital': 1},
            },
          },
        });
        final state = HSIState.fromJson(json);
        expect(state.modalities.physiological, isFalse);
        expect(state.modalities.digital, isTrue);
        expect(state.tiers.physiological, isNull);
        expect(state.tiers.digital, 1);
      },
    );

    test('unknown signals are silently ignored (forward-compat)', () {
      final json = jsonEncode({
        'meta': {
          'provenance': {
            'sources': {
              'future': {
                'type': 'sensor',
                'signals': ['eeg', 'audio'],
              },
            },
          },
        },
      });
      final state = HSIState.fromJson(json);
      expect(state.modalities.isEmpty, isTrue);
    });

    test('physio tier takes worst across multiple physio sources', () {
      final json = jsonEncode({
        'meta': {
          'provenance': {
            'sources': {
              'watch-rr': {
                'type': 'sensor',
                'signals': ['rr'],
                'source_tier': 1,
              },
              'watch-frame': {
                'type': 'sensor',
                'signals': ['hrv'],
                'source_tier': 3,
              },
            },
          },
        },
      });
      final state = HSIState.fromJson(json);
      expect(state.tiers.physiological, 3);
    });

    test('empty payload yields empty modalities and tiers', () {
      final state = HSIState.fromJson('{}');
      expect(state.modalities.isEmpty, isTrue);
      expect(state.tiers.isEmpty, isTrue);
    });

    test('Modalities can be constructed by callers', () {
      const m = Modalities(physiological: true, digital: true);
      expect(m.physiological, isTrue);
      expect(m.kinematic, isFalse);
      expect(m.digital, isTrue);
    });
  });
}
