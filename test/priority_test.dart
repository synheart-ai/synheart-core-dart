// SPDX-License-Identifier: Apache-2.0
//
// Pure-Dart unit tests for the priority API (in-memory fallback path).
// Native FFI behavior is exercised by the runtime's own internal tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/priority/priority_metric.dart';
import 'package:synheart_core/src/priority/synheart_priority.dart';

void main() {
  group('PriorityMetric wire names', () {
    test('all metrics have stable wire strings', () {
      // These strings are persisted in the runtime SQLite schema —
      // changing one requires a migration.
      expect(PriorityMetric.heartRate.wireName, 'heart_rate');
      expect(PriorityMetric.hrv.wireName, 'hrv');
      expect(PriorityMetric.steps.wireName, 'steps');
      expect(PriorityMetric.sleep.wireName, 'sleep');
      expect(PriorityMetric.calories.wireName, 'calories');
      expect(PriorityMetric.spo2.wireName, 'spo2');
      expect(PriorityMetric.temperature.wireName, 'temperature');
      expect(PriorityMetric.stress.wireName, 'stress');
    });

    test('round-trip through fromWire', () {
      for (final m in PriorityMetric.values) {
        expect(PriorityMetric.fromWire(m.wireName), m);
      }
    });

    test('unknown wire returns null', () {
      expect(PriorityMetric.fromWire('garbage'), isNull);
    });
  });

  group('SynheartPriority (in-memory fallback)', () {
    late SynheartPriority p;

    setUp(() {
      // ffi=null forces the in-memory path.
      p = SynheartPriority(ffi: null);
    });

    test('reports it is not using native store', () {
      expect(p.usingNativeStore, isFalse);
    });

    test('unknown provider returns UNRANKED sentinel', () {
      expect(
        p.effectiveRank(PriorityMetric.heartRate, 'apple_watch'),
        kPriorityUnranked,
      );
    });

    test('set then read provider rank', () {
      p.setProviderPriority('apple_watch', 10);
      expect(p.effectiveRank(PriorityMetric.heartRate, 'apple_watch'), 10);
    });

    test('metric override beats global rank', () {
      p.setProviderPriority('oura_ring', 40);
      expect(p.effectiveRank(PriorityMetric.heartRate, 'oura_ring'), 40);
      p.setMetricOverride(PriorityMetric.sleep, 'oura_ring', 5);
      expect(p.effectiveRank(PriorityMetric.sleep, 'oura_ring'), 5);
      // Override only applies to the named metric.
      expect(p.effectiveRank(PriorityMetric.heartRate, 'oura_ring'), 40);
    });

    test('clearing override falls back to global', () {
      p.setProviderPriority('oura_ring', 40);
      p.setMetricOverride(PriorityMetric.sleep, 'oura_ring', 5);
      p.setMetricOverride(PriorityMetric.sleep, 'oura_ring', null);
      expect(p.effectiveRank(PriorityMetric.sleep, 'oura_ring'), 40);
    });

    test('empty provider name throws', () {
      expect(() => p.setProviderPriority('', 1), throwsA(isA<ArgumentError>()));
      expect(
        () => p.setMetricOverride(PriorityMetric.hrv, '', 1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SynheartPriority.resolve (in-memory)', () {
    late SynheartPriority p;
    setUp(() {
      p = SynheartPriority(ffi: null);
      p.setProviderPriority('apple_watch', 10);
      p.setProviderPriority('oura_ring', 40);
      p.setProviderPriority('phone', 90);
    });

    test('empty input returns null', () {
      expect(p.resolve(PriorityMetric.heartRate, {}), isNull);
    });

    test('all-zero counts returns null', () {
      expect(
        p.resolve(PriorityMetric.heartRate, {'apple_watch': 0, 'oura_ring': 0}),
        isNull,
      );
    });

    test('lowest rank wins', () {
      final r = p.resolve(PriorityMetric.heartRate, {
        'apple_watch': 100,
        'oura_ring': 100,
        'phone': 100,
      });
      expect(r, isNotNull);
      expect(r!.winner, 'apple_watch');
      expect(r.rank, 10);
      expect(r.alsoRan, hasLength(2));
      expect(r.alsoRan[0].provider, 'oura_ring');
      expect(r.alsoRan[1].provider, 'phone');
    });

    test('override changes winner', () {
      p.setMetricOverride(PriorityMetric.sleep, 'oura_ring', 5);
      final r = p.resolve(PriorityMetric.sleep, {
        'apple_watch': 100,
        'oura_ring': 100,
      });
      expect(r!.winner, 'oura_ring');
      expect(r.rank, 5);
    });

    test('tie broken by sample count then alpha', () {
      p.setProviderPriority('alpha', 10);
      p.setProviderPriority('beta', 10);
      p.setProviderPriority('charlie', 10);
      // beta has the highest count → wins
      final r = p.resolve(PriorityMetric.steps, {
        'alpha': 50,
        'beta': 200,
        'charlie': 50,
      });
      expect(r!.winner, 'beta');
      // Now tie on count → alphabetical order picks alpha
      final r2 = p.resolve(PriorityMetric.steps, {'alpha': 100, 'beta': 100});
      expect(r2!.winner, 'alpha');
    });

    test('unknown provider loses to known', () {
      final r = p.resolve(PriorityMetric.heartRate, {
        'apple_watch': 10,
        'ghost_tracker': 10,
      });
      expect(r!.winner, 'apple_watch');
    });

    test('unknown only still resolves with UNRANKED rank', () {
      final r = p.resolve(PriorityMetric.heartRate, {'ghost_tracker': 5});
      expect(r!.winner, 'ghost_tracker');
      expect(r.rank, kPriorityUnranked);
    });
  });
}
