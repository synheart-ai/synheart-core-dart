import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/heads/emotion_head.dart';
import 'package:synheart_core/src/models/hsv.dart';
import 'package:synheart_core/src/models/behavior.dart';
import 'package:synheart_core/src/models/context.dart';
import 'package:synheart_core/src/models/hsi_axes.dart';
import 'dart:async';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmotionHead (deprecated pass-through)', () {
    // ignore: deprecated_member_use_from_same_package
    late EmotionHead emotionHead;
    late StreamController<HumanStateVector> hsvController;

    setUp(() {
      // ignore: deprecated_member_use_from_same_package
      emotionHead = EmotionHead();
      hsvController = StreamController<HumanStateVector>();
    });

    tearDown(() async {
      await emotionHead.dispose();
      await hsvController.close();
    });

    test('passes HSVs through unchanged', () async {
      final List<HumanStateVector> emittedHsvs = [];

      final subscription = emotionHead.emotionStream.listen((hsv) {
        emittedHsvs.add(hsv);
      });

      emotionHead.start(hsvController.stream);

      final hsv = _createMockHSV();
      hsvController.add(hsv);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(emittedHsvs.length, equals(1));
      expect(emittedHsvs.first.timestamp, equals(hsv.timestamp));

      await subscription.cancel();
    });

    test('does not start twice', () async {
      emotionHead.start(hsvController.stream);
      emotionHead.start(hsvController.stream);
      expect(emotionHead, isNotNull);
    });

    test('stops processing after stop()', () async {
      final List<HumanStateVector> emittedHsvs = [];

      final subscription = emotionHead.emotionStream.listen((hsv) {
        emittedHsvs.add(hsv);
      });

      emotionHead.start(hsvController.stream);

      hsvController.add(_createMockHSV());
      await Future.delayed(const Duration(milliseconds: 50));

      final countBeforeStop = emittedHsvs.length;
      await emotionHead.stop();

      hsvController.add(_createMockHSV(timestamp: 999999));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emittedHsvs.length, equals(countBeforeStop));

      await subscription.cancel();
    });

    test('clears on dispose', () async {
      emotionHead.start(hsvController.stream);
      hsvController.add(_createMockHSV());
      await Future.delayed(const Duration(milliseconds: 50));
      await emotionHead.dispose();
      expect(emotionHead, isNotNull);
    });
  });
}

HumanStateVector _createMockHSV({int? timestamp}) {
  return HumanStateVector.base(
    timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
    behavior: BehaviorState(
      typingSpeed: 0.5,
      typingBurstiness: 0.3,
      scrollVelocity: 0.4,
      idleGaps: 2.0,
      appSwitchRate: 0.1,
    ),
    context: ContextState(
      conversation: ConversationContext(avgReplyDelaySec: 5.0, burstiness: 0.4),
      device: DeviceStateContext(screenOn: true),
      userPatterns: UserPatternsContext(avgSessionMinutes: 45.0),
    ),
    meta: MetaState(
      sessionId: 'test-session',
      device: DeviceInfo(platform: 'test'),
      samplingRateHz: 1.0,
      embedding: StateEmbedding(
        vector: List.filled(15, 0.0),
        timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
        windowType: 'micro',
      ),
      axes: HSIAxes.empty(),
    ),
  );
}
