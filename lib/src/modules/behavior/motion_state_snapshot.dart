import 'dart:convert';

import '../../core/logger.dart';

/// Coarse motion / posture class (per the motion-state spec).
///
/// `unknown` is emitted by the runtime when required features are missing.
enum MotionStateClass { laying, sitting, standing, moving, unknown }

/// Snapshot of the runtime's most recent motion-state inference, parsed from
/// the `axes.behavior` axis of an HSI 1.2 snapshot.
class MotionStateSnapshot {
  final MotionStateClass value;
  final double confidence;
  final int? windowStartMs;
  final int? windowEndMs;

  const MotionStateSnapshot({
    required this.value,
    required this.confidence,
    this.windowStartMs,
    this.windowEndMs,
  });

  static MotionStateClass _parseClass(String? s) {
    switch (s) {
      case 'LAYING':
        return MotionStateClass.laying;
      case 'SITTING':
        return MotionStateClass.sitting;
      case 'STANDING':
        return MotionStateClass.standing;
      case 'MOVING':
        return MotionStateClass.moving;
      case 'UNKNOWN':
      case null:
        return MotionStateClass.unknown;
      default:
        return MotionStateClass.unknown;
    }
  }

  /// Walk an HSI 1.2 JSON snapshot and pull out the motion-state axis if
  /// present. Returns `null` when the snapshot has no `motion_state` reading.
  ///
  /// The runtime emits MotionState as a HSV with `notes` carrying the canonical
  /// string ("LAYING" | "SITTING" | ..). The engine maps that into
  /// `axes.behavior[*]` with `name == "motion_state"`.
  static MotionStateSnapshot? parseFromHsiJson(String hsiJson) {
    try {
      final root = json.decode(hsiJson);
      if (root is! Map) return null;
      final axes = root['axes'];
      if (axes is! Map) return null;
      final behavior = axes['behavior'];
      if (behavior is! List) return null;
      for (final reading in behavior) {
        if (reading is! Map) continue;
        final name = reading['name'];
        if (name != 'motion_state') continue;
        final notes = reading['notes'];
        final classStr = notes is String ? notes : null;
        final conf =
            (reading['score'] as num?)?.toDouble() ??
            (reading['confidence'] as num?)?.toDouble() ??
            0.0;
        final winStart = (reading['window_start_ms'] as num?)?.toInt();
        final winEnd = (reading['window_end_ms'] as num?)?.toInt();
        return MotionStateSnapshot(
          value: _parseClass(classStr),
          confidence: conf,
          windowStartMs: winStart,
          windowEndMs: winEnd,
        );
      }
      return null;
    } catch (e, st) {
      SynheartLogger.log(
        '[MotionStateSnapshot] parse error: $e',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  @override
  String toString() =>
      'MotionStateSnapshot(value=$value, confidence=$confidence)';
}
