// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'behavior.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BehaviorState _$BehaviorStateFromJson(Map<String, dynamic> json) =>
    BehaviorState(
      typingSpeed: (json['typingSpeed'] as num?)?.toDouble() ?? 0.0,
      typingBurstiness: (json['typingBurstiness'] as num?)?.toDouble() ?? 0.0,
      scrollVelocity: (json['scrollVelocity'] as num?)?.toDouble() ?? 0.0,
      idleGaps: (json['idleGaps'] as num?)?.toDouble() ?? 0.0,
      appSwitchRate: (json['appSwitchRate'] as num?)?.toDouble() ?? 0.0,
      interactionIntensity: (json['interactionIntensity'] as num?)?.toDouble() ?? 0.0,
      engagementLevel: (json['engagementLevel'] as num?)?.toDouble() ?? 0.0,
    );

Map<String, dynamic> _$BehaviorStateToJson(BehaviorState instance) =>
    <String, dynamic>{
      'typingSpeed': instance.typingSpeed,
      'typingBurstiness': instance.typingBurstiness,
      'scrollVelocity': instance.scrollVelocity,
      'idleGaps': instance.idleGaps,
      'appSwitchRate': instance.appSwitchRate,
      'interactionIntensity': instance.interactionIntensity,
      'engagementLevel': instance.engagementLevel,
    };
