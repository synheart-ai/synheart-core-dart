/// Default constants used across the Synheart SDK.
///
/// Centralizes magic numbers for runtime configuration, biosignal validation,
/// and physiological range boundaries.
class SynheartDefaults {
  SynheartDefaults._();

  /// Default runtime window duration in milliseconds.
  /// Use 10s so the first HSI completes after ~10–15s; 60s would require a full minute before any output.
  static const int runtimeWindowMs = 10000;

  /// Default runtime step interval in milliseconds (emit every 10s when window=10s).
  static const int runtimeStepMs = 10000;

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
