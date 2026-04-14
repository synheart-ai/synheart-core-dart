import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/modules/interfaces/consent_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HSI Consent Gating', () {
    test('HSI frames are NOT emitted when biosignals consent is false', () async {
      // The consent gate is in Synheart._hsvSubscription where it checks
      // _consentModule?.current().biosignals before forwarding to _hsvStream.
      //
      // We verify the gating logic in isolation: when consent.biosignals is
      // false, HSI JSON should be filtered out.

      final consent = ConsentSnapshot(
        biosignals: false,
        behavior: true,
        phoneContext: true,
        cloudUpload: false,
        timestamp: DateTime.now(),
      );

      // Simulate the consent gate logic from synheart.dart:
      //   if (consent == null || !consent.biosignals) return;
      final hsiValues = <String>[];
      final sourceStream = StreamController<String>();
      final gatedStream = StreamController<String>();

      sourceStream.stream.listen((hsiJson) {
        if (!consent.biosignals) return;
        gatedStream.add(hsiJson);
      });

      gatedStream.stream.listen(hsiValues.add);

      // Emit a frame while consent is denied
      sourceStream.add('{"hsi_version":"1.0","frame":1}');
      await Future.delayed(Duration(milliseconds: 50));

      expect(hsiValues, isEmpty,
          reason: 'HSI frames should not be emitted when biosignals consent is false');

      await sourceStream.close();
      await gatedStream.close();
    });

    test('HSI frames ARE emitted when biosignals consent is true', () async {
      final consent = ConsentSnapshot(
        biosignals: true,
        behavior: true,
        phoneContext: true,
        cloudUpload: false,
        timestamp: DateTime.now(),
      );

      final hsiValues = <String>[];
      final sourceStream = StreamController<String>();
      final gatedStream = StreamController<String>();

      sourceStream.stream.listen((hsiJson) {
        if (!consent.biosignals) return;
        gatedStream.add(hsiJson);
      });

      gatedStream.stream.listen(hsiValues.add);

      sourceStream.add('{"hsi_version":"1.0","frame":1}');
      await Future.delayed(Duration(milliseconds: 50));

      expect(hsiValues.length, equals(1),
          reason: 'HSI frames should be emitted when biosignals consent is true');
      expect(hsiValues.first, contains('frame'));

      await sourceStream.close();
      await gatedStream.close();
    });

    test('Consent gate blocks all frames with none() consent', () async {
      final consent = ConsentSnapshot.none();

      final hsiValues = <String>[];
      final sourceStream = StreamController<String>();
      final gatedStream = StreamController<String>();

      sourceStream.stream.listen((hsiJson) {
        if (!consent.biosignals) return;
        gatedStream.add(hsiJson);
      });

      gatedStream.stream.listen(hsiValues.add);

      sourceStream.add('{"frame":1}');
      sourceStream.add('{"frame":2}');
      sourceStream.add('{"frame":3}');
      await Future.delayed(Duration(milliseconds: 50));

      expect(hsiValues, isEmpty,
          reason: 'No frames should pass when consent is none()');

      await sourceStream.close();
      await gatedStream.close();
    });
  });
}
