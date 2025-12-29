import 'package:json_annotation/json_annotation.dart';

part 'hsi_axes.g.dart';

/// HSV State Axes - Core state representation indices
///
/// These axes form the internal HSV (Human State Vector) representation.
/// They provide interpretation-agnostic numerical representations of
/// physiological, behavioral, and contextual state dimensions.
///
/// All indices are normalized to [0.0, 1.0] range.
/// Missing signals result in null values (not 0.0).
///
/// For external interoperability, HSV can be exported to HSI 1.0 format
/// using the `toHSI10()` extension method.

/// Affect Axis - Physiological arousal and emotional stability
@JsonSerializable()
class AffectAxis {
  /// Physiological arousal level (0.0 - 1.0)
  /// Derived from HR, HRV, and motion patterns
  final double? arousalIndex;

  /// Stability of affective state (0.0 - 1.0)
  /// Higher values indicate more stable affect over time
  final double? valenceStability;

  AffectAxis({
    this.arousalIndex,
    this.valenceStability,
  });

  factory AffectAxis.fromJson(Map<String, dynamic> json) =>
      _$AffectAxisFromJson(json);

  Map<String, dynamic> toJson() => _$AffectAxisToJson(this);

  factory AffectAxis.empty() => AffectAxis(
        arousalIndex: null,
        valenceStability: null,
      );
}

/// Engagement Axis - Digital interaction patterns
@JsonSerializable()
class EngagementAxis {
  /// Consistency of interaction patterns (0.0 - 1.0)
  /// Higher values indicate more stable engagement
  final double? engagementStability;

  /// Rhythm of digital interactions (0.0 - 1.0)
  /// Higher values indicate faster, more consistent interaction cadence
  final double? interactionCadence;

  EngagementAxis({
    this.engagementStability,
    this.interactionCadence,
  });

  factory EngagementAxis.fromJson(Map<String, dynamic> json) =>
      _$EngagementAxisFromJson(json);

  Map<String, dynamic> toJson() => _$EngagementAxisToJson(this);

  factory EngagementAxis.empty() => EngagementAxis(
        engagementStability: null,
        interactionCadence: null,
      );
}

/// Activity Axis - Physical activity and motion
@JsonSerializable()
class ActivityAxis {
  /// Physical activity level (0.0 - 1.0)
  /// Derived from accelerometer and gyroscope data
  final double? motionIndex;

  /// Postural stability (0.0 - 1.0)
  /// Higher values indicate more stable posture/position
  final double? postureStability;

  ActivityAxis({
    this.motionIndex,
    this.postureStability,
  });

  factory ActivityAxis.fromJson(Map<String, dynamic> json) =>
      _$ActivityAxisFromJson(json);

  Map<String, dynamic> toJson() => _$ActivityAxisToJson(this);

  factory ActivityAxis.empty() => ActivityAxis(
        motionIndex: null,
        postureStability: null,
      );
}

/// Context Axis - Environmental and device state
@JsonSerializable()
class ContextAxis {
  /// Screen on/off ratio (0.0 - 1.0)
  /// Proportion of time screen was active in window
  final double? screenActiveRatio;

  /// App switching frequency (0.0 - 1.0)
  /// Higher values indicate more fragmented sessions
  final double? sessionFragmentation;

  ContextAxis({
    this.screenActiveRatio,
    this.sessionFragmentation,
  });

  factory ContextAxis.fromJson(Map<String, dynamic> json) =>
      _$ContextAxisFromJson(json);

  Map<String, dynamic> toJson() => _$ContextAxisToJson(this);

  factory ContextAxis.empty() => ContextAxis(
        screenActiveRatio: null,
        sessionFragmentation: null,
      );
}

/// State Embedding - Dense vector representation of fused multimodal state
@JsonSerializable()
class StateEmbedding {
  /// 64-dimensional dense vector representing fused state
  final List<double> vector;

  /// Dimension (always 64)
  final int dimension;

  /// Model identifier
  final String model;

  /// Timestamp when embedding was computed
  final int timestamp;

  /// Window type this embedding represents
  final String windowType;

  StateEmbedding({
    required this.vector,
    this.dimension = 64,
    this.model = 'hsi-fusion-v1',
    required this.timestamp,
    required this.windowType,
  });

  factory StateEmbedding.fromJson(Map<String, dynamic> json) =>
      _$StateEmbeddingFromJson(json);

  Map<String, dynamic> toJson() => _$StateEmbeddingToJson(this);

  factory StateEmbedding.empty({required int timestamp}) => StateEmbedding(
        vector: List.filled(64, 0.0),
        timestamp: timestamp,
        windowType: 'micro',
      );
}
