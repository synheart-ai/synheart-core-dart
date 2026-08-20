import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

/// Runtime 0.20.0 added `reason`, `retry_after_ms` and `detail` to the sync
/// failure envelope. `fromMap` previously read three keys and discarded the
/// rest, so the information reached the FFI boundary and stopped there — a
/// device refused by policy and a device that simply cannot attest arrived at
/// the host looking identical.
///
/// Envelope shapes below are taken from the runtime's SDK integration note.
void main() {
  group('SyncNativeError.fromMap', () {
    test('parses the full 0.20.0 envelope', () {
      final envelope =
          jsonDecode('''
        {
          "code": "ATTESTATION_UNAVAILABLE",
          "message": "Device verification is temporarily unavailable. Please try again.",
          "retryable": true,
          "reason": "transient",
          "retry_after_ms": 5000,
          "detail": { "phase": "attestation" }
        }
      ''')
              as Map<String, dynamic>;

      final e = SyncNativeError.fromMap(envelope);

      expect(e.code, 'ATTESTATION_UNAVAILABLE');
      expect(e.retryable, isTrue);
      expect(e.reason, 'transient');
      expect(e.retryAfterMs, 5000);
      expect(e.detail?['phase'], 'attestation');
    });

    test(
      'the three new fields are optional — an older runtime still parses',
      () {
        // Pre-0.20.0 runtimes omit them entirely. Absence is normal.
        final e = SyncNativeError.fromMap({
          'code': 'REGISTRATION_REJECTED',
          'message': 'This device is not permitted to register with this app.',
          'retryable': false,
        });

        expect(e.code, 'REGISTRATION_REJECTED');
        expect(e.reason, isNull);
        expect(e.retryAfterMs, isNull);
        expect(e.detail, isNull);
        expect(e.isUnsupported, isFalse);
      },
    );

    test('retry_after_ms survives decoding as a double', () {
      // The envelope crosses an FFI JSON boundary; an integral value is not
      // guaranteed to arrive as int.
      final e = SyncNativeError.fromMap({
        'code': 'ATTESTATION_UNAVAILABLE',
        'message': 'x',
        'retryable': true,
        'retry_after_ms': 15000.0,
      });
      expect(e.retryAfterMs, 15000);
    });

    test('an empty reason string is treated as absent, not as a reason', () {
      final e = SyncNativeError.fromMap({
        'code': 'X',
        'message': 'y',
        'reason': '',
      });
      expect(e.reason, isNull);
    });

    test('classifiers map the reason vocabulary', () {
      SyncNativeError withReason(String r) =>
          SyncNativeError.fromMap({'code': 'C', 'message': 'm', 'reason': r});

      expect(withReason('unsupported').isUnsupported, isTrue);
      expect(withReason('misconfigured').isMisconfigured, isTrue);
      expect(withReason('policy').isPolicyRefusal, isTrue);

      // Each classifier answers only for its own reason.
      expect(withReason('policy').isUnsupported, isFalse);
      expect(withReason('transient').isMisconfigured, isFalse);
    });
  });

  group('toString', () {
    test('includes the reason so crash logs can tell failures apart', () {
      final e = SyncNativeError.fromMap({
        'code': 'REGISTRATION_REJECTED',
        'message': 'This device is not permitted to register with this app.',
        'retryable': false,
        'reason': 'policy',
      });

      // The exact string that reaches a crash report.
      expect(e.toString(), contains('policy'));
      expect(e.toString(), contains('REGISTRATION_REJECTED'));
      expect(e.toString(), contains('retryable: false'));
    });

    test('omits the reason clause entirely when there is none', () {
      final e = SyncNativeError.fromMap({'code': 'C', 'message': 'm'});
      expect(e.toString(), isNot(contains('reason')));
    });

    test('surfaces the backoff when one was suggested', () {
      final e = SyncNativeError.fromMap({
        'code': 'ATTESTATION_UNAVAILABLE',
        'message': 'm',
        'retryable': true,
        'reason': 'timeout',
        'retry_after_ms': 15000,
      });
      expect(e.toString(), contains('retryAfterMs: 15000'));
    });
  });

  group('SyncNativeException passthrough', () {
    test('exposes the new fields without reaching into .error', () {
      final ex = SyncNativeException(
        SyncNativeError.fromMap({
          'code': 'ATTESTATION_UNAVAILABLE',
          'message': 'm',
          'retryable': false,
          'reason': 'unsupported',
          'detail': {'phase': 'attestation'},
        }),
      );

      expect(ex.reason, 'unsupported');
      expect(ex.isUnsupported, isTrue);
      expect(ex.detail?['phase'], 'attestation');
      expect(ex.toString(), contains('unsupported'));
    });
  });
}
