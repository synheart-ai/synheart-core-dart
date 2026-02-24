// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hsi_export.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HSI11Payload _$HSI11PayloadFromJson(Map<String, dynamic> json) => HSI11Payload(
  hsiVersion: json['hsi_version'] as String,
  observedAtUtc: json['observed_at_utc'] as String,
  computedAtUtc: json['computed_at_utc'] as String,
  producer: HSI11Producer.fromJson(json['producer'] as Map<String, dynamic>),
  windowIds: (json['window_ids'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  windows: (json['windows'] as Map<String, dynamic>).map(
    (k, e) => MapEntry(k, HSI11Window.fromJson(e as Map<String, dynamic>)),
  ),
  axes: json['axes'] == null
      ? null
      : HSI11Axes.fromJson(json['axes'] as Map<String, dynamic>),
  embeddings: (json['embeddings'] as List<dynamic>?)
      ?.map((e) => HSI11Embedding.fromJson(e as Map<String, dynamic>))
      .toList(),
  privacy: HSI11Privacy.fromJson(json['privacy'] as Map<String, dynamic>),
  meta: json['meta'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$HSI11PayloadToJson(HSI11Payload instance) =>
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

HSI11Producer _$HSI11ProducerFromJson(Map<String, dynamic> json) =>
    HSI11Producer(
      name: json['name'] as String,
      version: json['version'] as String,
      instanceId: json['instance_id'] as String,
    );

Map<String, dynamic> _$HSI11ProducerToJson(HSI11Producer instance) =>
    <String, dynamic>{
      'name': instance.name,
      'version': instance.version,
      'instance_id': instance.instanceId,
    };

HSI11Window _$HSI11WindowFromJson(Map<String, dynamic> json) => HSI11Window(
  start: json['start'] as String,
  end: json['end'] as String,
  label: json['label'] as String?,
);

Map<String, dynamic> _$HSI11WindowToJson(HSI11Window instance) =>
    <String, dynamic>{
      'start': instance.start,
      'end': instance.end,
      'label': instance.label,
    };

HSI11Axes _$HSI11AxesFromJson(Map<String, dynamic> json) => HSI11Axes(
  physiological: json['physiological'] == null
      ? null
      : HSI11Domain.fromJson(json['physiological'] as Map<String, dynamic>),
  engagement: json['engagement'] == null
      ? null
      : HSI11Domain.fromJson(json['engagement'] as Map<String, dynamic>),
  behavior: json['behavior'] == null
      ? null
      : HSI11Domain.fromJson(json['behavior'] as Map<String, dynamic>),
  context: json['context'] == null
      ? null
      : HSI11Domain.fromJson(json['context'] as Map<String, dynamic>),
);

Map<String, dynamic> _$HSI11AxesToJson(HSI11Axes instance) => <String, dynamic>{
  'physiological': instance.physiological?.toJson(),
  'engagement': instance.engagement?.toJson(),
  'behavior': instance.behavior?.toJson(),
  'context': instance.context?.toJson(),
};

HSI11Domain _$HSI11DomainFromJson(Map<String, dynamic> json) => HSI11Domain(
  readings: (json['readings'] as List<dynamic>)
      .map((e) => HSI11Reading.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$HSI11DomainToJson(HSI11Domain instance) =>
    <String, dynamic>{
      'readings': instance.readings.map((e) => e.toJson()).toList(),
    };

HSI11Reading _$HSI11ReadingFromJson(Map<String, dynamic> json) => HSI11Reading(
  axis: json['axis'] as String,
  score: (json['score'] as num).toDouble(),
  confidence: (json['confidence'] as num).toDouble(),
  windowId: json['window_id'] as String,
  direction: json['direction'] as String?,
  notes: json['notes'] as String?,
);

Map<String, dynamic> _$HSI11ReadingToJson(HSI11Reading instance) =>
    <String, dynamic>{
      'axis': instance.axis,
      'score': instance.score,
      'confidence': instance.confidence,
      'window_id': instance.windowId,
      'direction': instance.direction,
      'notes': instance.notes,
    };

HSI11Embedding _$HSI11EmbeddingFromJson(Map<String, dynamic> json) =>
    HSI11Embedding(
      vector: (json['vector'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
      dimension: (json['dimension'] as num).toInt(),
      encoding: json['encoding'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      windowId: json['window_id'] as String,
      vectorHash: json['vector_hash'] as String?,
      model: json['model'] as String?,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$HSI11EmbeddingToJson(HSI11Embedding instance) =>
    <String, dynamic>{
      'vector': instance.vector,
      'dimension': instance.dimension,
      'encoding': instance.encoding,
      'confidence': instance.confidence,
      'window_id': instance.windowId,
      'vector_hash': instance.vectorHash,
      'model': instance.model,
      'notes': instance.notes,
    };

HSI11Privacy _$HSI11PrivacyFromJson(Map<String, dynamic> json) => HSI11Privacy(
  containsPii: json['contains_pii'] as bool,
  rawBiosignalsAllowed: json['raw_biosignals_allowed'] as bool,
  derivedMetricsAllowed: json['derived_metrics_allowed'] as bool,
  embeddingAllowed: json['embedding_allowed'] as bool? ?? false,
  consent: json['consent'] as String? ?? 'explicit',
  notes: json['notes'] as String?,
);

Map<String, dynamic> _$HSI11PrivacyToJson(HSI11Privacy instance) =>
    <String, dynamic>{
      'contains_pii': instance.containsPii,
      'raw_biosignals_allowed': instance.rawBiosignalsAllowed,
      'derived_metrics_allowed': instance.derivedMetricsAllowed,
      'embedding_allowed': instance.embeddingAllowed,
      'consent': instance.consent,
      'notes': instance.notes,
    };
