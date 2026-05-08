import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  group('BreathingComplianceResult.fromJson', () {
    test('parses Compliant verdict', () {
      final json =
          jsonDecode('''
        {
          "verdict": "Compliant",
          "metrics": {
            "peak_hz": 0.0997,
            "peak_bpm": 5.98,
            "coherence": 0.71,
            "rsa_bpm": 14.2,
            "relative_power": 0.68,
            "criteria_met": 4,
            "confidence": 0.91
          }
        }
      ''')
              as Map<String, dynamic>;

      final result = BreathingComplianceResult.fromJson(json);

      expect(result, isA<BreathingCompliant>());
      expect(result.isCompliant, isTrue);
      expect(result.metrics, isNotNull);
      expect(result.metrics!.peakBpm, closeTo(5.98, 1e-6));
      expect(result.metrics!.criteriaMet, 4);
      expect(result.metrics!.confidence, closeTo(0.91, 1e-6));
    });

    test('parses NotCompliant + WrongFrequency', () {
      final json =
          jsonDecode('''
        {
          "verdict": "NotCompliant",
          "metrics": {
            "peak_hz": 0.15,
            "peak_bpm": 9.0,
            "coherence": 0.62,
            "rsa_bpm": 8.0,
            "relative_power": 0.55,
            "criteria_met": 3,
            "confidence": 0.74
          },
          "reason": {
            "type": "WrongFrequency",
            "detected_bpm": 9.0,
            "target_bpm": 6.0
          }
        }
      ''')
              as Map<String, dynamic>;

      final result = BreathingComplianceResult.fromJson(json);

      expect(result, isA<BreathingNotCompliant>());
      expect(result.isCompliant, isFalse);
      final nc = result as BreathingNotCompliant;
      expect(nc.reason, isA<WrongFrequency>());
      final wf = nc.reason as WrongFrequency;
      expect(wf.detectedBpm, 9.0);
      expect(wf.targetBpm, 6.0);
    });

    test('BreathingGuidanceCopy.copyFor produces friendly text', () {
      final wf = const WrongFrequency(detectedBpm: 9.0, targetBpm: 6.0);
      expect(BreathingGuidanceCopy.copyFor(wf), contains('Slow down'));
      final wf2 = const WrongFrequency(detectedBpm: 4.0, targetBpm: 6.0);
      expect(BreathingGuidanceCopy.copyFor(wf2), contains('Speed up'));
      expect(
        BreathingGuidanceCopy.copyFor(const ShallowBreathing(rsaBpm: 3.0)),
        contains('deeper'),
      );
      expect(
        BreathingGuidanceCopy.copyFor(const IrregularPattern(coherence: 0.4)),
        contains('steady'),
      );
      expect(
        BreathingGuidanceCopy.copyFor(const NoBreathingSignature()),
        contains('pacer'),
      );
    });

    test('parses Insufficient + VendorOnlyTier', () {
      final json =
          jsonDecode('''
        {
          "verdict": "Insufficient",
          "reason": {
            "type": "VendorOnlyTier",
            "device": "Apple Watch"
          }
        }
      ''')
              as Map<String, dynamic>;

      final result = BreathingComplianceResult.fromJson(json);

      expect(result, isA<BreathingInsufficient>());
      expect(result.metrics, isNull);
      expect(result.isCompliant, isFalse);
      final ins = result as BreathingInsufficient;
      expect(ins.reason, isA<VendorOnlyTier>());
      expect((ins.reason as VendorOnlyTier).device, 'Apple Watch');
    });

    test('parses Insufficient + WindowTooShort', () {
      final json =
          jsonDecode('''
        {
          "verdict": "Insufficient",
          "reason": {
            "type": "WindowTooShort",
            "have_secs": 12,
            "need_secs": 30
          }
        }
      ''')
              as Map<String, dynamic>;

      final result = BreathingComplianceResult.fromJson(json);

      final ins = result as BreathingInsufficient;
      final wts = ins.reason as WindowTooShort;
      expect(wts.haveSecs, 12);
      expect(wts.needSecs, 30);
    });

    test('parses Insufficient + NotEnoughBeats', () {
      final json =
          jsonDecode('''
        {
          "verdict": "Insufficient",
          "reason": { "type": "NotEnoughBeats", "have": 18, "need": 50 }
        }
      ''')
              as Map<String, dynamic>;

      final ins =
          BreathingComplianceResult.fromJson(json) as BreathingInsufficient;
      final neb = ins.reason as NotEnoughBeats;
      expect(neb.have, 18);
      expect(neb.need, 50);
    });

    test('unknown verdict defaults to Insufficient', () {
      final json = <String, dynamic>{
        'verdict': 'WhoKnows',
        'reason': {'type': 'NotEnoughBeats', 'have': 0, 'need': 50},
      };
      final result = BreathingComplianceResult.fromJson(json);
      expect(result, isA<BreathingInsufficient>());
    });

    test('NotCompliant + ShallowBreathing', () {
      final json =
          jsonDecode('''
        {
          "verdict": "NotCompliant",
          "metrics": {
            "peak_hz": 0.10, "peak_bpm": 6.0, "coherence": 0.7,
            "rsa_bpm": 3.5, "relative_power": 0.5, "criteria_met": 3,
            "confidence": 0.7
          },
          "reason": { "type": "ShallowBreathing", "rsa_bpm": 3.5 }
        }
      ''')
              as Map<String, dynamic>;

      final nc =
          BreathingComplianceResult.fromJson(json) as BreathingNotCompliant;
      final sb = nc.reason as ShallowBreathing;
      expect(sb.rsaBpm, closeTo(3.5, 1e-6));
    });
  });

  group('BreathingPopulation', () {
    test('enum index matches native profile values', () {
      // Must match the native enum: 0=Beginner, 1=Experienced, 2=Clinical.
      expect(BreathingPopulation.beginner.index, 0);
      expect(BreathingPopulation.experienced.index, 1);
      expect(BreathingPopulation.clinical.index, 2);
    });
  });
}
