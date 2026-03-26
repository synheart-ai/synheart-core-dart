/// State quality assessment aligned with synheart-runtime HSV.
///
/// Mirrors `StateQuality` from synheart-runtime — aggregated quality metadata describing
/// the overall reliability of the current Human State Vector.

/// Quality flags that can be raised on the HSV.
enum HsvQualityFlag {
  /// At least one modality has stale data.
  staleData,

  /// Only a single modality contributed (low fusion diversity).
  singleModality,

  /// Baselines have not yet converged (insufficient history).
  lowBaselineHistory,

  /// Sensor data had gaps or interpolation was needed.
  sensorGaps,
}

/// Aggregated quality assessment for the Human State Vector.
///
/// Summarizes the reliability and completeness of the fused state.
/// Downstream consumers can use [overallConfidence]
/// and [degraded] to decide whether to export or gate readings.
class StateQuality {
  /// Overall confidence in the fused HSV, [0.0, 1.0].
  /// Computed as a weighted average of per-modality confidences.
  final double overallConfidence;

  /// Number of modalities that contributed data (0–3: physiology, behavior, context).
  final int modalityCount;

  /// True when quality is below acceptable thresholds.
  final bool degraded;

  /// Set of active quality flags.
  final Set<HsvQualityFlag> qualityFlags;

  const StateQuality({
    this.overallConfidence = 0.0,
    this.modalityCount = 0,
    this.degraded = true,
    this.qualityFlags = const {},
  });

  factory StateQuality.fromJson(Map<String, dynamic> json) {
    return StateQuality(
      overallConfidence: (json['overall_confidence'] as num?)?.toDouble() ?? 0.0,
      modalityCount: (json['modality_count'] as num?)?.toInt() ?? 0,
      degraded: json['degraded'] as bool? ?? true,
      qualityFlags: ((json['quality_flags'] as List<dynamic>?) ?? [])
          .map((f) => HsvQualityFlag.values.firstWhere(
                (e) => e.name == f,
                orElse: () => HsvQualityFlag.staleData,
              ))
          .toSet(),
    );
  }

  Map<String, dynamic> toJson() => {
    'overall_confidence': overallConfidence,
    'modality_count': modalityCount,
    'degraded': degraded,
    'quality_flags': qualityFlags.map((f) => f.name).toList(),
  };

  /// Default quality indicating no data available.
  static const StateQuality empty = StateQuality();
}
