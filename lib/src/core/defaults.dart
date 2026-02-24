/// Default constants used across the Synheart SDK.
///
/// Centralizes magic numbers for runtime configuration, biosignal validation,
/// and physiological range boundaries.
class SynheartDefaults {
  SynheartDefaults._();

  /// Default runtime window duration in milliseconds (60 seconds).
  static const int runtimeWindowMs = 60000;

  /// Default runtime step interval in milliseconds (5 seconds).
  static const int runtimeStepMs = 5000;

  /// Default runtime tick interval in seconds.
  static const int runtimeTickIntervalSeconds = 5;

  /// Maximum daily steps used for motion normalization (0–1 range).
  static const double maxStepsForMotion = 10000.0;

  /// Minimum valid heart rate in BPM.
  static const double hrMinBpm = 40.0;

  /// Maximum valid heart rate in BPM.
  static const double hrMaxBpm = 180.0;

  /// Minimum valid RR interval in milliseconds.
  static const double rrMinMs = 300.0;

  /// Maximum valid RR interval in milliseconds.
  static const double rrMaxMs = 2000.0;

  /// Milliseconds per minute, used for HR ↔ RR conversion.
  static const double msPerMinute = 60000.0;
}
