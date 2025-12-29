// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hsi_axes.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AffectAxis _$AffectAxisFromJson(Map<String, dynamic> json) => AffectAxis(
      arousalIndex: (json['arousalIndex'] as num?)?.toDouble(),
      valenceStability: (json['valenceStability'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$AffectAxisToJson(AffectAxis instance) =>
    <String, dynamic>{
      'arousalIndex': instance.arousalIndex,
      'valenceStability': instance.valenceStability,
    };

EngagementAxis _$EngagementAxisFromJson(Map<String, dynamic> json) =>
    EngagementAxis(
      engagementStability: (json['engagementStability'] as num?)?.toDouble(),
      interactionCadence: (json['interactionCadence'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$EngagementAxisToJson(EngagementAxis instance) =>
    <String, dynamic>{
      'engagementStability': instance.engagementStability,
      'interactionCadence': instance.interactionCadence,
    };

ActivityAxis _$ActivityAxisFromJson(Map<String, dynamic> json) => ActivityAxis(
      motionIndex: (json['motionIndex'] as num?)?.toDouble(),
      postureStability: (json['postureStability'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$ActivityAxisToJson(ActivityAxis instance) =>
    <String, dynamic>{
      'motionIndex': instance.motionIndex,
      'postureStability': instance.postureStability,
    };

ContextAxis _$ContextAxisFromJson(Map<String, dynamic> json) => ContextAxis(
      screenActiveRatio: (json['screenActiveRatio'] as num?)?.toDouble(),
      sessionFragmentation: (json['sessionFragmentation'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$ContextAxisToJson(ContextAxis instance) =>
    <String, dynamic>{
      'screenActiveRatio': instance.screenActiveRatio,
      'sessionFragmentation': instance.sessionFragmentation,
    };

StateEmbedding _$StateEmbeddingFromJson(Map<String, dynamic> json) =>
    StateEmbedding(
      vector: (json['vector'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
      dimension: (json['dimension'] as num?)?.toInt() ?? 64,
      model: json['model'] as String? ?? 'hsi-fusion-v1',
      timestamp: (json['timestamp'] as num).toInt(),
      windowType: json['windowType'] as String,
    );

Map<String, dynamic> _$StateEmbeddingToJson(StateEmbedding instance) =>
    <String, dynamic>{
      'vector': instance.vector,
      'dimension': instance.dimension,
      'model': instance.model,
      'timestamp': instance.timestamp,
      'windowType': instance.windowType,
    };
