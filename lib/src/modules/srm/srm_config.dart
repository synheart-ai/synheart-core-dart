import 'srm_stratum.dart';

/// SRM configuration — thresholds, buffer sizes, and gating parameters.
///
/// All values are fixed per deployment and identical across platforms
/// to guarantee deterministic behavior (SRM.pdf §3.4).
class SRMConfig {
  /// Tracked metric names.
  final List<String> trackedMetrics;

  /// Maximum buffer size per stratum.
  final int bufferSize;

  /// Minimum signal quality score to accept a candidate window.
  final double qualityThreshold;

  /// Per-stratum motion thresholds. Windows with motion > beta are rejected.
  final Map<SRMStratum, double> motionThresholds;

  /// Minimum window duration in seconds.
  final double durationThresholdSeconds;

  /// Outlier z-score threshold. Reject if |z_k| > kappa for any metric.
  final double outlierKappa;

  /// Floor epsilon to prevent division by zero in z-score computation.
  final double epsilon;

  /// Minimum accepted windows for WARMING status.
  final int mMin;

  /// Minimum accepted windows for READY status.
  final int mReady;

  /// Minimum distinct calendar days for READY status.
  final int dMin;

  /// SRM schema version for snapshot compatibility.
  final String srmVersion;

  const SRMConfig({
    this.trackedMetrics = const ['hr_mean', 'rmssd'],
    this.bufferSize = 30,
    this.qualityThreshold = 0.5,
    this.motionThresholds = const {
      SRMStratum.sleep: 0.1,
      SRMStratum.rest: 0.2,
      SRMStratum.breathing: 0.15,
      SRMStratum.morning: 0.3,
      SRMStratum.other: 0.4,
    },
    this.durationThresholdSeconds = 30.0,
    this.outlierKappa = 3.0,
    this.epsilon = 0.001,
    this.mMin = 3,
    this.mReady = 10,
    this.dMin = 3,
    this.srmVersion = '1.0.0',
  });

  /// Default configuration.
  static const SRMConfig defaults = SRMConfig();

  /// Get motion threshold for a stratum, falling back to [other].
  double motionThresholdFor(SRMStratum stratum) {
    return motionThresholds[stratum] ?? motionThresholds[SRMStratum.other] ?? 0.4;
  }
}
