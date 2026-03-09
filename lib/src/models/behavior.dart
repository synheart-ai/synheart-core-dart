/// Behavioral metrics from Phone SDK + HSI processing
class BehaviorState {
  final double typingSpeed;
  final double typingBurstiness;
  final double scrollVelocity;
  final double idleGaps;
  final double appSwitchRate;
  final double interactionIntensity;
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

  factory BehaviorState.fromJson(Map<String, dynamic> json) => BehaviorState(
        typingSpeed: (json['typingSpeed'] as num?)?.toDouble() ?? 0.0,
        typingBurstiness:
            (json['typingBurstiness'] as num?)?.toDouble() ?? 0.0,
        scrollVelocity: (json['scrollVelocity'] as num?)?.toDouble() ?? 0.0,
        idleGaps: (json['idleGaps'] as num?)?.toDouble() ?? 0.0,
        appSwitchRate: (json['appSwitchRate'] as num?)?.toDouble() ?? 0.0,
        interactionIntensity:
            (json['interactionIntensity'] as num?)?.toDouble() ?? 0.0,
        engagementLevel:
            (json['engagementLevel'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'typingSpeed': typingSpeed,
        'typingBurstiness': typingBurstiness,
        'scrollVelocity': scrollVelocity,
        'idleGaps': idleGaps,
        'appSwitchRate': appSwitchRate,
        'interactionIntensity': interactionIntensity,
        'engagementLevel': engagementLevel,
      };
}
