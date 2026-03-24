import '../../models/canonical_wearable_event.dart';
import '../../storage/storage_manager.dart';
import '../runtime/runtime_bridge.dart';

class LongitudinalSrmModule {
  static const _eventDimensionMap = <String, List<_DimensionExtractor>>{
    'sleep.summary.recorded': [
      _DimensionExtractor('sleep_need', 'duration_seconds'),
      _DimensionExtractor('sleep_regularity', 'midpoint_time'),
    ],
    'hrv.recorded': [
      _DimensionExtractor('hrv_rmssd', 'rmssd_ms'),
    ],
    'heart_rate.resting.recorded': [
      _DimensionExtractor('resting_hr', 'bpm'),
    ],
    'recovery.summary.recorded': [
      _DimensionExtractor('recovery_score', 'score'),
    ],
  };

  Future<void> ingestEvent(
    CanonicalWearableEvent event,
    StorageManager storage,
    RuntimeBridge? bridge,
  ) async {
    final extractors = _eventDimensionMap[event.type];
    if (extractors == null || bridge == null) return;

    final dayIndex = event.observedAt.millisecondsSinceEpoch ~/ 86400000;

    for (final extractor in extractors) {
      final rawValue = event.payload[extractor.payloadKey];
      if (rawValue == null) continue;

      final value = (rawValue is num) ? rawValue.toDouble() : double.tryParse(rawValue.toString());
      if (value == null) continue;

      bridge.pushWearableDailyValue(
        extractor.dimension,
        dayIndex,
        value,
        event.confidence,
        _fidelityToInt(event.sourceFidelity),
      );
    }

    final todayDayIndex = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
    bridge.triggerWearableRecompute(0, todayDayIndex);
  }

  String? getWearableReference(RuntimeBridge? bridge) {
    return bridge?.getWearableReference();
  }

  static int _fidelityToInt(String fidelity) {
    switch (fidelity) {
      case 'raw':
        return 0;
      case 'derived':
        return 1;
      case 'estimated':
        return 2;
      default:
        return 2;
    }
  }
}

class _DimensionExtractor {
  final String dimension;
  final String payloadKey;

  const _DimensionExtractor(this.dimension, this.payloadKey);
}
