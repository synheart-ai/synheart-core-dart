import 'dart:convert';

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

    test('cache populates latestLongitudinalWear with the typed payload',
        () {
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

    test('cache is per-kind — writing one kind does not surface another',
        () {
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

  group('Cloud wiring', () {
    test('isCloudWired is false before wireCloud is called', () {
      expect(BaselineSnapshots().isCloudWired, isFalse);
    });

    test('isCloudWired is true after wireCloud with both hooks', () {
      final s = BaselineSnapshots();
      s.wireCloud(
        uploader: (_) async => {'success': true},
        sweep: (_) async => {
          'success': true,
          'body': {'snapshots': []},
        },
      );
      expect(s.isCloudWired, isTrue);
    });

    test('upload before wireCloud throws BaselineCloudUnavailable', () {
      expect(
        () => BaselineSnapshots().upload(
          buildEnvelope(BaselineKind.longitudinalWear),
        ),
        throwsA(isA<BaselineCloudUnavailable>()),
      );
    });

    test('restoreAll before wireCloud throws BaselineCloudUnavailable', () {
      expect(
        () => BaselineSnapshots().restoreAll(subjectId: 'usr_alice'),
        throwsA(isA<BaselineCloudUnavailable>()),
      );
    });
  });

  group('Cloud upload', () {
    test('successful upload calls the uploader with the envelope JSON',
        () async {
      final s = BaselineSnapshots();
      String? capturedJson;
      s.wireCloud(
        uploader: (envJson) async {
          capturedJson = envJson;
          return {
            'success': true,
            'status_code': 200,
            'body': {'artifact_id': 'bs_x', 'status': 'stored'},
          };
        },
        sweep: (_) async => null,
      );

      final envelope = buildEnvelope(BaselineKind.longitudinalWear);
      await s.upload(envelope);

      expect(capturedJson, isNotNull);
      final decoded = jsonDecode(capturedJson!) as Map<String, dynamic>;
      expect(decoded['kind'], 'longitudinal.wear');
      expect(decoded['header']['subject_id'], 'usr_alice');
    });

    test('upload throws BaselineCloudUnavailable when FFI returns null', () {
      final s = BaselineSnapshots();
      s.wireCloud(uploader: (_) async => null, sweep: (_) async => null);
      expect(
        () => s.upload(buildEnvelope(BaselineKind.longitudinalWear)),
        throwsA(isA<BaselineCloudUnavailable>()),
      );
    });

    test('upload throws BaselineCloudError when cloud returns success=false',
        () {
      final s = BaselineSnapshots();
      s.wireCloud(
        uploader: (_) async => {
          'success': false,
          'status_code': 403,
          'error_message': 'device not signed',
        },
        sweep: (_) async => null,
      );
      expect(
        () => s.upload(buildEnvelope(BaselineKind.longitudinalWear)),
        throwsA(
          isA<BaselineCloudError>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', 'device not signed'),
        ),
      );
    });

    test('upload throws BaselineCloudError on internal error envelope', () {
      final s = BaselineSnapshots();
      s.wireCloud(
        uploader: (_) async => {'error': 'invalid handle'},
        sweep: (_) async => null,
      );
      expect(
        () => s.upload(buildEnvelope(BaselineKind.longitudinalWear)),
        throwsA(isA<BaselineCloudError>()),
      );
    });
  });

  group('Cloud restoreAll', () {
    Map<String, dynamic> envelopeWire(BaselineKind kind, String id) {
      return buildEnvelope(kind, id: id).toJson();
    }

    test('restoreAll populates the cache from cloud-returned envelopes',
        () async {
      final s = BaselineSnapshots();
      s.wireCloud(
        uploader: (_) async => null,
        sweep: (subjectId) async {
          expect(subjectId, 'usr_alice');
          return {
            'success': true,
            'status_code': 200,
            'body': {
              'snapshots': [
                envelopeWire(BaselineKind.longitudinalWear, 'bs_wear'),
                envelopeWire(BaselineKind.sessionHsiAxes, 'bs_hsi'),
              ],
            },
          };
        },
      );

      final restored = await s.restoreAll(subjectId: 'usr_alice');
      expect(restored.length, 2);

      // Cache is now populated; typed getters return real values.
      final wear = s.latestLongitudinalWear();
      final hsi = s.latestHsiAxes();
      expect(wear, isNotNull);
      expect(hsi, isNotNull);
      expect(wear!.reference.dimensions['hrv_rmssd_ms'], 55.0);
      expect(hsi!.axes['sleep']?.mean, 0.6);
    });

    test('restoreAll returns empty list when subject has no baselines',
        () async {
      final s = BaselineSnapshots();
      s.wireCloud(
        uploader: (_) async => null,
        sweep: (_) async => {
          'success': true,
          'body': {'snapshots': []},
        },
      );
      final restored = await s.restoreAll(subjectId: 'usr_alice');
      expect(restored, isEmpty);
      expect(s.envelopesByKind(), isEmpty);
    });

    test('restoreAll skips envelopes with unknown kinds (forward-compat)',
        () async {
      final s = BaselineSnapshots();
      final wear = envelopeWire(BaselineKind.longitudinalWear, 'bs_wear');
      final future = {
        ...wear,
        'kind': 'future.behavior',
      };
      s.wireCloud(
        uploader: (_) async => null,
        sweep: (_) async => {
          'success': true,
          'body': {
            'snapshots': [wear, future],
          },
        },
      );
      final restored = await s.restoreAll(subjectId: 'usr_alice');
      expect(restored.length, 1, reason: 'unknown kind silently skipped');
      expect(s.latestLongitudinalWear(), isNotNull);
    });

    test(
      'restoreAll throws BaselineCloudError when cloud returns success=false',
      () {
        final s = BaselineSnapshots();
        s.wireCloud(
          uploader: (_) async => null,
          sweep: (_) async => {
            'success': false,
            'status_code': 500,
            'error_message': 'storage error',
          },
        );
        expect(
          () => s.restoreAll(subjectId: 'usr_alice'),
          throwsA(isA<BaselineCloudError>()),
        );
      },
    );
  });
}
