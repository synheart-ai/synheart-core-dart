import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:example/sdk/synheart_controller.dart';

/// Android and iOS are separate platform apps with separate `app_…` ids,
/// because attestation is per-store. A single shared id cannot be bound to
/// both, so the wrong one reaching the wrong platform fails attestation.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('falls back to the bundle id when no credential is supplied', () {
    // No dart-defines in a plain `flutter test` run. validate() rejects an
    // empty appId, so the fallback is what keeps a credential-free run working.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(SynheartController.appId, 'ai.synheart.core.example');
  });

  test('resolves per platform without throwing on desktop hosts', () {
    for (final p in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      expect(SynheartController.appId, isNotEmpty, reason: 'platform $p');
    }
  });
}
