import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/modules/cloud/upload_queue.dart';

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
      await queue.enqueue(_mockHsiJson(1));
      await queue.enqueue(_mockHsiJson(2));
      await queue.enqueue(_mockHsiJson(3));

      expect(queue.length, equals(3));
      expect(queue.hasItems, isTrue);
    });

    test('evicts oldest when exceeding max size (FIFO)', () async {
      await queue.enqueue(_mockHsiJson(1));
      await queue.enqueue(_mockHsiJson(2));
      await queue.enqueue(_mockHsiJson(3));
      await queue.enqueue(_mockHsiJson(4)); // Should evict item 1

      expect(queue.length, equals(3));

      final batch = queue.dequeueBatch(3);
      expect(_extractTs(batch.first), equals(2));
      expect(_extractTs(batch.last), equals(4));
    });

    test('dequeues batch correctly', () async {
      await queue.enqueue(_mockHsiJson(1));
      await queue.enqueue(_mockHsiJson(2));

      final batch = queue.dequeueBatch(1);
      expect(batch.length, equals(1));
      expect(_extractTs(batch.first), equals(1));

      // Queue should still have both items until confirmBatch
      expect(queue.length, equals(2));
    });

    test('dequeues all items when batch size exceeds queue length', () async {
      await queue.enqueue(_mockHsiJson(1));

      final batch = queue.dequeueBatch(10);
      expect(batch.length, equals(1));
    });

    test('returns empty list when queue is empty', () {
      final batch = queue.dequeueBatch(5);
      expect(batch, isEmpty);
      expect(queue.hasItems, isFalse);
    });

    test('confirmBatch removes items from queue', () async {
      await queue.enqueue(_mockHsiJson(1));
      await queue.enqueue(_mockHsiJson(2));

      final batch = queue.dequeueBatch(1);
      queue.confirmBatch(batch);

      expect(queue.length, equals(1));

      final nextBatch = queue.dequeueBatch(1);
      expect(_extractTs(nextBatch.first), equals(2));
    });

    test('requeueBatch keeps items in queue', () async {
      await queue.enqueue(_mockHsiJson(1));

      final batch = queue.dequeueBatch(1);
      await queue.requeueBatch(batch);

      expect(queue.length, equals(1));

      final nextBatch = queue.dequeueBatch(1);
      expect(_extractTs(nextBatch.first), equals(1));
    });

    test('clear removes all items', () async {
      await queue.enqueue(_mockHsiJson(1));
      await queue.enqueue(_mockHsiJson(2));

      await queue.clear();

      expect(queue.length, equals(0));
      expect(queue.hasItems, isFalse);
    });
  });
}

String _mockHsiJson(int timestamp) {
  return jsonEncode({
    'hsi_version': '1.1',
    'observed_at_utc': '2024-01-01T00:00:00Z',
    'timestamp': timestamp,
  });
}

int _extractTs(String json) {
  return (jsonDecode(json) as Map<String, dynamic>)['timestamp'] as int;
}
