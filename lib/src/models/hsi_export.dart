import 'package:json_annotation/json_annotation.dart';

part 'hsi_export.g.dart';

/// HSI 1.0 Canonical Payload
///
/// HSI (Human State Interface) 1.0 is the canonical JSON format for external
/// interoperability across systems and platforms.
///
/// This is distinct from HSV (Human State Vector), which is the internal
/// Dart representation optimized for on-device processing.
///
/// See: https://github.com/synheart-ai/hsi/schema/hsi-1.0.schema.json
@JsonSerializable(explicitToJson: true)
class HSI10Payload {
  /// HSI version (always "1.0")
  @JsonKey(name: 'hsi_version')
  final String hsiVersion;

  /// Event-time: when the human state was observed
  @JsonKey(name: 'observed_at_utc')
  final String observedAtUtc;

  /// Processing-time: when this payload was produced
  @JsonKey(name: 'computed_at_utc')
  final String computedAtUtc;

  /// Producer identity
  final HSI10Producer producer;

  /// Window identifiers
  @JsonKey(name: 'window_ids')
  final List<String> windowIds;

  /// Window definitions
  final Map<String, HSI10Window> windows;

  /// Axis readings (optional)
  final HSI10Axes? axes;

  /// Embeddings (optional)
  final List<HSI10Embedding>? embeddings;

  /// Privacy assertions
  final HSI10Privacy privacy;

  /// Additional metadata (optional)
  final Map<String, dynamic>? meta;

  HSI10Payload({
    required this.hsiVersion,
    required this.observedAtUtc,
    required this.computedAtUtc,
    required this.producer,
    required this.windowIds,
    required this.windows,
    this.axes,
    this.embeddings,
    required this.privacy,
    this.meta,
  });

  factory HSI10Payload.fromJson(Map<String, dynamic> json) =>
      _$HSI10PayloadFromJson(json);

  Map<String, dynamic> toJson() => _$HSI10PayloadToJson(this);
}

/// Producer metadata
@JsonSerializable()
class HSI10Producer {
  final String name;
  final String version;

  @JsonKey(name: 'instance_id')
  final String instanceId;

  HSI10Producer({
    required this.name,
    required this.version,
    required this.instanceId,
  });

  factory HSI10Producer.fromJson(Map<String, dynamic> json) =>
      _$HSI10ProducerFromJson(json);

  Map<String, dynamic> toJson() => _$HSI10ProducerToJson(this);
}

/// Time window definition
@JsonSerializable()
class HSI10Window {
  final String start;
  final String end;
  final String? label;

  HSI10Window({required this.start, required this.end, this.label});

  factory HSI10Window.fromJson(Map<String, dynamic> json) =>
      _$HSI10WindowFromJson(json);

  Map<String, dynamic> toJson() => _$HSI10WindowToJson(this);
}

/// Axes container
@JsonSerializable(explicitToJson: true)
class HSI10Axes {
  final HSI10Domain? affect;
  final HSI10Domain? engagement;
  final HSI10Domain? behavior;

  HSI10Axes({this.affect, this.engagement, this.behavior});

  factory HSI10Axes.fromJson(Map<String, dynamic> json) =>
      _$HSI10AxesFromJson(json);

  Map<String, dynamic> toJson() => _$HSI10AxesToJson(this);
}

/// Domain containing axis readings
@JsonSerializable(explicitToJson: true)
class HSI10Domain {
  final List<HSI10Reading> readings;

  HSI10Domain({required this.readings});

  factory HSI10Domain.fromJson(Map<String, dynamic> json) =>
      _$HSI10DomainFromJson(json);

  Map<String, dynamic> toJson() => _$HSI10DomainToJson(this);
}

/// Individual axis reading
@JsonSerializable()
class HSI10Reading {
  final String axis;
  final double score;
  final double confidence;

  @JsonKey(name: 'window_id')
  final String windowId;

  final String? direction;
  final String? notes;

  HSI10Reading({
    required this.axis,
    required this.score,
    required this.confidence,
    required this.windowId,
    this.direction,
    this.notes,
  });

  factory HSI10Reading.fromJson(Map<String, dynamic> json) =>
      _$HSI10ReadingFromJson(json);

  Map<String, dynamic> toJson() => _$HSI10ReadingToJson(this);
}

/// Embedding vector
@JsonSerializable()
class HSI10Embedding {
  final List<double> vector;
  final int dimension;
  final String encoding;
  final double confidence;

  @JsonKey(name: 'window_id')
  final String windowId;

  @JsonKey(name: 'vector_hash')
  final String? vectorHash;

  final String? model;
  final String? notes;

  HSI10Embedding({
    required this.vector,
    required this.dimension,
    required this.encoding,
    required this.confidence,
    required this.windowId,
    this.vectorHash,
    this.model,
    this.notes,
  });

  factory HSI10Embedding.fromJson(Map<String, dynamic> json) =>
      _$HSI10EmbeddingFromJson(json);

  Map<String, dynamic> toJson() => _$HSI10EmbeddingToJson(this);
}

/// Privacy assertions
@JsonSerializable()
class HSI10Privacy {
  @JsonKey(name: 'contains_pii')
  final bool containsPii;

  @JsonKey(name: 'raw_biosignals_allowed')
  final bool rawBiosignalsAllowed;

  @JsonKey(name: 'derived_metrics_allowed')
  final bool derivedMetricsAllowed;

  @JsonKey(name: 'embedding_allowed')
  final bool embeddingAllowed;

  final String consent;

  final String? notes;

  HSI10Privacy({
    required this.containsPii,
    required this.rawBiosignalsAllowed,
    required this.derivedMetricsAllowed,
    this.embeddingAllowed = false,
    this.consent = 'explicit',
    this.notes,
  });

  factory HSI10Privacy.fromJson(Map<String, dynamic> json) =>
      _$HSI10PrivacyFromJson(json);

  Map<String, dynamic> toJson() => _$HSI10PrivacyToJson(this);
}

// HSI generation goes through synheart-runtime exclusively.
