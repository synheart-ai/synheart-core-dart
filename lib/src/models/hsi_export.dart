import 'package:json_annotation/json_annotation.dart';
import 'hsv.dart';

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
  final HSI10Domain? behavior;

  HSI10Axes({this.affect, this.behavior});

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

  final String? model;
  final String? notes;

  HSI10Embedding({
    required this.vector,
    required this.dimension,
    required this.encoding,
    required this.confidence,
    required this.windowId,
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

  final String? notes;

  HSI10Privacy({
    required this.containsPii,
    required this.rawBiosignalsAllowed,
    required this.derivedMetricsAllowed,
    this.notes,
  });

  factory HSI10Privacy.fromJson(Map<String, dynamic> json) =>
      _$HSI10PrivacyFromJson(json);

  Map<String, dynamic> toJson() => _$HSI10PrivacyToJson(this);
}

/// Extension to convert HSV (Human State Vector) to HSI 1.0 format
extension HSI10Export on HumanStateVector {
  /// Convert HSV to HSI 1.0 canonical JSON payload
  ///
  /// This converts the internal HSV representation (fast, type-safe Dart classes)
  /// to the external HSI 1.0 format (JSON for cross-system interoperability).
  HSI10Payload toHSI10({
    String? producerName,
    String? producerVersion,
    String? instanceId,
  }) {
    final now = DateTime.now().toUtc();
    final observedTime = DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc();
    const windowId = 'w1';

    // Create window based on embedding window type
    final windowDuration = _getWindowDuration(meta.embedding.windowType);
    final windowStart = observedTime.subtract(windowDuration);

    return HSI10Payload(
      hsiVersion: '1.0',
      observedAtUtc: observedTime.toIso8601String(),
      computedAtUtc: now.toIso8601String(),
      producer: HSI10Producer(
        name: producerName ?? 'Synheart Core SDK',
        version: producerVersion ?? version,
        instanceId: instanceId ?? meta.sessionId,
      ),
      windowIds: [windowId],
      windows: {
        windowId: HSI10Window(
          start: windowStart.toIso8601String(),
          end: observedTime.toIso8601String(),
          label: '${meta.embedding.windowType}_window',
        ),
      },
      axes: _convertAxes(windowId),
      embeddings: [_convertEmbedding(windowId)],
      privacy: HSI10Privacy(
        containsPii: false,
        rawBiosignalsAllowed: false,
        derivedMetricsAllowed: true,
        notes: 'Synheart Core SDK: privacy-first, on-device processing only',
      ),
      meta: {
        'sdk': 'synheart_core',
        'platform': meta.device.platform,
        'sampling_rate_hz': meta.samplingRateHz,
      },
    );
  }

  /// Convert HSV axes to HSI 1.0 axes format
  HSI10Axes? _convertAxes(String windowId) {
    final affectReadings = <HSI10Reading>[];
    final behaviorReadings = <HSI10Reading>[];

    // Convert Affect Axis
    if (meta.axes.affect.arousalIndex != null) {
      affectReadings.add(
        HSI10Reading(
          axis: 'arousal',
          score: meta.axes.affect.arousalIndex!,
          confidence:
              0.8, // Default confidence (internal doesn't track per-axis confidence)
          windowId: windowId,
          direction: 'higher_is_more',
        ),
      );
    }

    if (meta.axes.affect.valenceStability != null) {
      affectReadings.add(
        HSI10Reading(
          axis: 'valence_stability',
          score: meta.axes.affect.valenceStability!,
          confidence: 0.8,
          windowId: windowId,
          direction: 'higher_is_more',
        ),
      );
    }

    // Convert Engagement Axis to behavior domain
    if (meta.axes.engagement.engagementStability != null) {
      behaviorReadings.add(
        HSI10Reading(
          axis: 'engagement_stability',
          score: meta.axes.engagement.engagementStability!,
          confidence: 0.8,
          windowId: windowId,
          direction: 'higher_is_more',
        ),
      );
    }

    if (meta.axes.engagement.interactionCadence != null) {
      behaviorReadings.add(
        HSI10Reading(
          axis: 'interaction_cadence',
          score: meta.axes.engagement.interactionCadence!,
          confidence: 0.8,
          windowId: windowId,
          direction: 'higher_is_more',
        ),
      );
    }

    // Convert Activity Axis to behavior domain
    if (meta.axes.activity.motionIndex != null) {
      behaviorReadings.add(
        HSI10Reading(
          axis: 'motion',
          score: meta.axes.activity.motionIndex!,
          confidence: 0.8,
          windowId: windowId,
          direction: 'higher_is_more',
        ),
      );
    }

    // Convert Context Axis to behavior domain
    if (meta.axes.context.screenActiveRatio != null) {
      behaviorReadings.add(
        HSI10Reading(
          axis: 'screen_active_ratio',
          score: meta.axes.context.screenActiveRatio!,
          confidence: 0.8,
          windowId: windowId,
          direction: 'higher_is_more',
        ),
      );
    }

    if (affectReadings.isEmpty && behaviorReadings.isEmpty) {
      return null;
    }

    return HSI10Axes(
      affect: affectReadings.isNotEmpty
          ? HSI10Domain(readings: affectReadings)
          : null,
      behavior: behaviorReadings.isNotEmpty
          ? HSI10Domain(readings: behaviorReadings)
          : null,
    );
  }

  /// Convert HSV embedding to HSI 1.0 embedding format
  HSI10Embedding _convertEmbedding(String windowId) {
    return HSI10Embedding(
      vector: meta.embedding.vector,
      dimension: meta.embedding.dimension,
      encoding: 'float64',
      confidence: 0.85, // Default confidence for embedding
      windowId: windowId,
      model: meta.embedding.model,
      notes: 'HSV state embedding',
    );
  }

  /// Get window duration from window type
  Duration _getWindowDuration(String windowType) {
    switch (windowType) {
      case 'micro':
        return const Duration(seconds: 30);
      case 'short':
        return const Duration(minutes: 5);
      case 'medium':
        return const Duration(hours: 1);
      case 'long':
        return const Duration(hours: 24);
      default:
        return const Duration(seconds: 30);
    }
  }

  /// Convert FocusState to Python format for snapshot
  /// Returns a Map matching the Python focus object structure
  Map<String, dynamic> toFocusSnapshot() {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      this.timestamp,
    ).toUtc();
    final timestampStr = timestamp.toIso8601String();

    // Determine focus state based on score
    String state;
    if (focus.score >= 0.75) {
      state = 'deep_focus';
    } else if (focus.score >= 0.5) {
      state = 'focused';
    } else if (focus.score >= 0.25) {
      state = 'neutral';
    } else {
      state = 'distracted';
    }

    // Determine trend based on cognitive load and distraction
    String trend;
    if (focus.cognitiveLoad > 0.6 && focus.distraction < 0.3) {
      trend = 'increasing';
    } else if (focus.distraction > 0.6 || focus.cognitiveLoad < 0.3) {
      trend = 'decreasing';
    } else {
      trend = 'stable';
    }

    // Calculate confidence from clarity
    final confidence = (focus.clarity * 0.8 + 0.2).clamp(0.0, 1.0);

    return {
      'timestamp': timestampStr,
      'state': state,
      'estimate': {
        'score': focus.score.clamp(0.0, 1.0),
        'confidence': confidence,
      },
      'trend': trend,
    };
  }

  /// Convert EmotionState to Python format for snapshot
  /// Returns a Map matching the Python emotion object structure
  Map<String, dynamic> toEmotionSnapshot() {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      this.timestamp,
    ).toUtc();
    final timestampStr = timestamp.toIso8601String();

    // Determine primary emotion based on stress, calm, activation
    String primaryEmotion;
    if (emotion.stress > 0.6) {
      primaryEmotion = 'stressed';
    } else if (emotion.calm > 0.6) {
      primaryEmotion = 'calm';
    } else if (emotion.activation > 0.6) {
      primaryEmotion = 'excited';
    } else if (emotion.activation < 0.3) {
      primaryEmotion = 'tired';
    } else {
      primaryEmotion = 'calm'; // Default
    }

    // Map activation to arousal (0.0-1.0)
    final arousal = emotion.activation.clamp(0.0, 1.0);

    // Use stress as stress_index
    final stressIndex = emotion.stress.clamp(0.0, 1.0);

    // Calculate energy level from activation and engagement
    final energyLevel = ((emotion.activation + emotion.engagement) / 2.0).clamp(
      0.0,
      1.0,
    );

    return {
      'timestamp': timestampStr,
      'primary_emotion': primaryEmotion,
      'valence': emotion.valence.clamp(-1.0, 1.0),
      'arousal': arousal,
      'stress_index': stressIndex,
      'energy_level': energyLevel,
    };
  }

  /// Get ISO 8601 timestamp string from HSV timestamp
  String getTimestampString() {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      this.timestamp,
    ).toUtc();
    return timestamp.toIso8601String();
  }
}
