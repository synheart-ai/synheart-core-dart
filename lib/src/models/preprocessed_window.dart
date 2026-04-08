/// Pre-processed Window - INTERNAL ONLY
///
/// Intermediate signal processing and feature extraction output from synheart-engine.
/// Contains quality metrics, derived features, SRM baseline context, and embeddings.
///
/// Used internally for:
/// - On-device model training (transfer learning, fine-tuning)
/// - Research & development (feature engineering, validation)
/// - Diagnostics & debugging (signal quality, pipeline inspection)
/// - Custom inference (alternative models, multi-modal fusion)
///
/// This is NOT part of the public API - follows same internal-only pattern as HSV.
class PreprocessedWindow {
  final String schemaVersion;
  final int windowStartMs;
  final int windowEndMs;
  final String sessionId;
  final Quality quality;
  final DerivedFeatures derivedFeatures;
  final BehaviorFeatures? behaviorFeatures;
  final SrmContext srmContext;
  final Embeddings embeddings;

  PreprocessedWindow({
    required this.schemaVersion,
    required this.windowStartMs,
    required this.windowEndMs,
    required this.sessionId,
    required this.quality,
    required this.derivedFeatures,
    this.behaviorFeatures,
    required this.srmContext,
    required this.embeddings,
  });

  factory PreprocessedWindow.fromJson(Map<String, dynamic> json) {
    return PreprocessedWindow(
      schemaVersion: json['schema_version'] as String? ?? '1.0.0',
      windowStartMs: json['window_start_ms'] as int? ?? 0,
      windowEndMs: json['window_end_ms'] as int? ?? 0,
      sessionId: json['session_id'] as String? ?? '',
      quality: Quality.fromJson(json['quality'] as Map<String, dynamic>? ?? {}),
      derivedFeatures: DerivedFeatures.fromJson(
        json['derived_features'] as Map<String, dynamic>? ?? {},
      ),
      behaviorFeatures: json['behavior_features'] != null
          ? BehaviorFeatures.fromJson(
              json['behavior_features'] as Map<String, dynamic>)
          : null,
      srmContext:
          SrmContext.fromJson(json['srm_context'] as Map<String, dynamic>? ?? {}),
      embeddings:
          Embeddings.fromJson(json['embeddings'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'window_start_ms': windowStartMs,
        'window_end_ms': windowEndMs,
        'session_id': sessionId,
        'quality': quality.toJson(),
        'derived_features': derivedFeatures.toJson(),
        'behavior_features': behaviorFeatures?.toJson(),
        'srm_context': srmContext.toJson(),
        'embeddings': embeddings.toJson(),
      };
}

/// Quality metrics for the window
class Quality {
  final double score;
  final double coveragePct;
  final int dropoutCount;
  final int rrCount;
  final double artifactPct;

  Quality({
    required this.score,
    required this.coveragePct,
    required this.dropoutCount,
    required this.rrCount,
    required this.artifactPct,
  });

  factory Quality.fromJson(Map<String, dynamic> json) {
    return Quality(
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      coveragePct: (json['coverage_pct'] as num?)?.toDouble() ?? 0.0,
      dropoutCount: json['dropout_count'] as int? ?? 0,
      rrCount: json['rr_count'] as int? ?? 0,
      artifactPct: (json['artifact_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'score': score,
        'coverage_pct': coveragePct,
        'dropout_count': dropoutCount,
        'rr_count': rrCount,
        'artifact_pct': artifactPct,
      };
}

/// HRV features derived from RR intervals
class HrvFeatures {
  final double rmssdMs;
  final double sdnnMs;
  final double pnn50;
  final double meanRrMs;
  final double hrMeanBpm;
  final double hrStdBpm;
  final int rrCount;

  HrvFeatures({
    required this.rmssdMs,
    required this.sdnnMs,
    required this.pnn50,
    required this.meanRrMs,
    required this.hrMeanBpm,
    required this.hrStdBpm,
    required this.rrCount,
  });

  factory HrvFeatures.fromJson(Map<String, dynamic> json) {
    return HrvFeatures(
      rmssdMs: (json['rmssd_ms'] as num?)?.toDouble() ?? 0.0,
      sdnnMs: (json['sdnn_ms'] as num?)?.toDouble() ?? 0.0,
      pnn50: (json['pnn50'] as num?)?.toDouble() ?? 0.0,
      meanRrMs: (json['mean_rr_ms'] as num?)?.toDouble() ?? 0.0,
      hrMeanBpm: (json['hr_mean_bpm'] as num?)?.toDouble() ?? 0.0,
      hrStdBpm: (json['hr_std_bpm'] as num?)?.toDouble() ?? 0.0,
      rrCount: json['rr_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'rmssd_ms': rmssdMs,
        'sdnn_ms': sdnnMs,
        'pnn50': pnn50,
        'mean_rr_ms': meanRrMs,
        'hr_mean_bpm': hrMeanBpm,
        'hr_std_bpm': hrStdBpm,
        'rr_count': rrCount,
      };
}

/// Motion features from accelerometer
class MotionFeatures {
  final double accelRms;
  final double accelVar;
  final int stepsEst;
  final double postureProxy;
  final int sampleCount;

  MotionFeatures({
    required this.accelRms,
    required this.accelVar,
    required this.stepsEst,
    required this.postureProxy,
    required this.sampleCount,
  });

  factory MotionFeatures.fromJson(Map<String, dynamic> json) {
    return MotionFeatures(
      accelRms: (json['accel_rms'] as num?)?.toDouble() ?? 0.0,
      accelVar: (json['accel_var'] as num?)?.toDouble() ?? 0.0,
      stepsEst: json['steps_est'] as int? ?? 0,
      postureProxy: (json['posture_proxy'] as num?)?.toDouble() ?? 0.0,
      sampleCount: json['sample_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'accel_rms': accelRms,
        'accel_var': accelVar,
        'steps_est': stepsEst,
        'posture_proxy': postureProxy,
        'sample_count': sampleCount,
      };
}

/// Artifact filtering results
class ArtifactResult {
  final double artifactPct;
  final double ectopicLikePct;
  final int originalCount;

  ArtifactResult({
    required this.artifactPct,
    required this.ectopicLikePct,
    required this.originalCount,
  });

  factory ArtifactResult.fromJson(Map<String, dynamic> json) {
    return ArtifactResult(
      artifactPct: (json['artifact_pct'] as num?)?.toDouble() ?? 0.0,
      ectopicLikePct: (json['ectopic_like_pct'] as num?)?.toDouble() ?? 0.0,
      originalCount: json['original_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'artifact_pct': artifactPct,
        'ectopic_like_pct': ectopicLikePct,
        'original_count': originalCount,
      };
}

/// Derived features (HRV, motion, artifact)
class DerivedFeatures {
  final HrvFeatures? hrv;
  final MotionFeatures? motion;
  final ArtifactResult? artifact;

  DerivedFeatures({
    this.hrv,
    this.motion,
    this.artifact,
  });

  factory DerivedFeatures.fromJson(Map<String, dynamic> json) {
    return DerivedFeatures(
      hrv: json['hrv'] != null
          ? HrvFeatures.fromJson(json['hrv'] as Map<String, dynamic>)
          : null,
      motion: json['motion'] != null
          ? MotionFeatures.fromJson(json['motion'] as Map<String, dynamic>)
          : null,
      artifact: json['artifact'] != null
          ? ArtifactResult.fromJson(json['artifact'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'hrv': hrv?.toJson(),
        'motion': motion?.toJson(),
        'artifact': artifact?.toJson(),
      };
}

/// Behavior features from phone interaction
class BehaviorFeatures {
  final double screenOnPct;
  final double touchRatePerMin;
  final double appSwitchesPerMin;
  final int notificationInterruptions;

  BehaviorFeatures({
    required this.screenOnPct,
    required this.touchRatePerMin,
    required this.appSwitchesPerMin,
    required this.notificationInterruptions,
  });

  factory BehaviorFeatures.fromJson(Map<String, dynamic> json) {
    return BehaviorFeatures(
      screenOnPct: (json['screen_on_pct'] as num?)?.toDouble() ?? 0.0,
      touchRatePerMin: (json['touch_rate_per_min'] as num?)?.toDouble() ?? 0.0,
      appSwitchesPerMin:
          (json['app_switches_per_min'] as num?)?.toDouble() ?? 0.0,
      notificationInterruptions:
          json['notification_interruptions'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'screen_on_pct': screenOnPct,
        'touch_rate_per_min': touchRatePerMin,
        'app_switches_per_min': appSwitchesPerMin,
        'notification_interruptions': notificationInterruptions,
      };
}

/// SRM baseline deviation context
class SrmDeviation {
  final double observed;
  final double mu;
  final double sigma;
  final double zScore;
  final String status; // "Ready", "Warming", "Empty"

  SrmDeviation({
    required this.observed,
    required this.mu,
    required this.sigma,
    required this.zScore,
    required this.status,
  });

  factory SrmDeviation.fromJson(Map<String, dynamic> json) {
    return SrmDeviation(
      observed: (json['observed'] as num?)?.toDouble() ?? 0.0,
      mu: (json['mu'] as num?)?.toDouble() ?? 0.0,
      sigma: (json['sigma'] as num?)?.toDouble() ?? 0.0,
      zScore: (json['z_score'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'Empty',
    );
  }

  Map<String, dynamic> toJson() => {
        'observed': observed,
        'mu': mu,
        'sigma': sigma,
        'z_score': zScore,
        'status': status,
      };
}

/// SRM baseline context with deviations
class SrmContext {
  final int readyCount;
  final int totalCount;
  final Map<String, SrmDeviation> deviations;

  SrmContext({
    required this.readyCount,
    required this.totalCount,
    required this.deviations,
  });

  factory SrmContext.fromJson(Map<String, dynamic> json) {
    final deviationsJson =
        json['deviations'] as Map<String, dynamic>? ?? {};
    final deviations = <String, SrmDeviation>{};

    deviationsJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        deviations[key] = SrmDeviation.fromJson(value);
      }
    });

    return SrmContext(
      readyCount: json['ready_count'] as int? ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
      deviations: deviations,
    );
  }

  Map<String, dynamic> toJson() {
    final deviationsJson = <String, Map<String, dynamic>>{};
    deviations.forEach((key, value) {
      deviationsJson[key] = value.toJson();
    });

    return {
      'ready_count': readyCount,
      'total_count': totalCount,
      'deviations': deviationsJson,
    };
  }
}

/// Signal embedding
class SignalEmbedding {
  final List<double> vector;
  final int dimension;
  final String space;

  SignalEmbedding({
    required this.vector,
    required this.dimension,
    required this.space,
  });

  factory SignalEmbedding.fromJson(Map<String, dynamic> json) {
    return SignalEmbedding(
      vector: (json['vector'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      dimension: json['dimension'] as int? ?? 0,
      space: json['space'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'vector': vector,
        'dimension': dimension,
        'space': space,
      };
}

/// Embeddings (signal, behavior, combined)
class Embeddings {
  final SignalEmbedding signalEmbedding;

  Embeddings({
    required this.signalEmbedding,
  });

  factory Embeddings.fromJson(Map<String, dynamic> json) {
    return Embeddings(
      signalEmbedding: SignalEmbedding.fromJson(
        json['signal_embedding'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'signal_embedding': signalEmbedding.toJson(),
      };
}
