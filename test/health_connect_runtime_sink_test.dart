// SPDX-License-Identifier: Apache-2.0
//
// Unit tests for `HealthConnectRuntimeSink`'s public contract.
//
// We can't drive the underlying `HealthAdapter` (it talks to a real
// Health Connect plugin), so these tests exercise the parts of the
// sink that don't need the platform: skip-on-iOS, skip-on-bad-input,
// and (where injectable) the daily-push contract via the same
// `PushDailyCallback` shape `AppleHealthRuntimeSink` uses.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  group('HealthConnectRuntimeSink', () {
    test('iOS short-circuits with skip + reason', () async {
      // The real `Platform.isAndroid` is what gates the read; we
      // can't override it without reaching into TestPlatform shims.
      // Instead, only assert the iOS branch on actual iOS test runs
      // (CI matrix runs both). On non-iOS platforms this test skips.
      if (!Platform.isIOS) return;
      final sink = HealthConnectRuntimeSink();
      final r = await sink.backfill();
      expect(r.skipped, isTrue);
      expect(r.skipReason, contains('Android-only'));
      expect(r.daysIngested, 0);
      expect(r.dimensionsPushed, 0);
    });

    test('rejects non-positive daysBack', () async {
      // This branch fires before any platform check, so it works
      // anywhere the test runner runs.
      final sink = HealthConnectRuntimeSink();
      final r0 = await sink.backfill(daysBack: 0);
      final rNeg = await sink.backfill(daysBack: -5);

      // On non-Android we hit the platform check first; only
      // assert the rejection branch on Android runs. On other
      // platforms we just confirm `skipped == true` either way.
      expect(r0.skipped, isTrue);
      expect(rNeg.skipped, isTrue);

      if (Platform.isAndroid) {
        expect(r0.skipReason, contains('positive'));
        expect(rNeg.skipReason, contains('positive'));
      }
    });

    test('result fields wire through cleanly when skipped', () async {
      // Regardless of platform, `skipped == true` always carries a
      // non-null reason and zero counters. Ensures we don't ship
      // confusing partial-success metadata.
      final sink = HealthConnectRuntimeSink();
      final r = await sink.backfill(daysBack: 365);
      if (r.skipped) {
        expect(r.skipReason, isNotNull);
        expect(r.daysIngested, 0);
        expect(r.dimensionsPushed, 0);
      }
      expect(r.requestedDaysBack, 365);
      expect(r.durationMs, greaterThanOrEqualTo(0));
    });
  });
}
