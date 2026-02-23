import 'srm_stratum.dart';
import 'srm_baseline_status.dart';

/// A candidate window submitted by Flux for SRM consideration.
///
/// Contains the metrics and metadata needed for quality gating,
/// outlier rejection, and buffer update (SRM.pdf §4).
class CandidateWindow {
  final String sessionId;
  final String windowId;
  final SRMStratum stratum;
  final Map<String, double> metrics;
  final double qualityScore;
  final double motionScore;
  final double durationSeconds;
  final DateTime observedAtUtc;

  const CandidateWindow({
    required this.sessionId,
    required this.windowId,
    required this.stratum,
    required this.metrics,
    required this.qualityScore,
    required this.motionScore,
    required this.durationSeconds,
    required this.observedAtUtc,
  });

  /// Check if any metric value is NaN or Inf.
  bool get hasInvalidValues {
    if (qualityScore.isNaN || qualityScore.isInfinite) return true;
    if (motionScore.isNaN || motionScore.isInfinite) return true;
    if (durationSeconds.isNaN || durationSeconds.isInfinite) return true;
    for (final v in metrics.values) {
      if (v.isNaN || v.isInfinite) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'window_id': windowId,
    'stratum': stratum.name,
    'metrics': metrics,
    'quality_score': qualityScore,
    'motion_score': motionScore,
    'duration_seconds': durationSeconds,
    'observed_at_utc': observedAtUtc.toIso8601String(),
  };

  factory CandidateWindow.fromJson(Map<String, dynamic> json) {
    return CandidateWindow(
      sessionId: json['session_id'] as String,
      windowId: json['window_id'] as String,
      stratum: SRMStratum.fromString(json['stratum'] as String) ?? SRMStratum.other,
      metrics: (json['metrics'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      qualityScore: (json['quality_score'] as num).toDouble(),
      motionScore: (json['motion_score'] as num).toDouble(),
      durationSeconds: (json['duration_seconds'] as num).toDouble(),
      observedAtUtc: DateTime.parse(json['observed_at_utc'] as String),
    );
  }
}

/// Per-metric robust reference (median and MAD).
class MetricReference {
  final double median;
  final double mad;

  const MetricReference({required this.median, required this.mad});

  Map<String, dynamic> toJson() => {'median': median, 'mad': mad};

  factory MetricReference.fromJson(Map<String, dynamic> json) {
    return MetricReference(
      median: (json['median'] as num).toDouble(),
      mad: (json['mad'] as num).toDouble(),
    );
  }
}

/// SRM reference for a stratum — per-metric median/MAD plus status.
class SRMReference {
  final SRMStratum stratum;
  final SRMBaselineStatus status;
  final Map<String, MetricReference> metrics;
  final int bufferCount;
  final int distinctDays;

  const SRMReference({
    required this.stratum,
    required this.status,
    required this.metrics,
    required this.bufferCount,
    required this.distinctDays,
  });

  Map<String, dynamic> toJson() => {
    'stratum': stratum.name,
    'status': status.toUpperCase(),
    'metrics': metrics.map((k, v) => MapEntry(k, v.toJson())),
    'buffer_count': bufferCount,
    'distinct_days': distinctDays,
  };
}

/// Result returned after submitting a candidate window.
class SRMResult {
  final bool accepted;
  final String? rejectionReason;
  final SRMBaselineStatus baselineStatus;
  final Map<String, MetricReference>? reference;
  final String srmSnapshotId;
  final String srmVersion;

  const SRMResult({
    required this.accepted,
    this.rejectionReason,
    required this.baselineStatus,
    this.reference,
    required this.srmSnapshotId,
    required this.srmVersion,
  });

  Map<String, dynamic> toJson() => {
    'accepted': accepted,
    if (rejectionReason != null) 'rejection_reason': rejectionReason,
    'baseline_status': baselineStatus.toUpperCase(),
    if (reference != null)
      'reference': reference!.map((k, v) => MapEntry(k, v.toJson())),
    'srm_snapshot_id': srmSnapshotId,
    'srm_version': srmVersion,
  };
}
