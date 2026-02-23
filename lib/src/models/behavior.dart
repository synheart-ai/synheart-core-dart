import 'package:json_annotation/json_annotation.dart';

part 'behavior.g.dart';

/// Behavioral metrics from Phone SDK + HSI processing
@JsonSerializable()
class BehaviorState {
  /// Typing speed (normalized 0.0 - 1.0)
  final double typingSpeed;

  /// Typing burstiness (0.0 - 1.0)
  final double typingBurstiness;

  /// Scroll velocity (normalized 0.0 - 1.0)
  final double scrollVelocity;

  /// Idle gaps between interactions (seconds)
  final double idleGaps;

  /// App switch rate (switches per minute, normalized)
  final double appSwitchRate;

  /// Interaction intensity (normalized 0.0 - 1.0)
  final double interactionIntensity;

  /// Engagement level (normalized 0.0 - 1.0)
  final double engagementLevel;

  BehaviorState({
    this.typingSpeed = 0.0,
    this.typingBurstiness = 0.0,
    this.scrollVelocity = 0.0,
    this.idleGaps = 0.0,
    this.appSwitchRate = 0.0,
    this.interactionIntensity = 0.0,
    this.engagementLevel = 0.0,
  });

  factory BehaviorState.fromJson(Map<String, dynamic> json) =>
      _$BehaviorStateFromJson(json);

  Map<String, dynamic> toJson() => _$BehaviorStateToJson(this);
}
