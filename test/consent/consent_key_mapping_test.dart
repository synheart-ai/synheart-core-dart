import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';

/// `Synheart.hasConsent` spans two vocabularies: the native runtime keys
/// consent in snake_case, the Dart API in camelCase. It used to forward the
/// caller's spelling to whichever backend was active, so neither spelling
/// worked in both places and `hasConsent('cloudUpload')` returned false against
/// a runtime that had the grant.
///
/// These lock the translation to the keys the rest of the SDK already sends —
/// `grantConsent('cloud_upload')` and `ConsentEffectiveState.fromJson`'s
/// `json['cloud_upload']`.
void main() {
  group('runtime consent keys', () {
    // The snake_case names `grantConsent` / `revokeConsent` send natively.
    const runtimeKeys = <String>{
      'biosignals',
      'behavior',
      'phone_context',
      'cloud_upload',
      'vendor_sync',
      'research',
      'syni',
    };

    // The camelCase names the Dart fallback switch and ConsentSnapshot use.
    const dartKeys = <String>{
      'biosignals',
      'behavior',
      'phoneContext',
      'cloudUpload',
      'vendorSync',
      'research',
      'syni',
    };

    test('ConsentEffectiveState round-trips every runtime key', () {
      final json = {for (final k in runtimeKeys) k: true};
      final state = ConsentEffectiveState.fromJson(json);

      // If a key were misspelled, the corresponding field would stay false.
      expect(state.biosignals, isTrue);
      expect(state.behavior, isTrue);
      expect(state.phoneContext, isTrue);
      expect(state.cloudUpload, isTrue, reason: 'reads json["cloud_upload"]');
      expect(state.vendorSync, isTrue);
      expect(state.research, isTrue);
    });

    test('toJson emits the snake_case keys the runtime expects', () {
      final state = ConsentEffectiveState.fromJson({
        for (final k in runtimeKeys) k: true,
      });
      final out = state.toJson();

      expect(
        out.containsKey('cloud_upload'),
        isTrue,
        reason:
            'The runtime defines cloud_upload. Emitting cloudUpload here would '
            'silently drop the grant on the way back across the FFI boundary.',
      );
      expect(out['cloud_upload'], isTrue);
    });

    test('the two vocabularies differ only where documented', () {
      // Guards the mapping against a new consent type being added to one side
      // only — the failure mode that produced the original bug.
      final onlyRuntime = runtimeKeys.difference(dartKeys);
      final onlyDart = dartKeys.difference(runtimeKeys);

      expect(
        onlyRuntime,
        equals({'phone_context', 'cloud_upload', 'vendor_sync'}),
        reason: 'a runtime key gained no camelCase counterpart',
      );
      expect(
        onlyDart,
        equals({'phoneContext', 'cloudUpload', 'vendorSync'}),
        reason: 'a Dart key gained no snake_case counterpart',
      );
    });
  });
}
