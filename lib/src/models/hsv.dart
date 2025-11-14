import 'package:json_annotation/json_annotation.dart';
import 'emotion.dart';
import 'focus.dart';
import 'behavior.dart';
import 'context.dart';

part 'hsv.g.dart';

/// Human State Vector (HSV) - The canonical representation of human state
/// 
/// This is the shared "state bus" that all Synheart components consume.
/// HSI Core produces the base HSV, then Emotion and Focus heads populate
/// their respective sections.
@JsonSerializable()
class HumanStateVector {
  /// HSV schema version
  final String version;

  /// Timestamp in milliseconds since epoch
  final int timestamp;

  /// Emotion state (populated by Emotion Engine)
  final EmotionState emotion;

  /// Focus state (populated by Focus Engine)
  final FocusState focus;

  /// Behavioral metrics (from Phone SDK + HSI processing)
  final BehaviorState behavior;

  /// Context information (from Context Adapters + HSI processing)
  final ContextState context;

  /// Metadata (device, session, internal embeddings)
  final MetaState meta;

  HumanStateVector({
    required this.version,
    required this.timestamp,
    required this.emotion,
    required this.focus,
    required this.behavior,
    required this.context,
    required this.meta,
  });

  factory HumanStateVector.fromJson(Map<String, dynamic> json) =>
      _$HumanStateVectorFromJson(json);

  Map<String, dynamic> toJson() => _$HumanStateVectorToJson(this);

  /// Create a base HSV with empty emotion/focus (before heads populate them)
  factory HumanStateVector.base({
    required int timestamp,
    required BehaviorState behavior,
    required ContextState context,
    required MetaState meta,
    String version = '1.0.0',
  }) {
    return HumanStateVector(
      version: version,
      timestamp: timestamp,
      emotion: EmotionState.empty(),
      focus: FocusState.empty(),
      behavior: behavior,
      context: context,
      meta: meta,
    );
  }

  /// Create a copy with updated emotion state
  HumanStateVector copyWithEmotion(EmotionState emotion) {
    return HumanStateVector(
      version: version,
      timestamp: timestamp,
      emotion: emotion,
      focus: focus,
      behavior: behavior,
      context: context,
      meta: meta,
    );
  }

  /// Create a copy with updated focus state
  HumanStateVector copyWithFocus(FocusState focus) {
    return HumanStateVector(
      version: version,
      timestamp: timestamp,
      emotion: emotion,
      focus: focus,
      behavior: behavior,
      context: context,
      meta: meta,
    );
  }
}

/// Metadata state containing device, session, and internal embeddings
@JsonSerializable()
class MetaState {
  /// Session identifier
  final String sessionId;

  /// Device information
  final DeviceInfo device;

  /// Sampling rate in Hz
  final double samplingRateHz;

  /// Internal HSI embedding (latent representation)
  final List<double> hsiEmbedding;

  MetaState({
    required this.sessionId,
    required this.device,
    required this.samplingRateHz,
    required this.hsiEmbedding,
  });

  factory MetaState.fromJson(Map<String, dynamic> json) =>
      _$MetaStateFromJson(json);

  Map<String, dynamic> toJson() => _$MetaStateToJson(this);
}

/// Device information
@JsonSerializable()
class DeviceInfo {
  /// Platform (e.g., 'ios', 'android')
  final String platform;

  /// Optional device model
  final String? model;

  /// Optional OS version
  final String? osVersion;

  DeviceInfo({
    required this.platform,
    this.model,
    this.osVersion,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceInfoToJson(this);
}

