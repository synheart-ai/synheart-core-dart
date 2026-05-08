/// Default user-facing copy for [NonComplianceReason] enum values.
///
/// The native engine emits structured reasons (frequency mismatch,
/// shallow breathing, etc.) — strings used to live alongside them
/// in the FFI but that put UI copy in the wrong layer: the engine
/// can't be localized, A/B-tested, or re-toned without a runtime
/// rebuild. Wording belongs to the consumer; this file ships a
/// neutral default so most apps can stay one-liner.
///
/// Apps wanting a different tone can either override
/// [BreathingGuidanceCopy.localize] (single replacement) or build
/// their own switch over [NonComplianceReason] in their UI layer.
library;

import 'breathing_compliance_result.dart';

/// Returns a single-line coaching string for [reason]. Pure function;
/// no engine call. Apps that want their own copy should write the
/// same switch — passing [BreathingGuidanceCopy.localize] is the
/// suggested fallback when no override is set.
typedef BreathingGuidanceLocalizer =
    String Function(NonComplianceReason reason);

class BreathingGuidanceCopy {
  /// Default-tone English. Override via [localize] to swap in your
  /// own copy globally without forking call sites.
  static BreathingGuidanceLocalizer localize = _defaultEn;

  /// Convenience equivalent of `localize(reason)`. Stays available
  /// when callers prefer a static-method look.
  static String copyFor(NonComplianceReason reason) => localize(reason);

  static String _defaultEn(NonComplianceReason reason) {
    return switch (reason) {
      WrongFrequency(:final detectedBpm, :final targetBpm) =>
        detectedBpm > targetBpm
            ? "Slow down - you're breathing faster than the target."
            : "Speed up slightly - you're breathing slower than the target.",
      ShallowBreathing() =>
        'Good rhythm - now breathe deeper, take fuller breaths.',
      IrregularPattern() => 'Try to keep a steady, even rhythm with the pacer.',
      NoBreathingSignature() =>
        "We can't detect a breathing pattern yet - follow the pacer.",
    };
  }
}
