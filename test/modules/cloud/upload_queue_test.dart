import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/modules/cloud/upload_queue.dart';
import 'package:synheart_core/synheart_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UploadQueue', () {
    late UploadQueue queue;

    setUp(() {
      queue = UploadQueue(maxSize: 3);
    });

    tearDown(() async {
      await queue.clear();
    });

    test('enqueues items up to max size', () async {
      final hsv1 = _createMockHSV(1);
      final hsv2 = _createMockHSV(2);
      final hsv3 = _createMockHSV(3);

      await queue.enqueue(hsv1);
      await queue.enqueue(hsv2);
      await queue.enqueue(hsv3);

      expect(queue.length, equals(3));
      expect(queue.hasItems, isTrue);
    });

    test('evicts oldest when exceeding max size (FIFO)', () async {
      final hsv1 = _createMockHSV(1);
      final hsv2 = _createMockHSV(2);
      final hsv3 = _createMockHSV(3);
      final hsv4 = _createMockHSV(4);

      await queue.enqueue(hsv1);
      await queue.enqueue(hsv2);
      await queue.enqueue(hsv3);
      await queue.enqueue(hsv4); // Should evict hsv1

      expect(queue.length, equals(3));

      final batch = queue.dequeueBatch(3);
      expect(batch.first.timestamp, equals(2)); // hsv2 should be first now
      expect(batch.last.timestamp, equals(4)); // hsv4 should be last
    });

    test('dequeues batch correctly', () async {
      final hsv1 = _createMockHSV(1);
      final hsv2 = _createMockHSV(2);

      await queue.enqueue(hsv1);
      await queue.enqueue(hsv2);

      final batch = queue.dequeueBatch(1);
      expect(batch.length, equals(1));
      expect(batch.first.timestamp, equals(1));

      // Queue should still have both items until confirmBatch
      expect(queue.length, equals(2));
    });

    test('dequeues all items when batch size exceeds queue length', () async {
      final hsv1 = _createMockHSV(1);
      await queue.enqueue(hsv1);

      final batch = queue.dequeueBatch(10);
      expect(batch.length, equals(1));
    });

    test('returns empty list when queue is empty', () {
      final batch = queue.dequeueBatch(5);
      expect(batch, isEmpty);
      expect(queue.hasItems, isFalse);
    });

    test('confirmBatch removes items from queue', () async {
      final hsv1 = _createMockHSV(1);
      final hsv2 = _createMockHSV(2);

      await queue.enqueue(hsv1);
      await queue.enqueue(hsv2);

      final batch = queue.dequeueBatch(1);
      queue.confirmBatch(batch);

      expect(queue.length, equals(1));

      // Next batch should be hsv2
      final nextBatch = queue.dequeueBatch(1);
      expect(nextBatch.first.timestamp, equals(2));
    });

    test('requeueBatch keeps items in queue', () async {
      final hsv1 = _createMockHSV(1);
      await queue.enqueue(hsv1);

      final batch = queue.dequeueBatch(1);
      await queue.requeueBatch(batch);

      // Items should still be in queue
      expect(queue.length, equals(1));

      final nextBatch = queue.dequeueBatch(1);
      expect(nextBatch.first.timestamp, equals(1));
    });

    test('clear removes all items', () async {
      final hsv1 = _createMockHSV(1);
      final hsv2 = _createMockHSV(2);

      await queue.enqueue(hsv1);
      await queue.enqueue(hsv2);

      await queue.clear();

      expect(queue.length, equals(0));
      expect(queue.hasItems, isFalse);
    });
  });
}

HumanStateVector _createMockHSV(int timestamp) {
  return HumanStateVector.base(
    timestamp: timestamp,
    behavior: BehaviorState(
      typingCadence: 0.5,
      typingBurstiness: 0.3,
      scrollVelocity: 0.4,
      idleGaps: 2.0,
      appSwitchRate: 0.1,
    ),
    context: ContextState(
      overload: 0.3,
      frustration: 0.2,
      engagement: 0.7,
      conversation: ConversationContext(
        avgReplyDelaySec: 5.0,
        burstiness: 0.4,
        interruptRate: 0.2,
      ),
      deviceState: DeviceStateContext(foreground: true, screenOn: true),
      userPatterns: UserPatternsContext(
        morningFocusBias: 0.6,
        avgSessionMinutes: 45.0,
        baselineTypingCadence: 0.5,
      ),
    ),
    meta: MetaState(
      sessionId: 'test',
      device: DeviceInfo(platform: 'test'),
      samplingRateHz: 1.0,
      embedding: StateEmbedding(
        vector: List.filled(64, 0.0),
        timestamp: timestamp,
        windowType: 'micro',
      ),
      axes: HSIAxes.empty(),
    ),
  );
}
