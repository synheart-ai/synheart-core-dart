/// Result of evaluating breathing compliance over the current RR window.
///
/// Mirrors the breathing runtime's `ComplianceResult` JSON shape from
/// the native runtime. See RFC-Breathing-001 for verdict semantics.
library;

/// Numeric metrics computed by the 4-pillar detector.
class BreathingMetrics {
  /// Detected breathing peak frequency in Hz.
  final double peakHz;

  /// Detected breathing rate in breaths/minute (= peakHz * 60).
  final double peakBpm;

  /// Coherence score (peak power / power in 0.04–0.26 Hz band), 0..1.
  final double coherence;

  /// RSA amplitude (mean per-cycle HR_max − HR_min), in BPM.
  final double rsaBpm;

  /// Peak power as a fraction of total breathing-band power, 0..1.
  final double relativePower;

  /// Number of compliance pillars met (0..4).
  final int criteriaMet;

  /// Mean of normalized pillar scores, 0..1.
  final double confidence;

  const BreathingMetrics({
    required this.peakHz,
    required this.peakBpm,
    required this.coherence,
    required this.rsaBpm,
    required this.relativePower,
    required this.criteriaMet,
    required this.confidence,
  });

  factory BreathingMetrics.fromJson(Map<String, dynamic> json) {
    double d(String k) => (json[k] as num?)?.toDouble() ?? 0.0;
    int i(String k) => (json[k] as num?)?.toInt() ?? 0;
    return BreathingMetrics(
      peakHz: d('peak_hz'),
      peakBpm: d('peak_bpm'),
      coherence: d('coherence'),
      rsaBpm: d('rsa_bpm'),
      relativePower: d('relative_power'),
      criteriaMet: i('criteria_met'),
      confidence: d('confidence'),
    );
  }
}

/// Why the user is not following instructions (when verdict is NotCompliant).
sealed class NonComplianceReason {
  const NonComplianceReason();

  factory NonComplianceReason.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'WrongFrequency':
        return WrongFrequency(
          detectedBpm: (json['detected_bpm'] as num).toDouble(),
          targetBpm: (json['target_bpm'] as num).toDouble(),
        );
      case 'ShallowBreathing':
        return ShallowBreathing(rsaBpm: (json['rsa_bpm'] as num).toDouble());
      case 'IrregularPattern':
        return IrregularPattern(
          coherence: (json['coherence'] as num).toDouble(),
        );
      case 'NoBreathingSignature':
      default:
        return const NoBreathingSignature();
    }
  }
}

class WrongFrequency extends NonComplianceReason {
  final double detectedBpm;
  final double targetBpm;
  const WrongFrequency({required this.detectedBpm, required this.targetBpm});
}

class ShallowBreathing extends NonComplianceReason {
  final double rsaBpm;
  const ShallowBreathing({required this.rsaBpm});
}

class IrregularPattern extends NonComplianceReason {
  final double coherence;
  const IrregularPattern({required this.coherence});
}

class NoBreathingSignature extends NonComplianceReason {
  const NoBreathingSignature();
}

/// Why the detector cannot produce a verdict yet.
sealed class InsufficientReason {
  const InsufficientReason();

  factory InsufficientReason.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'NotEnoughBeats':
        return NotEnoughBeats(
          have: (json['have'] as num).toInt(),
          need: (json['need'] as num).toInt(),
        );
      case 'WindowTooShort':
        return WindowTooShort(
          haveSecs: (json['have_secs'] as num).toInt(),
          needSecs: (json['need_secs'] as num).toInt(),
        );
      case 'VendorOnlyTier':
        return VendorOnlyTier(device: json['device'] as String? ?? '');
      case 'ExcessiveArtifacts':
        return ExcessiveArtifacts(
          rejectedPct: (json['rejected_pct'] as num).toDouble(),
        );
      default:
        return const NotEnoughBeats(have: 0, need: 50);
    }
  }
}

class NotEnoughBeats extends InsufficientReason {
  final int have;
  final int need;
  const NotEnoughBeats({required this.have, required this.need});
}

class WindowTooShort extends InsufficientReason {
  final int haveSecs;
  final int needSecs;
  const WindowTooShort({required this.haveSecs, required this.needSecs});
}

class VendorOnlyTier extends InsufficientReason {
  final String device;
  const VendorOnlyTier({required this.device});
}

class ExcessiveArtifacts extends InsufficientReason {
  final double rejectedPct;
  const ExcessiveArtifacts({required this.rejectedPct});
}

/// Top-level breathing compliance verdict.
sealed class BreathingComplianceResult {
  const BreathingComplianceResult();

  /// Returns the metrics if available (null for [Insufficient]).
  BreathingMetrics? get metrics;

  /// True iff the user is meeting the compliance threshold.
  bool get isCompliant => this is BreathingCompliant;

  factory BreathingComplianceResult.fromJson(Map<String, dynamic> json) {
    final verdict = json['verdict'] as String?;
    switch (verdict) {
      case 'Compliant':
        return BreathingCompliant(
          metrics: BreathingMetrics.fromJson(
            json['metrics'] as Map<String, dynamic>,
          ),
        );
      case 'NotCompliant':
        return BreathingNotCompliant(
          metrics: BreathingMetrics.fromJson(
            json['metrics'] as Map<String, dynamic>,
          ),
          reason: NonComplianceReason.fromJson(
            json['reason'] as Map<String, dynamic>,
          ),
        );
      case 'Insufficient':
      default:
        return BreathingInsufficient(
          reason: InsufficientReason.fromJson(
            json['reason'] as Map<String, dynamic>,
          ),
        );
    }
  }
}

class BreathingCompliant extends BreathingComplianceResult {
  @override
  final BreathingMetrics metrics;
  const BreathingCompliant({required this.metrics});
}

class BreathingNotCompliant extends BreathingComplianceResult {
  @override
  final BreathingMetrics metrics;
  final NonComplianceReason reason;
  const BreathingNotCompliant({required this.metrics, required this.reason});
}

class BreathingInsufficient extends BreathingComplianceResult {
  @override
  BreathingMetrics? get metrics => null;
  final InsufficientReason reason;
  const BreathingInsufficient({required this.reason});
}

/// Population threshold profiles. Match the native runtime's enum ordering.
enum BreathingPopulation { beginner, experienced, clinical }
