// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'emotion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EmotionState _$EmotionStateFromJson(Map<String, dynamic> json) => EmotionState(
      stress: (json['stress'] as num).toDouble(),
      calm: (json['calm'] as num).toDouble(),
      engagement: (json['engagement'] as num).toDouble(),
      activation: (json['activation'] as num).toDouble(),
      valence: (json['valence'] as num).toDouble(),
    );

Map<String, dynamic> _$EmotionStateToJson(EmotionState instance) =>
    <String, dynamic>{
      'stress': instance.stress,
      'calm': instance.calm,
      'engagement': instance.engagement,
      'activation': instance.activation,
      'valence': instance.valence,
    };
