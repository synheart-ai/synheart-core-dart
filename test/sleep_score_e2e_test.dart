// End-to-end test: loads the prebuilt `libsynheart_core_runtime.dylib`
// (built with `--features edge`) and drives the full
// RFC-SLEEP-SCORE-PIPELINE-0001 surface through the edge C ABI — the
// same ABI the Dart FFI bindings talk to in production.
//
// Skipped on non-macOS hosts / when the dylib isn't at the expected
// path; the model unit test (`sleep_score_models_test.dart`) still
// provides coverage everywhere.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/models/sleep_score.dart';

// ── Typedefs matching the native runtime's edge_ffi.rs ────────────

typedef _CreateC = Pointer<Void> Function(Pointer<Utf8>);
typedef _CreateDart = Pointer<Void> Function(Pointer<Utf8>);

typedef _DestroyC = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);

typedef _FreeStringC = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

typedef _PushRrC = Void Function(Pointer<Void>, Int64, Double);
typedef _PushRrDart = void Function(Pointer<Void>, int, double);

typedef _TickC = Pointer<Utf8> Function(Pointer<Void>, Int64);
typedef _TickDart = Pointer<Utf8> Function(Pointer<Void>, int);

typedef _ComputeC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ComputeDart = Pointer<Utf8> Function(Pointer<Utf8>);

typedef _AttachC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _AttachDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _JsonReturnHandleC = Pointer<Utf8> Function(Pointer<Void>);
typedef _JsonReturnHandleDart = Pointer<Utf8> Function(Pointer<Void>);

class _Edge {
  final DynamicLibrary _lib;
  _Edge(this._lib);

  late final create = _lib.lookupFunction<_CreateC, _CreateDart>(
    'synheart_core_edge_create',
  );
  late final destroy = _lib.lookupFunction<_DestroyC, _DestroyDart>(
    'synheart_core_edge_destroy',
  );
  late final freeString = _lib.lookupFunction<_FreeStringC, _FreeStringDart>(
    'synheart_core_edge_free_string',
  );
  late final pushRr = _lib.lookupFunction<_PushRrC, _PushRrDart>(
    'synheart_core_edge_push_rr',
  );
  late final tick = _lib.lookupFunction<_TickC, _TickDart>(
    'synheart_core_edge_tick',
  );
  late final compute = _lib.lookupFunction<_ComputeC, _ComputeDart>(
    'synheart_core_edge_sleep_score_compute_json',
  );
  late final attach = _lib.lookupFunction<_AttachC, _AttachDart>(
    'synheart_core_edge_attach_sleep_score_json',
  );
  late final lastSleepScore = _lib
      .lookupFunction<_JsonReturnHandleC, _JsonReturnHandleDart>(
        'synheart_core_edge_last_sleep_score_json',
      );
  late final wearableRef = _lib
      .lookupFunction<_JsonReturnHandleC, _JsonReturnHandleDart>(
        'synheart_core_edge_wearable_reference_json',
      );
  late final exportSnap = _lib
      .lookupFunction<_JsonReturnHandleC, _JsonReturnHandleDart>(
        'synheart_core_edge_export_longitudinal_snapshot',
      );
}

String? _readAndFree(_Edge e, Pointer<Utf8> p) {
  if (p == nullptr) return null;
  // Some HSI payloads contain stage emoji (e.g., the
  // physiology spec doc title). `toDartString` does strict UTF-8
  // validation which occasionally trips on edge HSV notes; decode via
  // the byte view with `allowMalformed: true` to be robust. The
  // resulting String is still valid for JSON parsing since serde
  // output is always valid UTF-8 in practice.
  final bytes = p.cast<Uint8>();
  var len = 0;
  while (bytes.elementAt(len).value != 0) {
    len++;
  }
  final list = bytes.asTypedList(len);
  final s = utf8.decode(list, allowMalformed: true);
  e.freeString(p);
  return s;
}

DynamicLibrary? _openDylib() {
  final candidates = <String>[
    'native/libsynheart_core_runtime.dylib',
    '${Directory.current.path}/native/libsynheart_core_runtime.dylib',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) {
      return DynamicLibrary.open(path);
    }
  }
  return null;
}

