/// End-to-end: real synheart-flux 1.3 emit → Flutter HSIState parse.
///
/// The fixture at `test/fixtures/hsi/v1_3/flux_emit.json` was produced by
/// `cargo run -p synheart-flux --example build_snapshot_v13` in the
/// `synheart-engine-runtime` workspace and validated against the canonical
/// HSI 1.3 schema (BASIC + STRICT) before being vendored here. This test
/// closes the producer→Flutter-SDK loop: same payload that flows to the
/// runtime must parse cleanly through the Dart `HSIState` model.
///
/// The HSI fixtures dir is also iterated by `hsi_parser_compat_test.dart`,
/// which exercises the `HSIPayload` (HSI11*) shape. This file complements
/// that with axis-level assertions on `HSIState`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/models/hsi_state.dart';

void main() {
  group('HSI 1.3 end-to-end (flux emit → HSIState)', () {
    final fixture = File('test/fixtures/hsi/v1_3/flux_emit.json');
    final raw = fixture.readAsStringSync();

    test('fixture is valid 1.3 payload', () {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['hsi_version'], '1.3');
      // Sanity: the canonical 5-axis layout is present.
      final axes = json['axes'] as Map<String, dynamic>;
      expect(axes.containsKey('cognitive'), isTrue);
      expect(axes.containsKey('affective'), isTrue);
      expect(axes.containsKey('physiological'), isTrue);
      // Legacy 1.2 domains MUST NOT appear in a 1.3 emit.
      expect(axes.containsKey('engagement'), isFalse);
      expect(axes.containsKey('emotion'), isFalse);
      expect(axes.containsKey('behavior'), isFalse);
    });

    test('HSIState extracts focus/capacity from axes.cognitive[]', () {
      final state = HSIState.fromJson(raw);
      expect(state.hsi.focus, isNotNull);
      expect(state.hsi.focus!.value, closeTo(0.7, 1e-6));
      expect(state.hsi.focus!.confidence, closeTo(0.5292, 1e-6));

      expect(state.hsi.capacity, isNotNull);
      expect(state.hsi.capacity!.value, closeTo(0.5266666666666666, 1e-9));
    });

    test('HSIState extracts arousal from axes.affective[]', () {
      final state = HSIState.fromJson(raw);
      expect(state.hsi.arousal, isNotNull);
      expect(state.hsi.arousal!.value, closeTo(0.7333333333333333, 1e-9));
    });

    test('axes.physiological[] carries sleep_autonomic (live proxy); '
        'state.hsi.sleep stays null until a batch nightly score attaches', () {
      // PHYSIO-002 supersession: the live autonomic head emits as
      // `sleep_autonomic`. The canonical `sleep_score` slot is reserved for
      // the nightly batch result, attached separately. The SDK's
      // state.hsi.sleep accessor reflects the canonical slot, not the live
      // proxy — correctly None when the fixture has no batch attachment.
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final physio = (json['axes'] as Map)['physiological'] as List;
      final autonomic =
          physio.firstWhere((r) => (r as Map)['name'] == 'sleep_autonomic')
              as Map;
      expect(
        (autonomic['score'] as num).toDouble(),
        closeTo(0.47999998927116394, 1e-6),
      );
      final state = HSIState.fromJson(raw);
      expect(
        state.hsi.sleep,
        isNull,
        reason: 'no batch sleep_score in fixture → SDK accessor is null',
      );
    });

    test('hsi_id is RFC 4122 UUIDv5 (deterministic, content-addressed)', () {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final id = ((json['meta'] as Map)['ids'] as Map)['hsi_id'] as String;
      // 8-4-4-4-12 lowercase hex
      final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      );
      expect(uuidPattern.hasMatch(id), isTrue, reason: 'hsi_id="$id"');
      // UUIDv5: deterministic, derived from synheart-id's canonical input
      // string under the Synheart HSI namespace. Version nibble in the
      // third group is '5'.
      expect(id.split('-')[2][0], '5', reason: 'expected UUIDv5, got "$id"');
    });

    test(
      'multimodal readings carry modalities_used; single-modality do not',
      () {
        // Schema-level invariant from RFC-HSI-0010 §5.1. The Flutter SDK
        // doesn't surface this through HSIState, but the producer guarantee
        // matters for downstream consumers that read raw JSON.
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final axes = json['axes'] as Map<String, dynamic>;

        for (final r in axes['cognitive'] as List) {
          expect(
            (r as Map)['modalities_used'],
            isA<List>(),
            reason: 'cognitive[${r['name']}] needs modalities_used',
          );
        }
        for (final r in axes['affective'] as List) {
          expect(
            (r as Map)['modalities_used'],
            isA<List>(),
            reason: 'affective[${r['name']}] needs modalities_used',
          );
        }
        for (final r in axes['physiological'] as List) {
          expect(
            (r as Map).containsKey('modalities_used'),
            isFalse,
            reason:
                'physiological[${r['name']}] MUST NOT carry modalities_used',
          );
        }
      },
    );
  });
}
