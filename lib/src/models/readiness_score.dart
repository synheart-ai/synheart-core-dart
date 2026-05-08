// Typed Dart models for the RFC-READINESS-SCORE-0001 daily scorer.
//
// Mirrors the JSON shapes produced by the Synheart Runtime's
// `ReadinessScore` computation. Field names use snake_case JSON
// keys for cross-language portability.
//
// Readiness layers acute / fatigue / history context on top of
// today's Recovery Score to answer:
//
//     "How much strain should the user take today?"

import 'dart:convert';

/// Discrete action label derived from the score.
enum ReadinessBand {
  rest('rest'),
  light('light'),
  normal('normal'),
  push('push');

  final String wire;
  const ReadinessBand(this.wire);

  static ReadinessBand fromWire(String s) => ReadinessBand.values.firstWhere(
    (v) => v.wire == s,
    orElse: () => ReadinessBand.rest,
  );

  String get label {
    switch (this) {
      case ReadinessBand.rest:
        return 'Rest';
      case ReadinessBand.light:
        return 'Light';
      case ReadinessBand.normal:
        return 'Normal';
      case ReadinessBand.push:
        return 'Push';
    }
  }
}

/// Discrete reasons surfaced for "why is your readiness X?" panels.
enum ReadinessFactor {
  strongRecovery('strong_recovery'),
  lowRecovery('low_recovery'),
  acuteLoadHigh('acute_load_high'),
  acuteLoadOptimal('acute_load_optimal'),
  sleepDebt('sleep_debt'),
  recoveryDeclining('recovery_declining'),
  consecutiveOverload('consecutive_overload'),
  noRecentRest('no_recent_rest'),
  anchorOnly('anchor_only');

  final String wire;
  const ReadinessFactor(this.wire);

  static ReadinessFactor? fromWire(String s) {
    for (final v in ReadinessFactor.values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

/// Acute / chronic workload context. Hosts can either pre-compute
/// `acuteChronicRatio` or pass the raw loads.
class AcuteWorkloadContext {
  final double? acuteLoad;
  final double? chronicLoad;
  final double? acuteChronicRatio;

  const AcuteWorkloadContext({
    this.acuteLoad,
    this.chronicLoad,
    this.acuteChronicRatio,
  });

  Map<String, Object?> toJson() => {
    'acute_load': acuteLoad,
    'chronic_load': chronicLoad,
    'acute_chronic_ratio': acuteChronicRatio,
  };
}

/// Short-window fatigue indicators.
class FatigueContext {
  final double? sleepDebtHours;
  final double? recoverySlopePerDay;
  final double? recovery7dMean;

  const FatigueContext({
    this.sleepDebtHours,
    this.recoverySlopePerDay,
    this.recovery7dMean,
  });

  Map<String, Object?> toJson() => {
    'sleep_debt_hours': sleepDebtHours,
    'recovery_slope_per_day': recoverySlopePerDay,
    'recovery_7d_mean': recovery7dMean,
  };
}

/// Training-history context.
class HistoryContext {
  final int? consecutiveHighStrainDays;
  final int? daysSinceRest;

  const HistoryContext({this.consecutiveHighStrainDays, this.daysSinceRest});

  Map<String, Object?> toJson() => {
    'consecutive_high_strain_days': consecutiveHighStrainDays,
    'days_since_rest': daysSinceRest,
  };
}

/// Top-level input bundle. Recovery score is required; everything
/// else is optional and improves confidence when present.
class ReadinessScoreInput {
  final int recoveryScore;
  final double? recoveryConfidence;
  final AcuteWorkloadContext? acuteWorkload;
  final FatigueContext? fatigue;
  final HistoryContext? history;

  const ReadinessScoreInput({
    required this.recoveryScore,
    this.recoveryConfidence,
    this.acuteWorkload,
    this.fatigue,
    this.history,
  });

  /// Build an input from only the recovery score; downstream context
  /// stays empty. Useful while a host is still wiring fatigue / load.
  factory ReadinessScoreInput.fromRecovery(int recoveryScore) =>
      ReadinessScoreInput(recoveryScore: recoveryScore);

  Map<String, Object?> toJson() => {
    'recovery_score': recoveryScore,
    'recovery_confidence': recoveryConfidence,
    'acute_workload': acuteWorkload?.toJson(),
    'fatigue': fatigue?.toJson(),
    'history': history?.toJson(),
  };

  String toJsonString() => jsonEncode(toJson());
}

/// Per-component breakdown.
class ReadinessComponents {
  final double recovery;
  final double? acuteLoad;
  final double? fatigue;
  final double? history;

  const ReadinessComponents({
    required this.recovery,
    this.acuteLoad,
    this.fatigue,
    this.history,
  });

  factory ReadinessComponents.fromJson(Map<String, Object?> json) =>
      ReadinessComponents(
        recovery: (json['recovery'] as num?)?.toDouble() ?? 0.0,
        acuteLoad: (json['acute_load'] as num?)?.toDouble(),
        fatigue: (json['fatigue'] as num?)?.toDouble(),
        history: (json['history'] as num?)?.toDouble(),
      );
}

/// Canonical output of the Readiness Score scorer.
class ReadinessScoreResult {
  final int score;
  final ReadinessBand band;
  final int recoveryAnchor;
  final ReadinessComponents components;
  final double confidence;
  final List<ReadinessFactor> explanation;
  final String modelId;
  final String modelVersion;
  final String pipelineVersion;

  const ReadinessScoreResult({
    required this.score,
    required this.band,
    required this.recoveryAnchor,
    required this.components,
    required this.confidence,
    this.explanation = const [],
    required this.modelId,
    required this.modelVersion,
    required this.pipelineVersion,
  });

  factory ReadinessScoreResult.fromJson(Map<String, Object?> json) {
    final rawExpl = (json['explanation'] as List?) ?? const [];
    final factors = <ReadinessFactor>[];
    for (final e in rawExpl) {
      if (e is String) {
        final f = ReadinessFactor.fromWire(e);
        if (f != null) factors.add(f);
      }
    }
    return ReadinessScoreResult(
      score: (json['score'] as num?)?.toInt() ?? 0,
      band: ReadinessBand.fromWire(json['band'] as String? ?? 'rest'),
      recoveryAnchor: (json['recovery_anchor'] as num?)?.toInt() ?? 0,
      components: ReadinessComponents.fromJson(
        (json['components'] as Map?)?.cast<String, Object?>() ?? {},
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      explanation: factors,
      modelId: json['model_id'] as String? ?? '',
      modelVersion: json['model_version'] as String? ?? '',
      pipelineVersion: json['pipeline_version'] as String? ?? '',
    );
  }

  factory ReadinessScoreResult.fromJsonString(String s) =>
      ReadinessScoreResult.fromJson(jsonDecode(s) as Map<String, Object?>);
}
