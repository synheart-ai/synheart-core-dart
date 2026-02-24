import 'package:json_annotation/json_annotation.dart';

part 'hsi_export.g.dart';

/// HSI 1.1 Canonical Payload
///
/// HSI (Human State Interface) 1.1 is the canonical JSON format for external
/// interoperability across systems and platforms.
///
/// This is distinct from HSV (Human State Vector), which is the internal
/// Dart representation optimized for on-device processing.
///
/// See: https://github.com/synheart-ai/hsi/schema/hsi-1.1.schema.json
@JsonSerializable(explicitToJson: true)
class HSI11Payload {
  /// HSI version (always "1.1")
  @JsonKey(name: 'hsi_version')
  final String hsiVersion;

  /// Event-time: when the human state was observed
  @JsonKey(name: 'observed_at_utc')
  final String observedAtUtc;

  /// Processing-time: when this payload was produced
  @JsonKey(name: 'computed_at_utc')
  final String computedAtUtc;

  /// Producer identity
  final HSI11Producer producer;

  /// Window identifiers
  @JsonKey(name: 'window_ids')
  final List<String> windowIds;

  /// Window definitions
  final Map<String, HSI11Window> windows;

  /// Axis readings (optional)
  final HSI11Axes? axes;

  /// Embeddings (optional)
  final List<HSI11Embedding>? embeddings;

  /// Privacy assertions
  final HSI11Privacy privacy;

  /// Additional metadata (optional)
  final Map<String, dynamic>? meta;

  HSI11Payload({
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

  factory HSI11Payload.fromJson(Map<String, dynamic> json) =>
      _$HSI11PayloadFromJson(json);

  Map<String, dynamic> toJson() => _$HSI11PayloadToJson(this);
}

/// Producer metadata
@JsonSerializable()
class HSI11Producer {
  final String name;
  final String version;

  @JsonKey(name: 'instance_id')
  final String instanceId;

  HSI11Producer({
    required this.name,
    required this.version,
    required this.instanceId,
  });

  factory HSI11Producer.fromJson(Map<String, dynamic> json) =>
      _$HSI11ProducerFromJson(json);

  Map<String, dynamic> toJson() => _$HSI11ProducerToJson(this);
}

/// Time window definition
@JsonSerializable()
class HSI11Window {
  final String start;
  final String end;
  final String? label;

  HSI11Window({required this.start, required this.end, this.label});

  factory HSI11Window.fromJson(Map<String, dynamic> json) =>
      _$HSI11WindowFromJson(json);

  Map<String, dynamic> toJson() => _$HSI11WindowToJson(this);
}

/// Axes container
@JsonSerializable(explicitToJson: true)
class HSI11Axes {
  final HSI11Domain? physiological;
  final HSI11Domain? engagement;
  final HSI11Domain? behavior;
  final HSI11Domain? context;

  HSI11Axes({this.physiological, this.engagement, this.behavior, this.context});

  factory HSI11Axes.fromJson(Map<String, dynamic> json) =>
      _$HSI11AxesFromJson(json);

  Map<String, dynamic> toJson() => _$HSI11AxesToJson(this);
}

/// Domain containing axis readings
@JsonSerializable(explicitToJson: true)
class HSI11Domain {
  final List<HSI11Reading> readings;

  HSI11Domain({required this.readings});

  factory HSI11Domain.fromJson(Map<String, dynamic> json) =>
      _$HSI11DomainFromJson(json);

  Map<String, dynamic> toJson() => _$HSI11DomainToJson(this);
}

/// Individual axis reading
@JsonSerializable()
class HSI11Reading {
  final String axis;
  final double score;
  final double confidence;

  @JsonKey(name: 'window_id')
  final String windowId;

  final String? direction;
  final String? notes;

  HSI11Reading({
    required this.axis,
    required this.score,
    required this.confidence,
    required this.windowId,
    this.direction,
    this.notes,
  });

  factory HSI11Reading.fromJson(Map<String, dynamic> json) =>
      _$HSI11ReadingFromJson(json);

  Map<String, dynamic> toJson() => _$HSI11ReadingToJson(this);
}

/// Embedding vector
@JsonSerializable()
class HSI11Embedding {
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

  HSI11Embedding({
    required this.vector,
    required this.dimension,
    required this.encoding,
    required this.confidence,
    required this.windowId,
    this.vectorHash,
    this.model,
    this.notes,
  });

  factory HSI11Embedding.fromJson(Map<String, dynamic> json) =>
      _$HSI11EmbeddingFromJson(json);

  Map<String, dynamic> toJson() => _$HSI11EmbeddingToJson(this);
}

/// Privacy assertions
@JsonSerializable()
class HSI11Privacy {
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

  HSI11Privacy({
    required this.containsPii,
    required this.rawBiosignalsAllowed,
    required this.derivedMetricsAllowed,
    this.embeddingAllowed = false,
    this.consent = 'explicit',
    this.notes,
  });

  factory HSI11Privacy.fromJson(Map<String, dynamic> json) =>
      _$HSI11PrivacyFromJson(json);

  Map<String, dynamic> toJson() => _$HSI11PrivacyToJson(this);
}

// HSI generation goes through synheart-runtime exclusively.