void main() {
  final lib = _openDylib();
  if (lib == null) {
    test('skipped — native dylib not found', () {
      // Install the runtime via the Synheart CLI (`synheart install
      // runtime`) so the dylib lands in synheart-core-flutter/native/.
    }, skip: 'native runtime dylib not present');
    return;
  }
  final edge = _Edge(lib);

  Pointer<Void> makeHandle() {
    final cfg =
        '{"window_ms":10000,"step_ms":10000,"subject_id":"sub_e2e",'
        '"session_id":"sess_e2e","behavior_enabled":false}';
    final cfgCstr = cfg.toNativeUtf8();
    try {
      final h = edge.create(cfgCstr);
      expect(h, isNot(nullptr));
      return h;
    } finally {
      malloc.free(cfgCstr);
    }
  }

  void driveWindow(Pointer<Void> h) {
    for (int i = 0; i < 10; i++) {
      edge.pushRr(h, i * 1000, 800.0);
    }
    final first = edge.tick(h, 0);
    expect(first, nullptr);
    final second = edge.tick(h, 10000);
    expect(second, isNot(nullptr));
    edge.freeString(second);
  }

  group('E2E edge FFI sleep score', () {
    test('stateless compute round-trips vendor_score', () {
      final input = SleepScoreInput(
        tonight: NightRaw(
          wakeCalendarDate: 20100,
          detail: const VendorScoreNight(score: 74),
        ),
      );
      final p = input.toJsonString().toNativeUtf8();
      try {
        final out = edge.compute(p);
        final json = _readAndFree(edge, out);
        expect(json, isNotNull);
        final parsed = SleepScoreResult.fromJsonString(json!);
        expect(parsed.score, 74);
        expect(parsed.path, SleepPath.vendorScore);
        expect(parsed.reason, SleepScoreReason.vendorPassthrough);
      } finally {
        malloc.free(p);
      }
    });

    test('attach + tick yields sleep_score axis in next HSI', () {
      final h = makeHandle();
      try {
        final input = SleepScoreInput(
          tonight: NightRaw(
            wakeCalendarDate: 20100,
            detail: const AggregatedNight(
              totals: AggregatedTotals(
                totalSleepMinutes: 470,
                deepSleepMinutes: 85,
                remSleepMinutes: 110,
                awakeMinutes: 18,
                awakenings: 2,
                timeInBedMinutes: 488,
              ),
            ),
            avgHrBpm: 58.0,
          ),
        );
        final p = input.toJsonString().toNativeUtf8();
        final scoreJson = _readAndFree(edge, edge.compute(p))!;
        malloc.free(p);

        final scoreP = scoreJson.toNativeUtf8();
        final rc = edge.attach(h, scoreP);
        expect(rc, 0);
        malloc.free(scoreP);

        for (int i = 0; i < 10; i++) {
          edge.pushRr(h, i * 1000, 800.0);
        }
        edge.tick(h, 0);
        final hsiP = edge.tick(h, 10000);
        final hsi = _readAndFree(edge, hsiP)!;
        final v = jsonDecode(hsi) as Map<String, Object?>;
        final phys = (v['axes'] as Map)['physiological'] as List<Object?>;
        final names = phys
            .cast<Map<String, Object?>>()
            .map((r) => r['name'])
            .toList();
        expect(names, contains('sleep_score'));
        expect(names, contains('sleep'));
      } finally {
        edge.destroy(h);
      }
    });

    test('Path B: 3 poor scores surface median on wearable reference', () {
      final h = makeHandle();
      try {
        // Three 30-point scores → median 30 → < 40 threshold → 0.80 multiplier.
        for (int i = 0; i < 3; i++) {
          final input = SleepScoreInput(
            tonight: NightRaw(
              wakeCalendarDate: 20100 + i,
              detail: const VendorScoreNight(score: 30),
            ),
          );
          final p = input.toJsonString().toNativeUtf8();
          final scoreJson = _readAndFree(edge, edge.compute(p))!;
          malloc.free(p);
          final scoreP = scoreJson.toNativeUtf8();
          expect(edge.attach(h, scoreP), 0);
          malloc.free(scoreP);
        }
        // Drive a window so state_rt's wearable reference flushes.
        driveWindow(h);
        final refJson = _readAndFree(edge, edge.wearableRef(h));
        expect(
          refJson,
          isNotNull,
          reason: 'wearable reference should be populated after attaches',
        );
        final ref = WearableReferenceView.fromJsonString(refJson!);
        expect(
          ref.recentSleepScoreMedian,
          30,
          reason: 'median should surface after ≥3 attaches',
        );
      } finally {
        edge.destroy(h);
      }
    });

    test('last-sleep-score null before any window, populated after', () {
      final h = makeHandle();
      try {
        expect(edge.lastSleepScore(h), nullptr);
        driveWindow(h);
        final json = _readAndFree(edge, edge.lastSleepScore(h));
        expect(json, isNotNull);
        expect(json!, contains('"path"'));
      } finally {
        edge.destroy(h);
      }
    });

    test('longitudinal snapshot export is well-formed JSON', () {
      final h = makeHandle();
      try {
        final snap = _readAndFree(edge, edge.exportSnap(h));
        expect(snap, isNotNull);
        final parsed = jsonDecode(snap!);
        expect(parsed, isA<Map>());
      } finally {
        edge.destroy(h);
      }
    });

    test('attach rejects malformed JSON', () {
      final h = makeHandle();
      try {
        final bad = 'not a score'.toNativeUtf8();
        final rc = edge.attach(h, bad);
        expect(rc, lessThan(0));
        malloc.free(bad);
      } finally {
        edge.destroy(h);
      }
    });
  });
}
