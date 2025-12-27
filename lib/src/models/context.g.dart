// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'context.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ContextState _$ContextStateFromJson(Map<String, dynamic> json) => ContextState(
  overload: (json['overload'] as num).toDouble(),
  frustration: (json['frustration'] as num).toDouble(),
  engagement: (json['engagement'] as num).toDouble(),
  conversation: ConversationContext.fromJson(
    json['conversation'] as Map<String, dynamic>,
  ),
  deviceState: DeviceStateContext.fromJson(
    json['deviceState'] as Map<String, dynamic>,
  ),
  userPatterns: UserPatternsContext.fromJson(
    json['userPatterns'] as Map<String, dynamic>,
  ),
);

Map<String, dynamic> _$ContextStateToJson(ContextState instance) =>
    <String, dynamic>{
      'overload': instance.overload,
      'frustration': instance.frustration,
      'engagement': instance.engagement,
      'conversation': instance.conversation,
      'deviceState': instance.deviceState,
      'userPatterns': instance.userPatterns,
    };

ConversationContext _$ConversationContextFromJson(Map<String, dynamic> json) =>
    ConversationContext(
      avgReplyDelaySec: (json['avgReplyDelaySec'] as num).toDouble(),
      burstiness: (json['burstiness'] as num).toDouble(),
      interruptRate: (json['interruptRate'] as num).toDouble(),
    );

Map<String, dynamic> _$ConversationContextToJson(
  ConversationContext instance,
) => <String, dynamic>{
  'avgReplyDelaySec': instance.avgReplyDelaySec,
  'burstiness': instance.burstiness,
  'interruptRate': instance.interruptRate,
};

DeviceStateContext _$DeviceStateContextFromJson(Map<String, dynamic> json) =>
    DeviceStateContext(
      foreground: json['foreground'] as bool,
      screenOn: json['screenOn'] as bool,
      focusMode: json['focusMode'] as String?,
    );

Map<String, dynamic> _$DeviceStateContextToJson(DeviceStateContext instance) =>
    <String, dynamic>{
      'foreground': instance.foreground,
      'screenOn': instance.screenOn,
      'focusMode': instance.focusMode,
    };

UserPatternsContext _$UserPatternsContextFromJson(Map<String, dynamic> json) =>
    UserPatternsContext(
      morningFocusBias: (json['morningFocusBias'] as num).toDouble(),
      avgSessionMinutes: (json['avgSessionMinutes'] as num).toDouble(),
      baselineTypingCadence: (json['baselineTypingCadence'] as num).toDouble(),
    );

Map<String, dynamic> _$UserPatternsContextToJson(
  UserPatternsContext instance,
) => <String, dynamic>{
  'morningFocusBias': instance.morningFocusBias,
  'avgSessionMinutes': instance.avgSessionMinutes,
  'baselineTypingCadence': instance.baselineTypingCadence,
};
