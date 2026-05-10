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

    test('parses HSI 1.3 canonical 5-axis payload', () {
      // RFC-HSI-0010 §4: focus/capacity → cognitive, valence/arousal →
      // affective, sleep_score → physiological. UUIDv7 hsi_id is irrelevant
      // to the parser; we just confirm axes are read from the right domains.
      final json = jsonEncode({
        'hsi_version': '1.3',
        'subject_id': 'usr_v13',
        'timestamp_ms': 1700000000000,
        'axes': {
          'physiological': [
            {
              'name': 'sleep_score',
              'score': 0.42,
              'confidence': 0.9,
              'direction': 'higher_is_more',
            },
          ],
          'cognitive': [
            {
              'name': 'focus',
              'score': 0.71,
              'confidence': 0.6,
              'direction': 'higher_is_more',
              'modalities_used': ['physiological'],
            },
            {
              'name': 'capacity',
              'score': 0.55,
              'confidence': 0.58,
              'direction': 'higher_is_more',
              'modalities_used': ['physiological'],
            },
          ],
          'affective': [
            {
              'name': 'arousal',
              'score': 0.45,
              'confidence': 0.5,
              'direction': 'bidirectional',
              'modalities_used': ['physiological'],
            },
          ],
        },
        'meta': {
          'ids': {'hsi_id': '019e0d98-9396-7663-a161-95f4727162b6'},
        },
      });

      final state = HSIState.fromJson(json);
      expect(state.subjectId, 'usr_v13');
      expect(state.hsi.focus!.value, 0.71);
      expect(state.hsi.focus!.confidence, 0.6);
      expect(state.hsi.capacity!.value, 0.55);
      expect(state.hsi.arousal!.value, 0.45);
      expect(state.hsi.sleep!.value, 0.42);
    });

    test('1.3 sleep alias is tolerated for forward-compat producers', () {
      // RFC-HSI-0008 §6.5: unknown member names within a known domain MUST
      // be tolerated. Producers that emit `sleep` instead of the canonical
      // `sleep_score` should still parse.
      final json = jsonEncode({
        'hsi_version': '1.3',
        'axes': {
          'physiological': [
            {
              'name': 'sleep',
              'score': 0.5,
              'confidence': 0.9,
              'direction': 'higher_is_more',
            },
          ],
        },
      });
      final state = HSIState.fromJson(json);
      expect(state.hsi.sleep!.value, 0.5);
    });

    test(
      '1.3 categorical / null-score readings yield null axis (not zero)',
      () {
        // RFC-HSI-0008 §6.2: consumers MUST NOT treat null as zero. An axis
        // whose only matching reading carries `score: null` surfaces as a null
        // HSIAxisValue, not value=0.
        final json = jsonEncode({
          'hsi_version': '1.3',
          'axes': {
            'cognitive': [
              {
                'name': 'focus',
                'score': null,
                'confidence': 0.4,
                'direction': 'higher_is_more',
                'modalities_used': ['physiological'],
              },
            ],
          },
        });
        final state = HSIState.fromJson(json);
        expect(state.hsi.focus, isNull);
      },
    );

    test('1.3 dispatch does not fall back to legacy hsi.<name>', () {
      // Even if a 1.3 payload also carries a legacy `hsi.focus` block (it
      // shouldn't, but defensive), the canonical axes.cognitive[] reading is
      // the source of truth.
      final json = jsonEncode({
        'hsi_version': '1.3',
        'hsi': {
          'focus': {'value': 0.99, 'confidence': 0.99},
        },
        'axes': {
          'cognitive': [
            {'name': 'focus', 'score': 0.5, 'confidence': 0.5},
          ],
        },
      });
      final state = HSIState.fromJson(json);
      expect(state.hsi.focus!.value, 0.5);
      expect(state.hsi.focus!.confidence, 0.5);
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
