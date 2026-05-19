import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/artifacts/artifact_header.dart';
import 'package:synheart_core/src/baseline/baseline_envelope.dart';
import 'package:synheart_core/src/baseline/baseline_kind.dart';
import 'package:synheart_core/src/baseline/baseline_snapshots.dart';

BaselineEnvelope buildEnvelope(BaselineKind kind, {String id = 'bs_x'}) {
  ArtifactHeader header(String? sessionId) => ArtifactHeader(
    type: 'baseline_snapshot',
    artifactId: id,
    subjectId: 'usr_alice',
    sessionId: sessionId,
    timeRange: const TimeRange(startMs: 0, endMs: 1000),
    schema: const SchemaRef(name: 'baseline_snapshot', version: '1'),
    createdAtMs: 5000,
  );

  Map<String, dynamic> payloadFor(BaselineKind k) {
    switch (k) {
      case BaselineKind.longitudinalWear:
        return {
          'schema_version': 1,
          'status': 'READY',
          'dimensions': {'hrv_rmssd_ms': 55.0},
          'confidence': {'hrv_rmssd_ms': 0.79},
        };
      case BaselineKind.sessionHsiAxes:
        return {
          'schema_version': 1,
          'axes': {
            'sleep': {'mean': 0.6, 'std': 0.1, 'confidence': 0.8},
          },
        };
      case BaselineKind.sessionSrmMetrics:
        return {
          'schema_version': 1,
          'metrics': {
            'hrv_rmssd_ms': {
              'mu_tilde': 48.3,
              'sigma_tilde': 7.2,
              'status': 'READY',
              'n_eff': 240,
            },
          },
        };
    }
  }

  return BaselineEnvelope(
    header: header(kind.isSessionScoped ? 'ses_x' : null),
    kind: kind,
    kindSchemaVersion: 1,
    computedAtMs: 1500,
    engine: const BaselineEngineRef(
      name: 'e',
      version: '0.9.2',
      configHash: 'h',
    ),
    coverage: const BaselineCoverage(
      windowStartMs: 0,
      windowEndMs: 1000,
      observations: 27,
      dimensionsPresent: 5,
      dimensionsTotal: 5,
    ),
    payload: payloadFor(kind),
  );
}

