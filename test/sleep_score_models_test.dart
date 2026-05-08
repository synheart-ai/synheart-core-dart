// Unit tests for Dart typed models mirroring the runtime's `SleepScoreResult`
// JSON shape. No native loading — pure in-memory round-trip.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/models/sleep_score.dart';

void main() {
  group('SleepScoreInput JSON shape', () {
    test('segmented night round-trips to the runtime-expected schema', () {
      final input = SleepScoreInput(
        tonight: NightRaw(
          wakeCalendarDate: 20100,
          detail: SegmentedNight(
            sessionStartMs: 1736300000000,
            sessionEndMs: 1736328800000,
            zoneId: 'America/Los_Angeles',
            segments: [
              const StageSegment(
                stage: SleepStage.awake,
                startMs: 1736300000000,
                endMs: 1736300300000,
              ),
              const StageSegment(
                stage: SleepStage.deep,
                startMs: 1736300300000,
                endMs: 1736305700000,
              ),
            ],
          ),
          avgHrBpm: 58.0,
        ),
        priorsNewestFirst: const [],
        pipelineVersion: 'sleep_score/1.0.0',
      );

      final json = jsonDecode(input.toJsonString()) as Map<String, Object?>;
      final tonight = json['tonight'] as Map<String, Object?>;
      expect(tonight['wake_calendar_date'], 20100);
      expect(tonight['avg_hr_bpm'], 58.0);

      final detail = tonight['detail'] as Map<String, Object?>;
      expect(detail['kind'], 'segmented');
      expect(detail['zone_id'], 'America/Los_Angeles');
      expect(detail['session_start_ms'], 1736300000000);

      final segments = detail['segments'] as List<Object?>;
      expect(segments, hasLength(2));
      final first = segments.first as Map<String, Object?>;
      expect(first['stage'], 'awake');
      expect(first['start_ms'], 1736300000000);
    });

    test('aggregated night includes all total fields', () {
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
      final json = jsonDecode(input.toJsonString()) as Map<String, Object?>;
      final totals =
          ((json['tonight'] as Map)['detail'] as Map)['totals']
              as Map<String, Object?>;
      expect(totals['total_sleep_minutes'], 470);
      expect(totals['deep_sleep_minutes'], 85);
      expect(totals['rem_sleep_minutes'], 110);
      expect(totals['awake_minutes'], 18);
      expect(totals['awakenings'], 2);
      expect(totals['time_in_bed_minutes'], 488);
    });

    test('vendor-score night carries only the scalar', () {
      final input = SleepScoreInput(
        tonight: NightRaw(
          wakeCalendarDate: 20100,
          detail: const VendorScoreNight(score: 82),
        ),
      );
      final detail =
          ((jsonDecode(input.toJsonString()) as Map<String, Object?>)['tonight']
                  as Map)['detail']
              as Map<String, Object?>;
      expect(detail['kind'], 'vendor_score');
      expect(detail['score'], 82);
    });
  });

  group('SleepScoreResult JSON shape', () {
    test('parses the full native shape', () {
      // Sample matching the output of
      // synheart_sleep_score::compute_sleep_score on a vendor_score input.
      const raw = '''
      {
        "score": 82,
        "score_normalized": 0.82,
        "confidence": 0.65,
        "path": "vendor_score",
        "mode": "cold_start",
        "components": {
          "duration": null,
          "quality": null,
          "continuity": null,
          "consistency": null,
          "personalization": null,
          "vendor_score": 82,
          "proxy_hr": null
        },
        "adjustments": {
          "debt_penalty": 0,
          "hr_adjustment": 0
        },
        "effective_weights": {
          "duration": 0.0,
          "quality": 0.0,
          "continuity": 0.0,
          "consistency": 0.0,
          "personalization": 0.0
        },
        "reason": "vendor_passthrough",
        "prior_night_count": 0,
        "pipeline_version": "sleep_score/1.0.0",
        "model_id": "rulepack://sleep_score_v1",
        "constants_hash": "deadbeefcafef00d"
      }''';
      final r = SleepScoreResult.fromJsonString(raw);
      expect(r.score, 82);
      expect(r.scoreNormalized, closeTo(0.82, 1e-6));
      expect(r.path, SleepPath.vendorScore);
      expect(r.mode, SleepScoreMode.coldStart);
      expect(r.reason, SleepScoreReason.vendorPassthrough);
      expect(r.components.vendorScore, 82);
      expect(r.components.duration, isNull);
      expect(r.pipelineVersion, 'sleep_score/1.0.0');
      expect(r.modelId, 'rulepack://sleep_score_v1');
      expect(r.constantsHash, 'deadbeefcafef00d');
    });

    test('handles null score (no-data path)', () {
      const raw = '''
      {
        "score": null,
        "score_normalized": null,
        "confidence": 0.0,
        "path": "proxy",
        "mode": "cold_start",
        "components": {},
        "adjustments": {"debt_penalty": 0, "hr_adjustment": 0},
        "effective_weights": {},
        "reason": "no_sleep_data",
        "prior_night_count": 0,
        "pipeline_version": "sleep_score/1.0.0",
        "model_id": "rulepack://sleep_score_v1",
        "constants_hash": "deadbeefcafef00d"
      }''';
      final r = SleepScoreResult.fromJsonString(raw);
      expect(r.score, isNull);
      expect(r.scoreNormalized, isNull);
      expect(r.confidence, 0.0);
      expect(r.reason, SleepScoreReason.noSleepData);
    });
  });

  group('WearableReferenceView', () {
    test('extracts Path-B recent_sleep_score_median', () {
      const raw = '''
      {
        "status": "Warming",
        "model_version": "longitudinal-srm-v1",
        "dimensions": {
          "recent_sleep_score_median": 42,
          "sleep_need_hours": 7.5
        },
        "confidence": {},
        "today": null
      }''';
      final v = WearableReferenceView.fromJsonString(raw);
      expect(v.status, 'Warming');
      expect(v.recentSleepScoreMedian, 42);
    });

    test('tolerates missing median', () {
      const raw = '''
      {"status":"Empty","model_version":"x","dimensions":{},"confidence":{}}''';
      final v = WearableReferenceView.fromJsonString(raw);
      expect(v.recentSleepScoreMedian, isNull);
    });
  });

  group('Enum wire contracts', () {
    test('path wire values are snake_case', () {
      expect(SleepPath.stage.wire, 'stage');
      expect(SleepPath.aggregated.wire, 'aggregated');
      expect(SleepPath.vendorScore.wire, 'vendor_score');
      expect(SleepPath.proxy.wire, 'proxy');
    });

    test('mode wire values are snake_case', () {
      expect(SleepScoreMode.coldStart.wire, 'cold_start');
      expect(SleepScoreMode.shortHistory.wire, 'short_history');
      expect(SleepScoreMode.stable.wire, 'stable');
    });
  });
}
