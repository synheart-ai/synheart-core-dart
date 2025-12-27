// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'behavior.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BehaviorState _$BehaviorStateFromJson(Map<String, dynamic> json) =>
    BehaviorState(
      typingCadence: (json['typingCadence'] as num).toDouble(),
      typingBurstiness: (json['typingBurstiness'] as num).toDouble(),
      scrollVelocity: (json['scrollVelocity'] as num).toDouble(),
      idleGaps: (json['idleGaps'] as num).toDouble(),
      appSwitchRate: (json['appSwitchRate'] as num).toDouble(),
    );

Map<String, dynamic> _$BehaviorStateToJson(BehaviorState instance) =>
    <String, dynamic>{
      'typingCadence': instance.typingCadence,
      'typingBurstiness': instance.typingBurstiness,
      'scrollVelocity': instance.scrollVelocity,
      'idleGaps': instance.idleGaps,
      'appSwitchRate': instance.appSwitchRate,
    };
