import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  group('unwrapSyncEnvelope', () {
    test('null passes through as null (legacy failure sentinel)', () {
      expect(unwrapSyncEnvelope(null), isNull);
    });

    test('legacy bare payload (no ok key) is returned unchanged', () {
      final legacy = {'sync_space_id': 'space_123', 'recovery_key': 'abc'};
      expect(unwrapSyncEnvelope(legacy), same(legacy));
    });

    test('success envelope returns the data map', () {
      final env = {
        'ok': true,
        'data': {'sync_space_id': 'space_123', 'recovery_key': 'abc'},
      };
      final data = unwrapSyncEnvelope(env);
      expect(data, isNotNull);
      expect(data!['sync_space_id'], 'space_123');
      expect(data['recovery_key'], 'abc');
    });

    test('success envelope with missing data yields an empty map', () {
      expect(unwrapSyncEnvelope({'ok': true}), <String, dynamic>{});
    });

    test('failure envelope throws a typed SyncNativeException', () {
      final env = {
        'ok': false,
        'error': {
          'code': 'DEVICE_REGISTRATION_REQUIRED',
          'message': 'Device registration is required.',
          'retryable': false,
        },
      };
      expect(
        () => unwrapSyncEnvelope(env),
        throwsA(
          isA<SyncNativeException>()
              .having((e) => e.code, 'code', 'DEVICE_REGISTRATION_REQUIRED')
              .having((e) => e.message, 'message',
                  'Device registration is required.')
              .having((e) => e.retryable, 'retryable', false),
        ),
      );
    });

    test('retryable failure is preserved', () {
      final env = {
        'ok': false,
        'error': {
          'code': 'NETWORK',
          'message': 'Network error.',
          'retryable': true,
        },
      };
      expect(
        () => unwrapSyncEnvelope(env),
        throwsA(isA<SyncNativeException>()
            .having((e) => e.retryable, 'retryable', true)),
      );
    });

    test('malformed failure envelope falls back to UNKNOWN', () {
      expect(
        () => unwrapSyncEnvelope({'ok': false}),
        throwsA(isA<SyncNativeException>()
            .having((e) => e.code, 'code', 'UNKNOWN')),
      );
    });

    test('readiness snapshot keys stay top-level after unwrap', () {
      final env = {
        'ok': true,
        'data': {
          'state': 'DEVICE_REGISTRATION_REQUIRED',
          'configured': true,
          'storage_present': true,
          'device_registered': false,
        },
      };
      final data = unwrapSyncEnvelope(env)!;
      expect(data['state'], 'DEVICE_REGISTRATION_REQUIRED');
      expect(data['device_registered'], false);
    });
  });
}
