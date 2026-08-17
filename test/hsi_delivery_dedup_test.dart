import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

/// A completed HSI window can reach Dart through two producers at once.
///
/// The runtime's `ingest_batch_json` BOTH broadcasts on `state_tx` — which
/// drives `setHsiCallback` — and returns the same payload to the caller. So on
/// any platform where the native callback fires (Android, and iOS as of runtime
/// 0.19.2), a window completed by `pushWearHr` / `pushVendorHrv` arrives twice.
///
/// Without suppression that double-counts `onHSIUpdate`, `onStateUpdate`, the
/// session buffer, and everything downstream. These tests pin the identity rule
/// the suppression relies on: `meta.ids.hsi_id`, per RFC-IDENTITY-0001 — the
/// same key the runtime's own ingest connector dedupes on.
void main() {
  String window({String? hsiId, double stress = 0.4}) => jsonEncode({
    'hsi_version': '1.3',
    'timestamp_ms': 1750000000000,
    'subject_id': 'sub_1',
    'axes': {
      'affective': [
        {'name': 'stress', 'score': stress, 'confidence': 0.8},
      ],
    },
    if (hsiId != null)
      'meta': {
        'ids': {'hsi_id': hsiId},
      },
  });

  group('HSI window identity', () {
    test('two deliveries of one window carry the same hsi_id', () {
      // The duplicate is the SAME window arriving twice, so the id matches
      // even though the two producers serialise independently.
      final viaCallback = window(hsiId: 'hsi_abc123');
      final viaIngestReturn = window(hsiId: 'hsi_abc123', stress: 0.4);

      expect(_hsiId(viaCallback), _hsiId(viaIngestReturn));
      expect(_hsiId(viaCallback), 'hsi_abc123');
    });

    test('distinct windows carry distinct ids', () {
      expect(
        _hsiId(window(hsiId: 'hsi_1')),
        isNot(_hsiId(window(hsiId: 'hsi_2'))),
      );
    });

    test('a payload without meta.ids.hsi_id yields no id', () {
      // Deliberately delivered rather than dropped: losing a window is worse
      // than repeating one, and this matches the runtime's own
      // "dedup disabled for this row" behaviour.
      expect(_hsiId(window()), isNull);
      expect(_hsiId('not json'), isNull);
      expect(_hsiId(jsonEncode({'meta': {}})), isNull);
      expect(
        _hsiId(
          jsonEncode({
            'meta': {'ids': {}},
          }),
        ),
        isNull,
      );
    });
  });

  group('HSIState parses either producer identically', () {
    test('the duplicate produces an equivalent typed state', () {
      // Both producers must be interchangeable — otherwise suppressing one
      // would change what subscribers see.
      final a = HSIState.fromJson(window(hsiId: 'hsi_x'));
      final b = HSIState.fromJson(window(hsiId: 'hsi_x'));

      expect(a.hasParseError, isFalse);
      expect(b.hasParseError, isFalse);
      expect(a.hsi.stress?.value, b.hsi.stress?.value);
      expect(a.timestampMs, b.timestampMs);
    });
  });
}

/// Mirrors the extraction the SDK performs before suppressing a duplicate.
String? _hsiId(String hsiJson) {
  try {
    final root = jsonDecode(hsiJson);
    if (root is! Map) return null;
    final meta = root['meta'];
    if (meta is! Map) return null;
    final ids = meta['ids'];
    if (ids is! Map) return null;
    final id = ids['hsi_id'];
    return (id is String && id.isNotEmpty) ? id : null;
  } catch (_) {
    return null;
  }
}
