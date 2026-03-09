/// HSI 1.1 Canonical Payload
///
/// HSI (Human State Interface) 1.1 is the canonical JSON format for external
/// interoperability across systems and platforms.
///
/// See: https://github.com/synheart-ai/hsi/schema/hsi-1.1.schema.json
class HSI11Payload {
  final String hsiVersion;
  final String observedAtUtc;
  final String computedAtUtc;
  final HSI11Producer producer;
  final List<String> windowIds;
  final Map<String, HSI11Window> windows;
  final HSI11Axes? axes;
  final List<HSI11Embedding>? embeddings;
  final HSI11Privacy privacy;
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

  factory HSI11Payload.fromJson(Map<String, dynamic> json) => HSI11Payload(
        hsiVersion: json['hsi_version'] as String,
        observedAtUtc: json['observed_at_utc'] as String,
        computedAtUtc: json['computed_at_utc'] as String,
        producer:
            HSI11Producer.fromJson(json['producer'] as Map<String, dynamic>),
        windowIds:
            (json['window_ids'] as List<dynamic>).cast<String>(),
        windows: (json['windows'] as Map<String, dynamic>).map(
          (k, v) =>
              MapEntry(k, HSI11Window.fromJson(v as Map<String, dynamic>)),
        ),
        axes: json['axes'] is Map
            ? HSI11Axes.fromJson(json['axes'] as Map<String, dynamic>)
            : null,
        embeddings: (json['embeddings'] as List<dynamic>?)
            ?.map(
                (e) => HSI11Embedding.fromJson(e as Map<String, dynamic>))
            .toList(),
        privacy:
            HSI11Privacy.fromJson(json['privacy'] as Map<String, dynamic>),
        meta: json['meta'] as Map<String, dynamic>?,
      );

  Map<String, dynamic> toJson() => {
        'hsi_version': hsiVersion,
        'observed_at_utc': observedAtUtc,
        'computed_at_utc': computedAtUtc,
        'producer': producer.toJson(),
        'window_ids': windowIds,
        'windows': windows.map((k, v) => MapEntry(k, v.toJson())),
        if (axes != null) 'axes': axes!.toJson(),
        if (embeddings != null)
          'embeddings': embeddings!.map((e) => e.toJson()).toList(),
        'privacy': privacy.toJson(),
        if (meta != null) 'meta': meta,
      };
}

class HSI11Producer {
  final String name;
  final String version;
  final String instanceId;

  HSI11Producer({
    required this.name,
    required this.version,
    required this.instanceId,
  });

  factory HSI11Producer.fromJson(Map<String, dynamic> json) => HSI11Producer(
        name: json['name'] as String,
        version: json['version'] as String,
        instanceId: json['instance_id'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
        'instance_id': instanceId,
      };
}

class HSI11Window {
  final String start;
  final String end;
  final String? label;

  HSI11Window({required this.start, required this.end, this.label});

  factory HSI11Window.fromJson(Map<String, dynamic> json) => HSI11Window(
        start: json['start'] as String,
        end: json['end'] as String,
        label: json['label'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        if (label != null) 'label': label,
      };
}

class HSI11Axes {
  final HSI11Domain? physiological;
  final HSI11Domain? engagement;
  final HSI11Domain? behavior;
  final HSI11Domain? context;

  HSI11Axes({this.physiological, this.engagement, this.behavior, this.context});

  factory HSI11Axes.fromJson(Map<String, dynamic> json) => HSI11Axes(
        physiological: json['physiological'] is Map
            ? HSI11Domain.fromJson(
                json['physiological'] as Map<String, dynamic>)
            : null,
        engagement: json['engagement'] is Map
            ? HSI11Domain.fromJson(
                json['engagement'] as Map<String, dynamic>)
            : null,
        behavior: json['behavior'] is Map
            ? HSI11Domain.fromJson(json['behavior'] as Map<String, dynamic>)
            : null,
        context: json['context'] is Map
            ? HSI11Domain.fromJson(json['context'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
        if (physiological != null) 'physiological': physiological!.toJson(),
        if (engagement != null) 'engagement': engagement!.toJson(),
        if (behavior != null) 'behavior': behavior!.toJson(),
        if (context != null) 'context': context!.toJson(),
      };
}

class HSI11Domain {
  final List<HSI11Reading> readings;

  HSI11Domain({required this.readings});

  factory HSI11Domain.fromJson(Map<String, dynamic> json) => HSI11Domain(
        readings: (json['readings'] as List<dynamic>)
            .map((e) => HSI11Reading.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'readings': readings.map((e) => e.toJson()).toList(),
      };
}

class HSI11Reading {
  final String axis;
  final double score;
  final double confidence;
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

  factory HSI11Reading.fromJson(Map<String, dynamic> json) => HSI11Reading(
        axis: json['axis'] as String,
        score: (json['score'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
        windowId: json['window_id'] as String,
        direction: json['direction'] as String?,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'axis': axis,
        'score': score,
        'confidence': confidence,
        'window_id': windowId,
        if (direction != null) 'direction': direction,
        if (notes != null) 'notes': notes,
      };
}

class HSI11Embedding {
  final List<double> vector;
  final int dimension;
  final String encoding;
  final double confidence;
  final String windowId;
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
      HSI11Embedding(
        vector: (json['vector'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList(),
        dimension: json['dimension'] as int,
        encoding: json['encoding'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        windowId: json['window_id'] as String,
        vectorHash: json['vector_hash'] as String?,
        model: json['model'] as String?,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'vector': vector,
        'dimension': dimension,
        'encoding': encoding,
        'confidence': confidence,
        'window_id': windowId,
        if (vectorHash != null) 'vector_hash': vectorHash,
        if (model != null) 'model': model,
        if (notes != null) 'notes': notes,
      };
}

class HSI11Privacy {
  final bool containsPii;
  final bool rawBiosignalsAllowed;
  final bool derivedMetricsAllowed;
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

  factory HSI11Privacy.fromJson(Map<String, dynamic> json) => HSI11Privacy(
        containsPii: json['contains_pii'] as bool,
        rawBiosignalsAllowed: json['raw_biosignals_allowed'] as bool,
        derivedMetricsAllowed: json['derived_metrics_allowed'] as bool,
        embeddingAllowed: json['embedding_allowed'] as bool? ?? false,
        consent: json['consent'] as String? ?? 'explicit',
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'contains_pii': containsPii,
        'raw_biosignals_allowed': rawBiosignalsAllowed,
        'derived_metrics_allowed': derivedMetricsAllowed,
        'embedding_allowed': embeddingAllowed,
        'consent': consent,
        if (notes != null) 'notes': notes,
      };
}
