// SPDX-License-Identifier: Apache-2.0
//
// Pure-Dart unit tests for the resilience wrapper. The native FFI
// path is exercised by the runtime's own internal tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/resilience/synheart_resilience.dart';

void main() {
  group('HrvSample', () {
    test('toJson produces wire-name keys', () {
      const s = HrvSample(tsMs: 100, rmssdMs: 42.5);
      expect(s.toJson(), {
        'ts_ms': 100,
        'rmssd_ms': 42.5,
        'kind': 'nightly_rmssd',
      });
    });
  });

  group('SleepWindow', () {
    test('toJson produces wire-name keys', () {
      const w = SleepWindow(startMs: 1000, endMs: 2000);
      expect(w.toJson(), {'start_ms': 1000, 'end_ms': 2000});
    });
  });

  group('ResilienceConfig', () {
    test('defaults match runtime defaults', () {
      const c = ResilienceConfig();
      expect(c.lookbackDays, 7);
      expect(c.minDaysRequired, 5);
      expect(c.minRrSamples, 20);
      expect(c.cvCeilingPct, 7.0);
      expect(c.cvFloorPct, 40.0);
    });

    test('toJson produces snake_case keys for runtime', () {
      const c = ResilienceConfig();
      final j = c.toJson();
      expect(j['lookback_days'], 7);
      expect(j['min_days_required'], 5);
      expect(j['min_rr_samples'], 20);
      expect(j['cv_ceiling_pct'], 7.0);
      expect(j['cv_floor_pct'], 40.0);
    });
  });

  group('ResilienceReason.fromWire', () {
    test('maps every variant', () {
      expect(
        ResilienceReason.fromWire('InsufficientDays'),
        ResilienceReason.insufficientDays,
      );
      expect(
        ResilienceReason.fromWire('NoSleepWindows'),
        ResilienceReason.noSleepWindows,
      );
      expect(
        ResilienceReason.fromWire('InsufficientSamples'),
        ResilienceReason.insufficientSamples,
      );
      expect(
        ResilienceReason.fromWire('NoValidSamples'),
        ResilienceReason.noValidSamples,
      );
      expect(
        ResilienceReason.fromWire('ZeroMeanHrv'),
        ResilienceReason.zeroMeanHrv,
      );
    });

    test('null and unknown return null', () {
      expect(ResilienceReason.fromWire(null), isNull);
      expect(ResilienceReason.fromWire('garbage'), isNull);
    });
  });

  group('ResilienceResult.fromJson', () {
    test('parses an unavailable result (NoSleepWindows)', () {
      final r = ResilienceResult.fromJson({
        'score': null,
        'rmssd_ow_ms': null,
        'sdnn_ow_ms': null,
        'hrv_cv_pct': null,
        'days_used': 0,
        'samples_used': 0,
        'confidence': 0.0,
        'reason': 'NoSleepWindows',
        'model_id': 'resilience/1.0.0',
        'pipeline_version': 'resilience/1.0.0',
        'constants_hash': 'a' * 64,
      });
      expect(r.score, isNull);
      expect(r.reason, ResilienceReason.noSleepWindows);
      expect(r.daysUsed, 0);
      expect(r.modelId, 'resilience/1.0.0');
      expect(r.constantsHash.length, 64);
    });

    test('parses a successful result', () {
      final r = ResilienceResult.fromJson({
        'score': 100,
        'rmssd_ow_ms': 50.0,
        'sdnn_ow_ms': 50.0,
        'hrv_cv_pct': 0.0,
        'days_used': 7,
        'samples_used': 70,
        'confidence': 1.0,
        'reason': null,
        'model_id': 'resilience/1.0.0',
        'pipeline_version': 'resilience/1.0.0',
        'constants_hash': 'b' * 64,
      });
      expect(r.score, 100);
      expect(r.reason, isNull);
      expect(r.daysUsed, 7);
      expect(r.samplesUsed, 70);
      expect(r.confidence, 1.0);
    });

    test('tolerates missing optional metric fields', () {
      final r = ResilienceResult.fromJson({
        'days_used': 0,
        'samples_used': 0,
        'confidence': 0.0,
      });
      expect(r.score, isNull);
      expect(r.rmssdOwMs, isNull);
      expect(r.sdnnOwMs, isNull);
      expect(r.modelId, '');
    });
  });

  group('SynheartResilience (FFI absent)', () {
    test('reports not available when ffi is null', () {
      final r = SynheartResilience(ffi: null);
      expect(r.isAvailable, isFalse);
    });

    test('compute throws ResilienceUnavailable when ffi is null', () {
      final r = SynheartResilience(ffi: null);
      expect(
        () => r.compute(samples: const [], sleepWindows: const []),
        throwsA(isA<ResilienceUnavailable>()),
      );
    });
  });

  group('ResilienceError stringification', () {
    test('all error types stringify usefully', () {
      const errs = <ResilienceError>[
        ResilienceUnavailable(),
        ResilienceComputeFailed('boom'),
      ];
      for (final e in errs) {
        expect(e.toString(), startsWith('ResilienceError:'));
      }
    });

    test('ResilienceUnavailable suggests an actionable upgrade path', () {
      // Was asserting the literal '5.4.0', a stale version string. Assert the
      // remedy instead so the test survives version-scheme changes.
      const e = ResilienceUnavailable();
      expect(e.message, contains('synheart install runtime'));
      expect(e.message, isNot(contains('5.4.0')));
    });
  });
}
