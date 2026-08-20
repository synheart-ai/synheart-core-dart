import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

/// `HSIState.fromJson` swallowed every parse failure and returned empty axes,
/// which is byte-identical to a legitimate window whose axes the engine has not
/// populated yet. A developer had no way to distinguish "no data" from "the
/// payload was malformed". These tests pin the distinction.
void main() {
  group('HSIState parse failures', () {
    test('malformed JSON is reported, not silently emptied', () {
      final state = HSIState.fromJson('not json at all', subjectId: 'sub_1');

      expect(state.hasParseError, isTrue);
      expect(state.parseError, isNotNull);
      expect(state.hsi.stress, isNull);
      // The offending payload stays available for diagnosis.
      expect(state.rawJson, 'not json at all');
      // The requested subject is preserved so callers can still attribute it.
      expect(state.subjectId, 'sub_1');
    });

    test('a JSON array (not an object) is a parse error', () {
      final state = HSIState.fromJson('[1, 2, 3]');
      expect(state.hasParseError, isTrue);
    });

    test('a well-formed window with no axes is NOT a parse error', () {
      // The case that was previously indistinguishable from malformed input.
      final json = jsonEncode({
        'hsi_version': '1.3',
        'timestamp_ms': 1750000000000,
        'subject_id': 'sub_2',
        'axes': <String, dynamic>{},
      });

      final state = HSIState.fromJson(json);

      expect(state.hasParseError, isFalse);
      expect(state.parseError, isNull);
      expect(state.hsi.stress, isNull, reason: 'no axes present yet');
      expect(state.subjectId, 'sub_2');
      expect(state.timestampMs, 1750000000000);
    });

    test('a populated 1.3 window parses without error', () {
      final json = jsonEncode({
        'hsi_version': '1.3',
        'timestamp_ms': 1750000000001,
        'subject_id': 'sub_3',
        'axes': {
          // Wire shape uses `score`; the Dart model exposes it as `value`.
          'affective': [
            {'name': 'stress', 'score': 0.42, 'confidence': 0.8},
          ],
        },
      });

      final state = HSIState.fromJson(json);

      expect(state.hasParseError, isFalse);
      expect(state.hsi.stress?.value, closeTo(0.42, 1e-9));
      expect(state.hsi.stress?.confidence, closeTo(0.8, 1e-9));
    });

    test('an empty string is a parse error rather than an empty window', () {
      expect(HSIState.fromJson('').hasParseError, isTrue);
    });
  });
}