void main() {
  group('BaselineSnapshots in-memory cache', () {
    test('typed getters return null when nothing is cached', () {
      final s = BaselineSnapshots();
      expect(s.latestLongitudinalWear(), isNull);
      expect(s.latestHsiAxes(), isNull);
      expect(s.latestSrmMetrics(), isNull);
    });

    test('cache populates latestLongitudinalWear with the typed payload', () {
      final s = BaselineSnapshots();
      s.cache(buildEnvelope(BaselineKind.longitudinalWear));
      final wear = s.latestLongitudinalWear();
      expect(wear, isNotNull);
      expect(wear!.reference.dimensions['hrv_rmssd_ms'], 55.0);
      expect(wear.reference.status, 'READY');
    });

    test('cache populates latestHsiAxes with the typed payload', () {
      final s = BaselineSnapshots();
      s.cache(buildEnvelope(BaselineKind.sessionHsiAxes, id: 'bs_hsi'));
      final hsi = s.latestHsiAxes();
      expect(hsi, isNotNull);
      expect(hsi!.axes['sleep']?.mean, 0.6);
    });

    test('cache populates latestSrmMetrics with the typed payload', () {
      final s = BaselineSnapshots();
      s.cache(buildEnvelope(BaselineKind.sessionSrmMetrics, id: 'bs_srm'));
      final srm = s.latestSrmMetrics();
      expect(srm, isNotNull);
      expect(srm!.metrics['hrv_rmssd_ms']?.muTilde, 48.3);
    });

    test('cache is per-kind — writing one kind does not surface another', () {
      final s = BaselineSnapshots();
      s.cache(buildEnvelope(BaselineKind.longitudinalWear));
      expect(s.latestHsiAxes(), isNull);
      expect(s.latestSrmMetrics(), isNull);
    });

    test('last-write-wins per kind', () {
      final s = BaselineSnapshots();
      s.cache(buildEnvelope(BaselineKind.longitudinalWear, id: 'bs_a'));
      s.cache(buildEnvelope(BaselineKind.longitudinalWear, id: 'bs_b'));
      expect(
        s.envelopeFor(BaselineKind.longitudinalWear)?.header.artifactId,
        'bs_b',
      );
    });

    test('envelopesByKind reflects every cached kind', () {
      final s = BaselineSnapshots();
      s.cache(buildEnvelope(BaselineKind.longitudinalWear));
      s.cache(buildEnvelope(BaselineKind.sessionHsiAxes, id: 'bs_hsi'));
      final m = s.envelopesByKind();
      expect(m.length, 2);
      expect(m.containsKey(BaselineKind.longitudinalWear), isTrue);
      expect(m.containsKey(BaselineKind.sessionHsiAxes), isTrue);
    });

    test('envelopesByKind is unmodifiable', () {
      final s = BaselineSnapshots();
      s.cache(buildEnvelope(BaselineKind.longitudinalWear));
      final m = s.envelopesByKind();
      expect(
        () => m.remove(BaselineKind.longitudinalWear),
        throwsUnsupportedError,
      );
    });

    test('reset clears every cached envelope', () {
      final s = BaselineSnapshots();
      s.cache(buildEnvelope(BaselineKind.longitudinalWear));
      s.cache(buildEnvelope(BaselineKind.sessionHsiAxes, id: 'bs_hsi'));
      s.reset();
      expect(s.envelopesByKind(), isEmpty);
      expect(s.latestLongitudinalWear(), isNull);
      expect(s.latestHsiAxes(), isNull);
    });
  });

  group('Local hydration', () {
    test('hydrateFromLocal is a no-op before wireLocalHydrator', () async {
      final s = BaselineSnapshots();
      final restored = await s.hydrateFromLocal();
      expect(restored, isEmpty);
    });

    test('hydrateFromLocal populates the cache from local snapshots', () async {
      final s = BaselineSnapshots();
      s.wireLocalHydrator(
        () async => {
          'snapshots': [
            buildEnvelope(
              BaselineKind.longitudinalWear,
              id: 'bs_wear',
            ).toJson(),
            buildEnvelope(BaselineKind.sessionHsiAxes, id: 'bs_hsi').toJson(),
          ],
        },
      );
      final restored = await s.hydrateFromLocal();
      expect(restored.length, 2);
      expect(s.latestLongitudinalWear(), isNotNull);
      expect(s.latestHsiAxes(), isNotNull);
    });

    test(
      'hydrateFromLocal skips envelopes with unknown kinds (forward-compat)',
      () async {
        final s = BaselineSnapshots();
        final wear = buildEnvelope(
          BaselineKind.longitudinalWear,
          id: 'bs_wear',
        ).toJson();
        final future = {...wear, 'kind': 'future.behavior'};
        s.wireLocalHydrator(
          () async => {
            'snapshots': [wear, future],
          },
        );
        final restored = await s.hydrateFromLocal();
        expect(restored.length, 1, reason: 'unknown kind silently skipped');
        expect(s.latestLongitudinalWear(), isNotNull);
      },
    );

    test('hydrateFromLocal returns empty on error envelope', () async {
      final s = BaselineSnapshots();
      s.wireLocalHydrator(() async => {'error': 'invalid handle'});
      final restored = await s.hydrateFromLocal();
      expect(restored, isEmpty);
      expect(s.envelopesByKind(), isEmpty);
    });

    test('wireLocalHydrator(null) clears the hook', () async {
      final s = BaselineSnapshots();
      s.wireLocalHydrator(
        () async => {
          'snapshots': [buildEnvelope(BaselineKind.longitudinalWear).toJson()],
        },
      );
      s.wireLocalHydrator(null);
      final restored = await s.hydrateFromLocal();
      expect(restored, isEmpty);
    });
  });
}
