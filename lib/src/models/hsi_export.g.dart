// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hsi_export.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HSI10Payload _$HSI10PayloadFromJson(Map<String, dynamic> json) => HSI10Payload(
      hsiVersion: json['hsi_version'] as String,
      observedAtUtc: json['observed_at_utc'] as String,
      computedAtUtc: json['computed_at_utc'] as String,
      producer:
          HSI10Producer.fromJson(json['producer'] as Map<String, dynamic>),
      windowIds: (json['window_ids'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      windows: (json['windows'] as Map<String, dynamic>).map(
        (k, e) => MapEntry(k, HSI10Window.fromJson(e as Map<String, dynamic>)),
      ),
      axes: json['axes'] == null
          ? null
          : HSI10Axes.fromJson(json['axes'] as Map<String, dynamic>),
      embeddings: (json['embeddings'] as List<dynamic>?)
          ?.map((e) => HSI10Embedding.fromJson(e as Map<String, dynamic>))
          .toList(),
      privacy: HSI10Privacy.fromJson(json['privacy'] as Map<String, dynamic>),
      meta: json['meta'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$HSI10PayloadToJson(HSI10Payload instance) =>
    <String, dynamic>{
      'hsi_version': instance.hsiVersion,
      'observed_at_utc': instance.observedAtUtc,
      'computed_at_utc': instance.computedAtUtc,
      'producer': instance.producer.toJson(),
      'window_ids': instance.windowIds,
      'windows': instance.windows.map((k, e) => MapEntry(k, e.toJson())),
      'axes': instance.axes?.toJson(),
      'embeddings': instance.embeddings?.map((e) => e.toJson()).toList(),
      'privacy': instance.privacy.toJson(),
      'meta': instance.meta,
    };

HSI10Producer _$HSI10ProducerFromJson(Map<String, dynamic> json) =>
    HSI10Producer(
      name: json['name'] as String,
      version: json['version'] as String,
      instanceId: json['instance_id'] as String,
    );

Map<String, dynamic> _$HSI10ProducerToJson(HSI10Producer instance) =>
    <String, dynamic>{
      'name': instance.name,
      'version': instance.version,
      'instance_id': instance.instanceId,
    };

HSI10Window _$HSI10WindowFromJson(Map<String, dynamic> json) => HSI10Window(
      start: json['start'] as String,
      end: json['end'] as String,
      label: json['label'] as String?,
    );

Map<String, dynamic> _$HSI10WindowToJson(HSI10Window instance) =>
    <String, dynamic>{
      'start': instance.start,
      'end': instance.end,
      'label': instance.label,
    };

HSI10Axes _$HSI10AxesFromJson(Map<String, dynamic> json) => HSI10Axes(
      affect: json['affect'] == null
          ? null
          : HSI10Domain.fromJson(json['affect'] as Map<String, dynamic>),
      behavior: json['behavior'] == null
          ? null
          : HSI10Domain.fromJson(json['behavior'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$HSI10AxesToJson(HSI10Axes instance) => <String, dynamic>{
      'affect': instance.affect?.toJson(),
      'behavior': instance.behavior?.toJson(),
    };

HSI10Domain _$HSI10DomainFromJson(Map<String, dynamic> json) => HSI10Domain(
      readings: (json['readings'] as List<dynamic>)
          .map((e) => HSI10Reading.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$HSI10DomainToJson(HSI10Domain instance) =>
    <String, dynamic>{
      'readings': instance.readings.map((e) => e.toJson()).toList(),
    };

HSI10Reading _$HSI10ReadingFromJson(Map<String, dynamic> json) => HSI10Reading(
      axis: json['axis'] as String,
      score: (json['score'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      windowId: json['window_id'] as String,
      direction: json['direction'] as String?,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$HSI10ReadingToJson(HSI10Reading instance) =>
    <String, dynamic>{
      'axis': instance.axis,
      'score': instance.score,
      'confidence': instance.confidence,
      'window_id': instance.windowId,
      'direction': instance.direction,
      'notes': instance.notes,
    };

HSI10Embedding _$HSI10EmbeddingFromJson(Map<String, dynamic> json) =>
    HSI10Embedding(
      vector: (json['vector'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
      dimension: (json['dimension'] as num).toInt(),
      encoding: json['encoding'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      windowId: json['window_id'] as String,
      model: json['model'] as String?,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$HSI10EmbeddingToJson(HSI10Embedding instance) =>
    <String, dynamic>{
      'vector': instance.vector,
      'dimension': instance.dimension,
      'encoding': instance.encoding,
      'confidence': instance.confidence,
      'window_id': instance.windowId,
      'model': instance.model,
      'notes': instance.notes,
    };

HSI10Privacy _$HSI10PrivacyFromJson(Map<String, dynamic> json) => HSI10Privacy(
      containsPii: json['contains_pii'] as bool,
      rawBiosignalsAllowed: json['raw_biosignals_allowed'] as bool,
      derivedMetricsAllowed: json['derived_metrics_allowed'] as bool,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$HSI10PrivacyToJson(HSI10Privacy instance) =>
    <String, dynamic>{
      'contains_pii': instance.containsPii,
      'raw_biosignals_allowed': instance.rawBiosignalsAllowed,
      'derived_metrics_allowed': instance.derivedMetricsAllowed,
      'notes': instance.notes,
    };
