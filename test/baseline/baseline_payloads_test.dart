import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/baseline/baseline_kind.dart';
import 'package:synheart_core/src/baseline/baseline_payloads.dart';

void main() {
  group('AxisStats', () {
    test('round-trips through JSON', () {
      const a = AxisStats(mean: 0.62, std: 0.11, confidence: 0.84);
      final back = AxisStats.fromJson(a.toJson());
      expect(back.mean, 0.62);
      expect(back.std, 0.11);
      expect(back.confidence, 0.84);
    });
  });

  group('HsiAxesBaseline', () {
    test('round-trips with multi-axis map', () {
      final orig = HsiAxesBaseline(
        schemaVersion: 1,
        axes: const {
          'sleep': AxisStats(mean: 0.62, std: 0.11, confidence: 0.84),
          'focus': AxisStats(mean: 0.71, std: 0.09, confidence: 0.78),
        },
      );
      final back = HsiAxesBaseline.fromJson(orig.toJson());
      expect(back.schemaVersion, 1);
      expect(back.axes.length, 2);
      expect(back.axes['sleep']?.mean, 0.62);
      expect(back.axes['focus']?.confidence, 0.78);
    });

    test('survives unknown future axes (forward-compat)', () {
      // The map is string-keyed, so a future HSI version's added axis
      // (e.g. 'sleep_depth') deserialized into the map without panic.
      final json = {
        'schema_version': 1,
        'axes': {
          'sleep': {'mean': 0.6, 'std': 0.1, 'confidence': 0.9},
          'novel_axis': {'mean': 0.4, 'std': 0.2, 'confidence': 0.7},
        },
      };
      final p = HsiAxesBaseline.fromJson(json);
      expect(p.axes.keys, containsAll(['sleep', 'novel_axis']));
    });
  });

  group('SessionSrmMetricsBaseline', () {
    test('round-trips with per-metric status', () {
      final orig = SessionSrmMetricsBaseline(
        schemaVersion: 1,
        metrics: const {
          'hrv_rmssd_ms': SrmMetricBaseline(
            muTilde: 48.3,
            sigmaTilde: 7.2,
            status: SrmMetricStatus.ready,
            nEff: 240,
          ),
          'motion_intensity': SrmMetricBaseline(
            muTilde: 0.12,
            sigmaTilde: 0.05,
            status: SrmMetricStatus.warming,
            nEff: 30,
          ),
        },
      );
      final back = SessionSrmMetricsBaseline.fromJson(orig.toJson());
      expect(back.metrics.length, 2);
      expect(back.metrics['hrv_rmssd_ms']?.muTilde, 48.3);
      expect(back.metrics['hrv_rmssd_ms']?.status, SrmMetricStatus.ready);
      expect(back.metrics['motion_intensity']?.nEff, 30);
    });

    test('unknown status wire degrades to empty (forward-compat)', () {
      // A future engine version that emits a new status string (e.g.
      // 'STALE' which doesn't exist on session-level today) → fromWire
      // returns null → we fall back to empty, not throw.
      final json = {
        'mu_tilde': 1.0,
        'sigma_tilde': 0.5,
        'status': 'FUTURE_VARIANT',
        'n_eff': 10,
      };
      final m = SrmMetricBaseline.fromJson(json);
      expect(m.status, SrmMetricStatus.empty);
      expect(m.muTilde, 1.0);
    });
  });

  group('LongitudinalWearBaseline', () {
    test('round-trips with flattened reference fields', () {
      // Build the wire shape directly — matches what the Rust
      // LongitudinalWearPayload with #[serde(flatten)] emits.
      final wire = {
        'schema_version': 1,
        'status': 'READY',
        'model_version': 'wearable-srm-v1',
        'dimensions': {
          'sleep_need_hours': 7.3,
          'hrv_rmssd_ms': 55.0,
          'resting_hr_bpm': 58.0,
          'recovery_score_baseline': 0.68,
          'sleep_regularity_score': 0.71,
          'recent_sleep_score_median': 74,
        },
        'confidence': {
          'sleep_need_hours': 0.86,
          'hrv_rmssd_ms': 0.79,
        },
      };
      final p = LongitudinalWearBaseline.fromJson(wire);
      expect(p.schemaVersion, 1);
      expect(p.reference.status, 'READY');
      expect(p.reference.modelVersion, 'wearable-srm-v1');
      expect(p.reference.dimensions['hrv_rmssd_ms'], 55.0);
      expect(p.reference.recentSleepScoreMedian, 74);
      expect(p.reference.confidence['sleep_need_hours'], 0.86);

      final back = LongitudinalWearBaseline.fromJson(p.toJson());
      expect(back.reference.dimensions['hrv_rmssd_ms'], 55.0);
      expect(back.reference.recentSleepScoreMedian, 74);
    });
  });
}
