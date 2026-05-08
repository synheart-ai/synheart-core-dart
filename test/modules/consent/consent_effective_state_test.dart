import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  group('ConsentEffectiveState', () {
    test('parses the runtime summary shape', () {
      final state = ConsentEffectiveState.fromJson(const {
        'biosignals': true,
        'phone_context': false,
        'behavior': true,
        'cloud_upload': true,
        'syni': false,
        'vendor_sync': true,
        'research': false,
        'timestamp_ms': 1776000000000,
        'version': '1.0.0',
      });

      expect(state.biosignals, isTrue);
      expect(state.phoneContext, isFalse);
      expect(state.behavior, isTrue);
      expect(state.cloudUpload, isTrue);
      expect(state.syni, isFalse);
      expect(state.vendorSync, isTrue);
      expect(state.research, isFalse);
      expect(state.timestampMs, 1776000000000);
      expect(state.version, '1.0.0');
    });

    test('round-trips through toJson/fromJson', () {
      const original = ConsentEffectiveState(
        biosignals: true,
        phoneContext: true,
        behavior: false,
        cloudUpload: true,
        syni: false,
        vendorSync: false,
        research: true,
        timestampMs: 1776000000001,
        version: '1.0.0',
      );

      final round = ConsentEffectiveState.fromJson(original.toJson());

      expect(round, equals(original));
    });

    test(
      'fromJson tolerates missing fields (all false, ts 0, version empty)',
      () {
        final state = ConsentEffectiveState.fromJson(const {});

        expect(state.biosignals, isFalse);
        expect(state.phoneContext, isFalse);
        expect(state.behavior, isFalse);
        expect(state.cloudUpload, isFalse);
        expect(state.syni, isFalse);
        expect(state.vendorSync, isFalse);
        expect(state.research, isFalse);
        expect(state.timestampMs, 0);
        expect(state.version, '');
      },
    );

    test('hasAnyGrant is false when everything is off', () {
      final state = ConsentEffectiveState.fromJson(const {});
      expect(state.hasAnyGrant, isFalse);
    });

    test('hasAnyGrant is true when any coarse flag is on', () {
      final state = ConsentEffectiveState.fromJson(const {'biosignals': true});
      expect(state.hasAnyGrant, isTrue);
    });
  });
}
