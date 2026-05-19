import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/baseline/baseline_kind.dart';

void main() {
  group('BaselineKind', () {
    test('wire strings are stable', () {
      expect(BaselineKind.sessionHsiAxes.wire, 'session.hsi_axes');
      expect(BaselineKind.sessionSrmMetrics.wire, 'session.srm_metrics');
      expect(BaselineKind.longitudinalWear.wire, 'longitudinal.wear');
    });

    test('round-trips through fromWire', () {
      for (final k in BaselineKind.values) {
        expect(BaselineKind.fromWire(k.wire), k);
      }
    });

    test('unknown wire returns null (forward-compat)', () {
      expect(BaselineKind.fromWire('future.behavior'), isNull);
      expect(BaselineKind.fromWire(''), isNull);
      expect(BaselineKind.fromWire(null), isNull);
    });

    test('isSessionScoped reflects the session.* prefix', () {
      expect(BaselineKind.sessionHsiAxes.isSessionScoped, isTrue);
      expect(BaselineKind.sessionSrmMetrics.isSessionScoped, isTrue);
      expect(BaselineKind.longitudinalWear.isSessionScoped, isFalse);
    });
  });

  group('SrmMetricStatus', () {
    test('wire strings are uppercase', () {
      expect(SrmMetricStatus.empty.wire, 'EMPTY');
      expect(SrmMetricStatus.warming.wire, 'WARMING');
      expect(SrmMetricStatus.ready.wire, 'READY');
    });

    test('fromWire round trips', () {
      for (final s in SrmMetricStatus.values) {
        expect(SrmMetricStatus.fromWire(s.wire), s);
      }
    });

    test('unknown wire returns null', () {
      expect(SrmMetricStatus.fromWire('STALE'), isNull);
      expect(SrmMetricStatus.fromWire(null), isNull);
    });
  });
}
