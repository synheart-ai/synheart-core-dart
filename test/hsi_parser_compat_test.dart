import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

/// Schema-drift regression net for `HSIPayload.fromJson`.
///
/// Iterates every JSON file under `test/fixtures/hsi/` (vendored from
/// https://github.com/synheart-ai/hsi) and asserts the parser accepts
/// it. When a new HSI release ships, vendor the new fixtures into the
/// matching `vN_M/` directory and add the version string to
/// `kKnownHsiVersions` — this test will catch any field that the
/// hand-rolled parser hasn't been taught to handle.
///
/// Failure shape is intentionally informative: the offending file path
/// is in the test name so a CI failure report points at the exact
/// fixture that broke.
void main() {
  group('HSIPayload.fromJson — canonical fixtures', () {
    // Resolve fixtures at group-load. `expect` calls inside a group
    // body but outside a `test` throw `OutsideTestException`, so a
    // missing-fixtures or empty-directory failure is folded into a
    // dedicated `test('fixtures present')` below.
    final root = Directory('test/fixtures/hsi');
    final fixtures = root.existsSync()
        ? (root
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.json'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];

    test('fixtures present', () {
      expect(
        root.existsSync(),
        isTrue,
        reason:
            'Fixture directory not found at ${root.path}. '
            'Run `flutter test` from the package root.',
      );
      expect(
        fixtures,
        isNotEmpty,
        reason: 'No HSI fixtures found under ${root.path}',
      );
    });

    for (final f in fixtures) {
      final relPath = f.path.replaceFirst('test/fixtures/hsi/', '');
      test('parses $relPath', () {
        final raw = f.readAsStringSync();
        final json = jsonDecode(raw);
        expect(
          json,
          isA<Map<String, dynamic>>(),
          reason: 'Top-level value in $relPath must be a JSON object.',
        );
        // Round-trip — fromJson must accept, and toJson must round-trip
        // to a Map (we don't require lossless equality because the
        // parser intentionally normalises across HSI versions, but the
        // re-serialised shape must be parseable a second time).
        final payload = HSIPayload.fromJson(json as Map<String, dynamic>);
        expect(
          payload.hsiVersion,
          isNotEmpty,
          reason: 'hsi_version must not be empty after parse',
        );
        final encoded = jsonEncode(payload.toJson());
        final reparsed = HSIPayload.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>,
        );
        expect(
          reparsed.hsiVersion,
          payload.hsiVersion,
          reason: 'Round-trip lost hsiVersion for $relPath',
        );
      });
    }
  });

  group('HSIPayload.fromJson — version canary', () {
    test('accepts an unknown version without throwing', () {
      // The forward-compat contract: parser must not fault on a
      // version string it doesn't recognise. The only externally-
      // observable signal is the warn-once log, which we don't
      // intercept here — exercising this path documents that the
      // parser is lenient by design.
      final futureVersion =
          jsonDecode('''
        {
          "hsi_version": "1.99",
          "observed_at_utc": "2026-01-01T00:00:00Z",
          "computed_at_utc": "2026-01-01T00:00:01Z",
          "producer": {"name": "test", "version": "0.0.0"},
          "windows": {"win_x": {"start_utc": "2026-01-01T00:00:00Z", "end_utc": "2026-01-01T00:01:00Z"}},
          "axes": {"physiological": []}
        }
      ''')
              as Map<String, dynamic>;
      expect(() => HSIPayload.fromJson(futureVersion), returnsNormally);
    });

    test('kKnownHsiVersions is non-empty', () {
      // Sanity — if someone wipes the set, every version becomes a
      // "drift" warning, defeating the canary's purpose.
      expect(kKnownHsiVersions, isNotEmpty);
      // Pin the current floor so a regression that drops 1.2 support
      // is caught immediately.
      expect(kKnownHsiVersions, contains('1.2'));
    });
  });
}
