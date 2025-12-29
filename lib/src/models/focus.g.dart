// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'focus.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FocusState _$FocusStateFromJson(Map<String, dynamic> json) => FocusState(
      score: (json['score'] as num).toDouble(),
      cognitiveLoad: (json['cognitiveLoad'] as num).toDouble(),
      clarity: (json['clarity'] as num).toDouble(),
      distraction: (json['distraction'] as num).toDouble(),
    );

Map<String, dynamic> _$FocusStateToJson(FocusState instance) =>
    <String, dynamic>{
      'score': instance.score,
      'cognitiveLoad': instance.cognitiveLoad,
      'clarity': instance.clarity,
      'distraction': instance.distraction,
    };
