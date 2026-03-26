import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/logger.dart';

class UploadQueue {
  final int maxSize;
  final FlutterSecureStorage? _storage;
  final List<String> _queue = [];

  static const String _storageKey = 'synheart_upload_queue';

  UploadQueue({required this.maxSize, FlutterSecureStorage? storage})
    : _storage = storage;

  bool get hasItems => _queue.isNotEmpty;
  int get length => _queue.length;

  /// Load queue from persistent storage
  Future<void> loadFromStorage() async {
    final storage = _storage;
    if (storage == null) return;

    try {
      final jsonString = await storage.read(key: _storageKey);
      if (jsonString == null || jsonString.isEmpty) return;

      final List<dynamic> json = jsonDecode(jsonString);
      _queue.addAll(json.cast<String>());
    } catch (e) {
      SynheartLogger.log(
        '[UploadQueue] Failed to load from storage: $e',
        error: e,
      );
    }
  }

  /// Persist queue to storage
  Future<void> persistToStorage() async {
    final storage = _storage;
    if (storage == null) return;

    try {
      await storage.write(key: _storageKey, value: jsonEncode(_queue));
    } catch (e) {
      SynheartLogger.log(
        '[UploadQueue] Failed to persist to storage: $e',
        error: e,
      );
    }
  }

  /// Enqueue a new HSI JSON string
  Future<void> enqueue(String hsiJson) async {
    _queue.add(hsiJson);

    // Enforce max size (FIFO eviction)
    if (_queue.length > maxSize) {
      _queue.removeAt(0);
    }

    await persistToStorage();
  }

  /// Dequeue a batch of snapshots
  List<String> dequeueBatch(int batchSize) {
    if (_queue.isEmpty) return [];

    final count = _queue.length < batchSize ? _queue.length : batchSize;
    return _queue.take(count).toList();
  }

  /// Confirm batch was successfully uploaded (remove from queue)
  Future<void> confirmBatch(List<String> batch) async {
    final removeCount = batch.length.clamp(0, _queue.length);
    _queue.removeRange(0, removeCount);
    await persistToStorage();
  }

  /// Re-enqueue batch on failure
  Future<void> requeueBatch(List<String> batch) async {
    // Batch is still at the front of queue - no action needed
    // Just persist to ensure it's saved
    await persistToStorage();
  }

  /// Clear entire queue
  Future<void> clear() async {
    _queue.clear();
    final storage = _storage;
    if (storage == null) return;
    await storage.delete(key: _storageKey);
  }
}
