import 'package:json_annotation/json_annotation.dart';

part 'behavior.g.dart';

/// Behavioral metrics from Phone SDK + HSI processing
@JsonSerializable()
class BehaviorState {
  /// Typing cadence (normalized 0.0 - 1.0)
  final double typingCadence;

  /// Typing burstiness (0.0 - 1.0)
  final double typingBurstiness;

  /// Scroll velocity (normalized 0.0 - 1.0)
  final double scrollVelocity;

  /// Idle gaps between interactions (seconds)
  final double idleGaps;

  /// App switch rate (switches per minute)
  final double appSwitchRate;

  BehaviorState({
    required this.typingCadence,
    required this.typingBurstiness,
    required this.scrollVelocity,
    required this.idleGaps,
    required this.appSwitchRate,
  });

  factory BehaviorState.fromJson(Map<String, dynamic> json) =>
      _$BehaviorStateFromJson(json);

  Map<String, dynamic> toJson() => _$BehaviorStateToJson(this);
}
