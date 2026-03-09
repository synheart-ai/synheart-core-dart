/// Context information from adapters
class ContextState {
  final ConversationContext? conversation;
  final DeviceStateContext? device;
  final UserPatternsContext? userPatterns;

  ContextState({this.conversation, this.device, this.userPatterns});

  factory ContextState.fromJson(Map<String, dynamic> json) => ContextState(
        conversation: json['conversation'] is Map
            ? ConversationContext.fromJson(
                json['conversation'] as Map<String, dynamic>)
            : null,
        device: json['device'] is Map
            ? DeviceStateContext.fromJson(
                json['device'] as Map<String, dynamic>)
            : null,
        userPatterns: json['userPatterns'] is Map
            ? UserPatternsContext.fromJson(
                json['userPatterns'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
        if (conversation != null) 'conversation': conversation!.toJson(),
        if (device != null) 'device': device!.toJson(),
        if (userPatterns != null) 'userPatterns': userPatterns!.toJson(),
      };
}

class ConversationContext {
  final bool isActive;
  final double? avgReplyDelaySec;
  final int? messageCount;
  final double? burstiness;

  ConversationContext({
    this.isActive = false,
    this.avgReplyDelaySec,
    this.messageCount,
    this.burstiness,
  });

  factory ConversationContext.fromJson(Map<String, dynamic> json) =>
      ConversationContext(
        isActive: json['isActive'] as bool? ?? false,
        avgReplyDelaySec:
            (json['avgReplyDelaySec'] as num?)?.toDouble(),
        messageCount: json['messageCount'] as int?,
        burstiness: (json['burstiness'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'isActive': isActive,
        if (avgReplyDelaySec != null) 'avgReplyDelaySec': avgReplyDelaySec,
        if (messageCount != null) 'messageCount': messageCount,
        if (burstiness != null) 'burstiness': burstiness,
      };
}

class DeviceStateContext {
  final bool screenOn;
  final bool isCharging;
  final double? batteryLevel;
  final String? networkType;
  final String? focusMode;

  DeviceStateContext({
    this.screenOn = true,
    this.isCharging = false,
    this.batteryLevel,
    this.networkType,
    this.focusMode,
  });

  factory DeviceStateContext.fromJson(Map<String, dynamic> json) =>
      DeviceStateContext(
        screenOn: json['screenOn'] as bool? ?? true,
        isCharging: json['isCharging'] as bool? ?? false,
        batteryLevel: (json['batteryLevel'] as num?)?.toDouble(),
        networkType: json['networkType'] as String?,
        focusMode: json['focusMode'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'screenOn': screenOn,
        'isCharging': isCharging,
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
        if (networkType != null) 'networkType': networkType,
        if (focusMode != null) 'focusMode': focusMode,
      };
}

class UserPatternsContext {
  final double timeOfDay;
  final int dayOfWeek;
  final double? avgSessionMinutes;
  final String? activityPattern;

  UserPatternsContext({
    this.timeOfDay = 0.0,
    this.dayOfWeek = 0,
    this.avgSessionMinutes,
    this.activityPattern,
  });

  factory UserPatternsContext.fromJson(Map<String, dynamic> json) =>
      UserPatternsContext(
        timeOfDay: (json['timeOfDay'] as num?)?.toDouble() ?? 0.0,
        dayOfWeek: json['dayOfWeek'] as int? ?? 0,
        avgSessionMinutes:
            (json['avgSessionMinutes'] as num?)?.toDouble(),
        activityPattern: json['activityPattern'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'timeOfDay': timeOfDay,
        'dayOfWeek': dayOfWeek,
        if (avgSessionMinutes != null) 'avgSessionMinutes': avgSessionMinutes,
        if (activityPattern != null) 'activityPattern': activityPattern,
      };
}
