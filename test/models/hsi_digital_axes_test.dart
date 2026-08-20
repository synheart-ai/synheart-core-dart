import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

/// `axes.digital[]` carries the three readings the runtime derives from
/// interaction events — taps, scrolls, swipes, app switches, notifications.
/// They need no wearable, so they are the only axes that resolve on a phone
/// with no biosignal source attached.
///
/// The parser previously read `cognitive`, `affective` and `physiological` and
/// ignored `digital` entirely, so behavior reached the runtime, produced
/// readings, and was then dropped at the SDK boundary.
///
/// Shapes below mirror the runtime's own `flux_v13_emit.json` fixture.
void main() {
  String payload({required List<Map<String, Object?>> digital}) => jsonEncode({
    'hsi_version': '1.3',
    'subject_id': 'sub_test',
    'timestamp_ms': 1700000000000,
    'axes': {
      'digital': digital,
      // Deliberately empty: this is the no-wearable case, where the
      // physiology-derived axes have nothing to work from.
      'physiological': <Object?>[],
      'cognitive': <Object?>[],
      'affective': <Object?>[],
    },
  });

  test('parses all three digital readings', () {
    final state = HSIState.fromJson(
      payload(
        digital: [
          {
            'name': 'focus_quality',
            'score': 0.5166666666666667,
            'confidence': 1.0,
            'direction': 'higher_is_more',
          },
          {
            'name': 'interruption_pressure',
            'score': 0.4028760211756565,
            'confidence': 0.6,
            'direction': 'lower_is_more',
          },
          {
            'name': 'interaction_mode',
            'score': 0.5702662537012094,
            'confidence': 0.9,
            'direction': 'bidirectional',
          },
        ],
      ),
    );

    expect(state.hasParseError, isFalse);
    expect(state.hsi.focusQuality?.value, closeTo(0.5167, 0.0001));
    expect(state.hsi.focusQuality?.confidence, 1.0);
    expect(state.hsi.interruptionPressure?.value, closeTo(0.4029, 0.0001));
    expect(state.hsi.interruptionPressure?.confidence, 0.6);
    expect(state.hsi.interactionMode?.value, closeTo(0.5703, 0.0001));
    expect(state.hsi.interactionMode?.confidence, 0.9);
    expect(state.hsi.hasDigital, isTrue);
  });

  test('digital resolves even when every other domain is empty', () {
    // The whole point: a phone with no wearable still produces usable HSI.
    final state = HSIState.fromJson(
      payload(
        digital: [
          {'name': 'focus_quality', 'score': 0.42, 'confidence': 0.8},
        ],
      ),
    );

    expect(state.hsi.focus, isNull, reason: 'cognitive[] was empty');
    expect(state.hsi.arousal, isNull);
    expect(state.hsi.stress, isNull);
    expect(state.hsi.sleep, isNull);

    expect(state.hsi.hasDigital, isTrue);
    expect(state.hsi.focusQuality?.value, 0.42);
  });

  test('hasDigital is false when the domain is absent or empty', () {
    expect(HSIState.fromJson(payload(digital: [])).hsi.hasDigital, isFalse);

    final noDomain = jsonEncode({
      'hsi_version': '1.3',
      'subject_id': 'sub_test',
      'timestamp_ms': 1700000000000,
      'axes': {'cognitive': <Object?>[]},
    });
    expect(HSIState.fromJson(noDomain).hsi.hasDigital, isFalse);
  });

  test('a null score is skipped rather than read as zero', () {
    // `_findAxisReading` drops readings the engine could not compute. Treating
    // them as 0.0 would render "no focus at all" as a real measurement.
    final state = HSIState.fromJson(
      payload(
        digital: [
          {'name': 'focus_quality', 'score': null, 'confidence': 0.0},
        ],
      ),
    );
    expect(state.hsi.focusQuality, isNull);
    expect(state.hsi.hasDigital, isFalse);
  });
}
