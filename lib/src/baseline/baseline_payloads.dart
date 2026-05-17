import '../models/sleep_score.dart' show WearableReferenceView;
import 'baseline_kind.dart';

/// Mean / std / confidence triplet for one axis or metric.
class AxisStats {
  final double mean;
  final double std;

  /// 0.0–1.0. Same semantics as the per-dimension wearable confidence.
  final double confidence;

  const AxisStats({
    required this.mean,
    required this.std,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
    'mean': mean,
    'std': std,
    'confidence': confidence,
  };

  factory AxisStats.fromJson(Map<String, dynamic> json) => AxisStats(
    mean: (json['mean'] as num).toDouble(),
    std: (json['std'] as num).toDouble(),
    confidence: (json['confidence'] as num).toDouble(),
  );
}

/// Marker for any typed baseline payload. Bounds the generic payload
/// extractor surface on `BaselineSnapshots`.
abstract class BaselinePayload {
  /// Per-payload schema version. Independent across kinds — a bump on
  /// one kind does not force changes on the others.
  int get schemaVersion;
}

// ---------------------------------------------------------------------------
// kind = "session.hsi_axes"
// ---------------------------------------------------------------------------

/// HSI axes aggregator output for one session. `axes` is a
/// string-keyed map (not a fixed 4-field struct) so future HSI
/// versions can publish additional axes without a payload schema bump.
class HsiAxesBaseline implements BaselinePayload {
  @override
  final int schemaVersion;
  final Map<String, AxisStats> axes;

  const HsiAxesBaseline({required this.schemaVersion, required this.axes});

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'axes': {for (final e in axes.entries) e.key: e.value.toJson()},
  };

  factory HsiAxesBaseline.fromJson(Map<String, dynamic> json) {
    final raw = (json['axes'] as Map?)?.cast<String, Object?>() ?? const {};
    final out = <String, AxisStats>{};
    for (final e in raw.entries) {
      final v = e.value;
      if (v is Map) {
        out[e.key] = AxisStats.fromJson(v.cast<String, dynamic>());
      }
    }
    return HsiAxesBaseline(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      axes: out,
    );
  }
}

// ---------------------------------------------------------------------------
// kind = "session.srm_metrics"
// ---------------------------------------------------------------------------

/// Per-metric session SRM baseline.
class SrmMetricBaseline {
  final double muTilde;
  final double sigmaTilde;
  final SrmMetricStatus status;
  final int nEff;

  const SrmMetricBaseline({
    required this.muTilde,
    required this.sigmaTilde,
    required this.status,
    required this.nEff,
  });

  Map<String, dynamic> toJson() => {
    'mu_tilde': muTilde,
    'sigma_tilde': sigmaTilde,
    'status': status.wire,
    'n_eff': nEff,
  };

  factory SrmMetricBaseline.fromJson(Map<String, dynamic> json) =>
      SrmMetricBaseline(
        muTilde: (json['mu_tilde'] as num).toDouble(),
        sigmaTilde: (json['sigma_tilde'] as num).toDouble(),
        status:
            SrmMetricStatus.fromWire(json['status'] as String?) ??
            SrmMetricStatus.empty,
        nEff: (json['n_eff'] as num?)?.toInt() ?? 0,
      );
}

/// `SrmEngine`'s per-session output.
class SessionSrmMetricsBaseline implements BaselinePayload {
  @override
  final int schemaVersion;
  final Map<String, SrmMetricBaseline> metrics;

  const SessionSrmMetricsBaseline({
    required this.schemaVersion,
    required this.metrics,
  });

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'metrics': {for (final e in metrics.entries) e.key: e.value.toJson()},
  };

  factory SessionSrmMetricsBaseline.fromJson(Map<String, dynamic> json) {
    final raw = (json['metrics'] as Map?)?.cast<String, Object?>() ?? const {};
    final out = <String, SrmMetricBaseline>{};
    for (final e in raw.entries) {
      final v = e.value;
      if (v is Map) {
        out[e.key] = SrmMetricBaseline.fromJson(v.cast<String, dynamic>());
      }
    }
    return SessionSrmMetricsBaseline(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      metrics: out,
    );
  }
}

// ---------------------------------------------------------------------------
// kind = "longitudinal.wear"
// ---------------------------------------------------------------------------

/// Payload wrapper for the `longitudinal.wear` kind.
///
/// The bare [WearableReferenceView] is already reachable via
/// `Synheart.wearableReference` (FFI hot path); this wrapper adds the
/// kind-local `schemaVersion` for envelope round-tripping.
class LongitudinalWearBaseline implements BaselinePayload {
  @override
  final int schemaVersion;
  final WearableReferenceView reference;

  const LongitudinalWearBaseline({
    required this.schemaVersion,
    required this.reference,
  });

  Map<String, dynamic> toJson() {
    // Wire shape: the reference's fields are top-level alongside
    // `schema_version` (flat, no nested `reference` object).
    final dims = <String, dynamic>{};
    reference.dimensions.forEach((k, v) => dims[k] = v);
    if (reference.recentSleepScoreMedian != null) {
      dims['recent_sleep_score_median'] = reference.recentSleepScoreMedian;
    }
    final conf = <String, dynamic>{};
    reference.confidence.forEach((k, v) => conf[k] = v);

    return {
      'schema_version': schemaVersion,
      'status': reference.status,
      if (reference.modelVersion != null)
        'model_version': reference.modelVersion,
      'dimensions': dims,
      'confidence': conf,
    };
  }

  factory LongitudinalWearBaseline.fromJson(Map<String, dynamic> json) =>
      LongitudinalWearBaseline(
        schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
        reference: WearableReferenceView.fromJson(
          // WearableReferenceView.fromJson expects `Map<String, Object?>`
          // with status / model_version / dimensions / confidence —
          // the same flattened shape we emit in toJson above.
          json.cast<String, Object?>(),
        ),
      );
}
