/// HSV State Axes - Core state representation indices
///
/// These axes form the internal HSV (Human State Vector) representation.
/// All indices are normalized to [0.0, 1.0] range.
/// Missing signals result in null values (not 0.0).

/// Affect Axis - Physiological arousal and emotional stability
class AffectAxis {
  final double? arousalIndex;
  final double? valenceStability;

  AffectAxis({this.arousalIndex, this.valenceStability});

  factory AffectAxis.fromJson(Map<String, dynamic> json) => AffectAxis(
    arousalIndex: (json['arousalIndex'] as num?)?.toDouble(),
    valenceStability: (json['valenceStability'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    if (arousalIndex != null) 'arousalIndex': arousalIndex,
    if (valenceStability != null) 'valenceStability': valenceStability,
  };

  factory AffectAxis.empty() => AffectAxis();
}

/// Engagement Axis - Digital interaction patterns
class EngagementAxis {
  final double? engagementStability;
  final double? interactionCadence;

  EngagementAxis({this.engagementStability, this.interactionCadence});

  factory EngagementAxis.fromJson(Map<String, dynamic> json) => EngagementAxis(
    engagementStability: (json['engagementStability'] as num?)?.toDouble(),
    interactionCadence: (json['interactionCadence'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    if (engagementStability != null) 'engagementStability': engagementStability,
    if (interactionCadence != null) 'interactionCadence': interactionCadence,
  };

  factory EngagementAxis.empty() => EngagementAxis();
}

/// Activity Axis - Physical activity and motion
class ActivityAxis {
  final double? motionIndex;
  final double? postureStability;

  ActivityAxis({this.motionIndex, this.postureStability});

  factory ActivityAxis.fromJson(Map<String, dynamic> json) => ActivityAxis(
    motionIndex: (json['motionIndex'] as num?)?.toDouble(),
    postureStability: (json['postureStability'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    if (motionIndex != null) 'motionIndex': motionIndex,
    if (postureStability != null) 'postureStability': postureStability,
  };

  factory ActivityAxis.empty() => ActivityAxis();
}

/// Context Axis - Environmental and device state
class ContextAxis {
  final double? screenActiveRatio;
  final double? sessionFragmentation;

  ContextAxis({this.screenActiveRatio, this.sessionFragmentation});

  factory ContextAxis.fromJson(Map<String, dynamic> json) => ContextAxis(
    screenActiveRatio: (json['screenActiveRatio'] as num?)?.toDouble(),
    sessionFragmentation: (json['sessionFragmentation'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    if (screenActiveRatio != null) 'screenActiveRatio': screenActiveRatio,
    if (sessionFragmentation != null)
      'sessionFragmentation': sessionFragmentation,
  };

  factory ContextAxis.empty() => ContextAxis();
}

/// State Embedding - Dense vector representation of fused multimodal state
class StateEmbedding {
  final List<double> vector;
  final int dimension;
  final String model;
  final int timestamp;
  final String windowType;

  StateEmbedding({
    required this.vector,
    this.dimension = 64,
    this.model = 'hsi-fusion-v1',
    required this.timestamp,
    required this.windowType,
  });

  factory StateEmbedding.fromJson(Map<String, dynamic> json) => StateEmbedding(
    vector: (json['vector'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList(),
    dimension: json['dimension'] as int? ?? 64,
    model: json['model'] as String? ?? 'hsi-fusion-v1',
    timestamp: json['timestamp'] as int,
    windowType: json['windowType'] as String,
  );

  Map<String, dynamic> toJson() => {
    'vector': vector,
    'dimension': dimension,
    'model': model,
    'timestamp': timestamp,
    'windowType': windowType,
  };

  factory StateEmbedding.empty({required int timestamp}) => StateEmbedding(
    vector: List.filled(64, 0.0),
    timestamp: timestamp,
    windowType: 'micro',
  );
}
