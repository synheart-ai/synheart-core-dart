import 'package:json_annotation/json_annotation.dart';

part 'context.g.dart';

/// Context information from adapters
@JsonSerializable()
class ContextState {
  /// Conversation timing metrics
  final ConversationContext? conversation;

  /// Device state information
  final DeviceStateContext? device;

  /// User pattern information
  final UserPatternsContext? userPatterns;

  ContextState({
    this.conversation,
    this.device,
    this.userPatterns,
  });

  factory ContextState.fromJson(Map<String, dynamic> json) =>
      _$ContextStateFromJson(json);

  Map<String, dynamic> toJson() => _$ContextStateToJson(this);
}

/// Conversation timing context
@JsonSerializable()
class ConversationContext {
  /// Whether a conversation is currently active
  final bool isActive;

  /// Average reply delay in seconds
  final double? avgReplyDelaySec;

  /// Number of messages in conversation
  final int? messageCount;

  /// Burstiness of conversation (0.0 - 1.0)
  final double? burstiness;

  ConversationContext({
    this.isActive = false,
    this.avgReplyDelaySec,
    this.messageCount,
    this.burstiness,
  });

  factory ConversationContext.fromJson(Map<String, dynamic> json) =>
      _$ConversationContextFromJson(json);

  Map<String, dynamic> toJson() => _$ConversationContextToJson(this);
}

/// Device state context
@JsonSerializable()
class DeviceStateContext {
  /// Whether screen is on
  final bool screenOn;

  /// Whether device is charging
  final bool isCharging;

  /// Battery level (0.0 - 1.0)
  final double? batteryLevel;

  /// Network type (e.g., 'wifi', 'cellular')
  final String? networkType;

  /// Focus mode (e.g., 'work', 'personal', 'none')
  final String? focusMode;

  DeviceStateContext({
    this.screenOn = true,
    this.isCharging = false,
    this.batteryLevel,
    this.networkType,
    this.focusMode,
  });

  factory DeviceStateContext.fromJson(Map<String, dynamic> json) =>
      _$DeviceStateContextFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceStateContextToJson(this);
}

/// User patterns context
@JsonSerializable()
class UserPatternsContext {
  /// Time of day in seconds since midnight
  final double timeOfDay;

  /// Day of week (0-6, 0=Sunday)
  final int dayOfWeek;

  /// Average session length in minutes
  final double? avgSessionMinutes;

  /// Activity pattern (e.g., 'work', 'exercise', 'rest')
  final String? activityPattern;

  UserPatternsContext({
    this.timeOfDay = 0.0,
    this.dayOfWeek = 0,
    this.avgSessionMinutes,
    this.activityPattern,
  });

  factory UserPatternsContext.fromJson(Map<String, dynamic> json) =>
      _$UserPatternsContextFromJson(json);

  Map<String, dynamic> toJson() => _$UserPatternsContextToJson(this);
}
