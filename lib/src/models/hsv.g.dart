// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hsv.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HumanStateVector _$HumanStateVectorFromJson(Map<String, dynamic> json) =>
    HumanStateVector(
      version: json['version'] as String,
      timestamp: (json['timestamp'] as num).toInt(),
      emotion: EmotionState.fromJson(json['emotion'] as Map<String, dynamic>),
      focus: FocusState.fromJson(json['focus'] as Map<String, dynamic>),
      behavior: BehaviorState.fromJson(
        json['behavior'] as Map<String, dynamic>,
      ),
      context: ContextState.fromJson(json['context'] as Map<String, dynamic>),
      meta: MetaState.fromJson(json['meta'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$HumanStateVectorToJson(HumanStateVector instance) =>
    <String, dynamic>{
      'version': instance.version,
      'timestamp': instance.timestamp,
      'emotion': instance.emotion,
      'focus': instance.focus,
      'behavior': instance.behavior,
      'context': instance.context,
      'meta': instance.meta,
    };

MetaState _$MetaStateFromJson(Map<String, dynamic> json) => MetaState(
  sessionId: json['sessionId'] as String,
  device: DeviceInfo.fromJson(json['device'] as Map<String, dynamic>),
  samplingRateHz: (json['samplingRateHz'] as num).toDouble(),
  hsiEmbedding: (json['hsiEmbedding'] as List<dynamic>)
      .map((e) => (e as num).toDouble())
      .toList(),
);

Map<String, dynamic> _$MetaStateToJson(MetaState instance) => <String, dynamic>{
  'sessionId': instance.sessionId,
  'device': instance.device,
  'samplingRateHz': instance.samplingRateHz,
  'hsiEmbedding': instance.hsiEmbedding,
};

DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) => DeviceInfo(
  platform: json['platform'] as String,
  model: json['model'] as String?,
  osVersion: json['osVersion'] as String?,
);

Map<String, dynamic> _$DeviceInfoToJson(DeviceInfo instance) =>
    <String, dynamic>{
      'platform': instance.platform,
      'model': instance.model,
      'osVersion': instance.osVersion,
    };
