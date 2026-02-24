/// Physiology domain types aligned with synheart-runtime HSV.
///
/// These types mirror the `PhysiologyState` and `HsvAxisValue` from
/// synheart-runtime, providing per-axis score + confidence pairs for all
/// physiological readings.

/// A single HSV axis reading: optional score with associated confidence.
///
/// Mirrors `HsvAxisValue { score: Option<f32>, confidence: f32 }` from synheart-runtime.
/// Score is null when the signal is unavailable; confidence reflects
/// measurement quality independent of the score value.
class HsvAxisValue {
  /// Normalized score in [0.0, 1.0], or null if signal unavailable.
  final double? score;

  /// Confidence in the reading [0.0, 1.0].
  /// A value of 0.0 means no confidence; 1.0 means full confidence.
  final double confidence;

  const HsvAxisValue({this.score, this.confidence = 0.0});

  /// Convenience: whether a usable score is present.
  bool get isPresent => score != null;

  factory HsvAxisValue.fromJson(Map<String, dynamic> json) {
    return HsvAxisValue(
      score: (json['score'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'score': score,
    'confidence': confidence,
  };

  /// An absent axis value with zero confidence.
  static const HsvAxisValue absent = HsvAxisValue(score: null, confidence: 0.0);
}

/// Physiology domain of the Human State Vector.
///
/// Contains all wearable-derived physiological readings, each paired with
/// a confidence score. Mirrors `PhysiologyState` from synheart-runtime.
///
/// Populated by wearable adapters (WHOOP, Garmin, etc.) via the biosignal
/// pipeline. Emotion and Focus heads in external SDKs (synheart-emotion,
/// synheart-focus) may consume these values but do NOT populate them.
class PhysiologyState {
  /// Sleep efficiency (0–1). Higher is better.
  final HsvAxisValue sleepEfficiency;

  /// Recovery score (0–1). Higher indicates better recovery.
  final HsvAxisValue recoveryScore;

  /// HRV deviation from personal baseline (0–1, 0.5 = at baseline).
  final HsvAxisValue hrvDeviation;

  /// Resting heart rate deviation from baseline (0–1, 0.5 = at baseline).
  final HsvAxisValue rhrDeviation;

  /// Respiratory rate normalized (0–1).
  final HsvAxisValue respiratoryRate;

  /// Blood oxygen saturation normalized (0–1).
  final HsvAxisValue spo2;

  /// Physical strain / exertion (0–1). Higher means more strain.
  final HsvAxisValue strain;

  /// Sleep duration ratio vs. target (0–1).
  final HsvAxisValue sleepDuration;

  /// Deep sleep ratio (0–1).
  final HsvAxisValue deepSleepRatio;

  /// REM sleep ratio (0–1).
  final HsvAxisValue remSleepRatio;

  /// Sleep fragmentation index (0–1). Higher means more fragmented.
  final HsvAxisValue sleepFragmentation;

  const PhysiologyState({
    this.sleepEfficiency = HsvAxisValue.absent,
    this.recoveryScore = HsvAxisValue.absent,
    this.hrvDeviation = HsvAxisValue.absent,
    this.rhrDeviation = HsvAxisValue.absent,
    this.respiratoryRate = HsvAxisValue.absent,
    this.spo2 = HsvAxisValue.absent,
    this.strain = HsvAxisValue.absent,
    this.sleepDuration = HsvAxisValue.absent,
    this.deepSleepRatio = HsvAxisValue.absent,
    this.remSleepRatio = HsvAxisValue.absent,
    this.sleepFragmentation = HsvAxisValue.absent,
  });

  /// Count of axes that have a present (non-null) score.
  int get presentCount {
    int count = 0;
    for (final axis in allAxes) {
      if (axis.isPresent) count++;
    }
    return count;
  }

  /// All axis values in declaration order.
  List<HsvAxisValue> get allAxes => [
    sleepEfficiency, recoveryScore, hrvDeviation, rhrDeviation,
    respiratoryRate, spo2, strain, sleepDuration, deepSleepRatio,
    remSleepRatio, sleepFragmentation,
  ];

  factory PhysiologyState.fromJson(Map<String, dynamic> json) {
    HsvAxisValue axis(String key) =>
        json[key] != null ? HsvAxisValue.fromJson(json[key] as Map<String, dynamic>) : HsvAxisValue.absent;

    return PhysiologyState(
      sleepEfficiency: axis('sleep_efficiency'),
      recoveryScore: axis('recovery_score'),
      hrvDeviation: axis('hrv_deviation'),
      rhrDeviation: axis('rhr_deviation'),
      respiratoryRate: axis('respiratory_rate'),
      spo2: axis('spo2'),
      strain: axis('strain'),
      sleepDuration: axis('sleep_duration'),
      deepSleepRatio: axis('deep_sleep_ratio'),
      remSleepRatio: axis('rem_sleep_ratio'),
      sleepFragmentation: axis('sleep_fragmentation'),
    );
  }

  Map<String, dynamic> toJson() => {
    'sleep_efficiency': sleepEfficiency.toJson(),
    'recovery_score': recoveryScore.toJson(),
    'hrv_deviation': hrvDeviation.toJson(),
    'rhr_deviation': rhrDeviation.toJson(),
    'respiratory_rate': respiratoryRate.toJson(),
    'spo2': spo2.toJson(),
    'strain': strain.toJson(),
    'sleep_duration': sleepDuration.toJson(),
    'deep_sleep_ratio': deepSleepRatio.toJson(),
    'rem_sleep_ratio': remSleepRatio.toJson(),
    'sleep_fragmentation': sleepFragmentation.toJson(),
  };

  /// Empty physiology with no present axes.
  static const PhysiologyState empty = PhysiologyState();
}
