// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'context.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ContextState _$ContextStateFromJson(Map<String, dynamic> json) => ContextState(
  conversation: json['conversation'] == null
      ? null
      : ConversationContext.fromJson(
          json['conversation'] as Map<String, dynamic>,
        ),
  device: json['device'] == null
      ? null
      : DeviceStateContext.fromJson(
          json['device'] as Map<String, dynamic>,
        ),
  userPatterns: json['userPatterns'] == null
      ? null
      : UserPatternsContext.fromJson(
          json['userPatterns'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$ContextStateToJson(ContextState instance) =>
    <String, dynamic>{
      'conversation': instance.conversation?.toJson(),
      'device': instance.device?.toJson(),
      'userPatterns': instance.userPatterns?.toJson(),
    };

ConversationContext _$ConversationContextFromJson(Map<String, dynamic> json) =>
    ConversationContext(
      isActive: json['isActive'] as bool? ?? false,
      avgReplyDelaySec: (json['avgReplyDelaySec'] as num?)?.toDouble(),
      messageCount: (json['messageCount'] as num?)?.toInt(),
      burstiness: (json['burstiness'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$ConversationContextToJson(
  ConversationContext instance,
) => <String, dynamic>{
  'isActive': instance.isActive,
  'avgReplyDelaySec': instance.avgReplyDelaySec,
  'messageCount': instance.messageCount,
  'burstiness': instance.burstiness,
};

DeviceStateContext _$DeviceStateContextFromJson(Map<String, dynamic> json) =>
    DeviceStateContext(
      screenOn: json['screenOn'] as bool? ?? true,
      isCharging: json['isCharging'] as bool? ?? false,
      batteryLevel: (json['batteryLevel'] as num?)?.toDouble(),
      networkType: json['networkType'] as String?,
      focusMode: json['focusMode'] as String?,
    );

Map<String, dynamic> _$DeviceStateContextToJson(DeviceStateContext instance) =>
    <String, dynamic>{
      'screenOn': instance.screenOn,
      'isCharging': instance.isCharging,
      'batteryLevel': instance.batteryLevel,
      'networkType': instance.networkType,
      'focusMode': instance.focusMode,
    };

UserPatternsContext _$UserPatternsContextFromJson(Map<String, dynamic> json) =>
    UserPatternsContext(
      timeOfDay: (json['timeOfDay'] as num?)?.toDouble() ?? 0.0,
      dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 0,
      avgSessionMinutes: (json['avgSessionMinutes'] as num?)?.toDouble(),
      activityPattern: json['activityPattern'] as String?,
    );

Map<String, dynamic> _$UserPatternsContextToJson(
  UserPatternsContext instance,
) => <String, dynamic>{
  'timeOfDay': instance.timeOfDay,
  'dayOfWeek': instance.dayOfWeek,
  'avgSessionMinutes': instance.avgSessionMinutes,
  'activityPattern': instance.activityPattern,
};
