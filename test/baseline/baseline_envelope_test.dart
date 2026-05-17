import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/artifacts/artifact_header.dart';
import 'package:synheart_core/src/baseline/baseline_envelope.dart';
import 'package:synheart_core/src/baseline/baseline_kind.dart';

BaselineEnvelope buildWearEnvelope({String artifactId = 'bs_test'}) {
  return BaselineEnvelope(
    header: ArtifactHeader(
      type: 'baseline_snapshot',
      artifactId: artifactId,
      subjectId: 'usr_alice',
      timeRange: const TimeRange(startMs: 1000, endMs: 2000),
      schema: const SchemaRef(name: 'baseline_snapshot', version: '1'),
      createdAtMs: 5000,
    ),
    kind: BaselineKind.longitudinalWear,
    kindSchemaVersion: 1,
    computedAtMs: 1500,
    engine: const BaselineEngineRef(
      name: 'srm_longitudinal',
      version: '0.9.2',
      configHash: 'h_abc',
    ),
    coverage: const BaselineCoverage(
      windowStartMs: 0,
      windowEndMs: 1000,
      observations: 27,
      dimensionsPresent: 5,
      dimensionsTotal: 5,
    ),
    payload: const {
      'schema_version': 1,
      'status': 'READY',
      'dimensions': {'hrv_rmssd_ms': 55.0},
      'confidence': {'hrv_rmssd_ms': 0.79},
    },
  );
}

void main() {
  group('BaselineEnvelope', () {
    test('round-trips through JSON preserving every field', () {
      final orig = buildWearEnvelope();
      final back = BaselineEnvelope.fromJson(orig.toJson());

      expect(back.kind, BaselineKind.longitudinalWear);
      expect(back.kindSchemaVersion, 1);
      expect(back.computedAtMs, 1500);
      expect(back.engine.name, 'srm_longitudinal');
      expect(back.engine.configHash, 'h_abc');
      expect(back.coverage.observations, 27);
      expect(back.header.artifactId, 'bs_test');
      expect(back.header.subjectId, 'usr_alice');
      expect(back.payload['status'], 'READY');
    });

    test('payloadLongitudinalWear decodes typed', () {
      final env = buildWearEnvelope();
      final p = env.payloadLongitudinalWear();
      expect(p.schemaVersion, 1);
      expect(p.reference.status, 'READY');
      expect(p.reference.dimensions['hrv_rmssd_ms'], 55.0);
      expect(p.reference.confidence['hrv_rmssd_ms'], 0.79);
    });

    test('wrong-kind extractor throws BaselineKindMismatch', () {
      final env = buildWearEnvelope();
      expect(
        () => env.payloadHsiAxes(),
        throwsA(isA<BaselineKindMismatch>()),
      );
      expect(
        () => env.payloadSrmMetrics(),
        throwsA(isA<BaselineKindMismatch>()),
      );
    });

    test('mismatch carries expected + actual kind for diagnostics', () {
      final env = buildWearEnvelope();
      try {
        env.payloadHsiAxes();
        fail('expected throw');
      } on BaselineKindMismatch catch (e) {
        expect(e.expected, BaselineKind.sessionHsiAxes);
        expect(e.actual, BaselineKind.longitudinalWear);
        expect(e.toString(), contains('session.hsi_axes'));
        expect(e.toString(), contains('longitudinal.wear'));
      }
    });

    test('unknown kind on the wire fails fromJson with a clear message', () {
      final orig = buildWearEnvelope();
      final json = orig.toJson();
      json['kind'] = 'future.behavior';
      expect(
        () => BaselineEnvelope.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('future.behavior'),
          ),
        ),
      );
    });

    test('missing header is a FormatException', () {
      final orig = buildWearEnvelope();
      final json = orig.toJson();
      json.remove('header');
      expect(
        () => BaselineEnvelope.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('session.hsi_axes envelope decodes via the typed extractor', () {
      final env = BaselineEnvelope(
        header: ArtifactHeader(
          type: 'baseline_snapshot',
          subjectId: 'usr_alice',
          sessionId: 'ses_123',
          timeRange: const TimeRange(startMs: 0, endMs: 1000),
          schema: const SchemaRef(name: 'baseline_snapshot', version: '1'),
        ),
        kind: BaselineKind.sessionHsiAxes,
        kindSchemaVersion: 1,
        computedAtMs: 500,
        engine: const BaselineEngineRef(
          name: 'hsi_axes_aggregator',
          version: '0.9.2',
          configHash: 'h_x',
        ),
        coverage: const BaselineCoverage(
          windowStartMs: 0,
          windowEndMs: 1000,
          observations: 100,
          dimensionsPresent: 2,
          dimensionsTotal: 4,
        ),
        payload: const {
          'schema_version': 1,
          'axes': {
            'sleep': {'mean': 0.6, 'std': 0.1, 'confidence': 0.8},
            'focus': {'mean': 0.7, 'std': 0.05, 'confidence': 0.9},
          },
        },
      );
      final p = env.payloadHsiAxes();
      expect(p.axes['sleep']?.mean, 0.6);
      expect(p.axes['focus']?.confidence, 0.9);
    });
  });
}
