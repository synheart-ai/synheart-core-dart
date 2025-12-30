import 'package:json_annotation/json_annotation.dart';

part 'context.g.dart';

/// Context information from Context Adapters + HSI processing
@JsonSerializable()
class ContextState {
  /// Overload indicator (0.0 - 1.0)
  final double overload;

  /// Frustration level (0.0 - 1.0)
  final double frustration;

  /// Engagement level (0.0 - 1.0)
  final double engagement;

  /// Conversation timing metrics
  final ConversationContext conversation;

  /// Device state information
  final DeviceStateContext deviceState;

  /// User pattern information
  final UserPatternsContext userPatterns;

  ContextState({
    required this.overload,
    required this.frustration,
    required this.engagement,
    required this.conversation,
    required this.deviceState,
    required this.userPatterns,
  });

  factory ContextState.fromJson(Map<String, dynamic> json) =>
      _$ContextStateFromJson(json);

  Map<String, dynamic> toJson() => _$ContextStateToJson(this);
}

/// Conversation timing context
@JsonSerializable()
class ConversationContext {
  /// Average reply delay in seconds
  final double avgReplyDelaySec;

  /// Burstiness of conversation (0.0 - 1.0)
  final double burstiness;

  /// Interrupt rate (0.0 - 1.0)
  final double interruptRate;

  ConversationContext({
    required this.avgReplyDelaySec,
    required this.burstiness,
    required this.interruptRate,
  });

  factory ConversationContext.fromJson(Map<String, dynamic> json) =>
      _$ConversationContextFromJson(json);

  Map<String, dynamic> toJson() => _$ConversationContextToJson(this);
}

/// Device state context
@JsonSerializable()
class DeviceStateContext {
  /// Whether app is in foreground
  final bool foreground;

  /// Whether screen is on
  final bool screenOn;

  /// Focus mode (e.g., 'work', 'personal', 'none')
  final String? focusMode;

  DeviceStateContext({
    required this.foreground,
    required this.screenOn,
    this.focusMode,
  });

  factory DeviceStateContext.fromJson(Map<String, dynamic> json) =>
      _$DeviceStateContextFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceStateContextToJson(this);
}

/// User patterns context
@JsonSerializable()
class UserPatternsContext {
  /// Morning focus bias (0.0 - 1.0)
  final double morningFocusBias;

  /// Average session length in minutes
  final double avgSessionMinutes;

  /// Baseline typing cadence
  final double baselineTypingCadence;

  UserPatternsContext({
    required this.morningFocusBias,
    required this.avgSessionMinutes,
    required this.baselineTypingCadence,
  });

  factory UserPatternsContext.fromJson(Map<String, dynamic> json) =>
      _$UserPatternsContextFromJson(json);

  Map<String, dynamic> toJson() => _$UserPatternsContextToJson(this);
}
