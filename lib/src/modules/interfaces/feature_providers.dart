/// Window types for time-based aggregation
enum WindowType {
  /// 30-second window
  window30s,

  /// 5-minute window
  window5m,

  /// 1-hour window
  window1h,

  /// 24-hour window
  window24h,
}

/// Sleep stage information
enum SleepStage {
  awake,
  light,
  deep,
  rem,
}

/// Wear module feature provider
abstract class WearFeatureProvider {
  /// Get biosignal features for a specific window
  WearWindowFeatures? features(WindowType window);
}

/// Biosignal features from wearables
class WearWindowFeatures {
  /// Window duration
  final Duration windowDuration;

  /// Average heart rate (bpm)
  final double? hrAverage;

  /// Minimum heart rate (bpm)
  final double? hrMin;

  /// Maximum heart rate (bpm)
  final double? hrMax;

  /// Heart rate variability - RMSSD (ms)
  final double? hrvRmssd;

  /// Heart rate variability - SDNN (ms)
  ///
  /// Optional. Populated only when RR intervals are available.
  final double? hrvSdnn;

  /// pNN50 (%)
  ///
  /// Optional. Populated only when RR intervals are available.
  final double? pnn50;

  /// Mean RR interval (ms)
  ///
  /// Optional. Populated only when RR intervals are available.
  final double? meanRrMs;

  /// Motion index (0.0 - 1.0)
  final double? motionIndex;

  /// Sleep stage
  final SleepStage? sleepStage;

  /// Respiration rate (breaths per minute)
  final double? respRate;

  const WearWindowFeatures({
    required this.windowDuration,
    this.hrAverage,
    this.hrMin,
    this.hrMax,
    this.hrvRmssd,
    this.hrvSdnn,
    this.pnn50,
    this.meanRrMs,
    this.motionIndex,
    this.sleepStage,
    this.respRate,
  });
}

/// Phone module feature provider
abstract class PhoneFeatureProvider {
  /// Get phone features for a specific window
  PhoneWindowFeatures? features(WindowType window);
}

/// Phone context features
class PhoneWindowFeatures {
  /// Motion level (0.0 - 1.0)
  final double motionLevel;

  /// App switch rate (normalized)
  final double appSwitchRate;

  /// Screen on ratio (proportion of window)
  final double screenOnRatio;

  /// Notification rate (per minute)
  final double notificationRate;

  const PhoneWindowFeatures({
    required this.motionLevel,
    required this.appSwitchRate,
    required this.screenOnRatio,
    required this.notificationRate,
  });
}

/// Behavior module feature provider
abstract class BehaviorFeatureProvider {
  /// Get behavioral features for a specific window
  BehaviorWindowFeatures? features(WindowType window);
}

/// Behavioral interaction features
class BehaviorWindowFeatures {
  /// Typing cadence (normalized 0.0 - 1.0)
  final double tapRateNorm;

  /// Keystroke rate (normalized 0.0 - 1.0)
  final double keystrokeRateNorm;

  /// Scroll velocity (normalized 0.0 - 1.0)
  final double scrollVelocityNorm;

  /// Idle ratio (0.0 - 1.0)
  final double idleRatio;

  /// App/context switch rate (normalized)
  final double switchRateNorm;

  /// Burstiness (0.0 - 1.0)
  final double burstiness;

  /// Session fragmentation (0.0 - 1.0)
  final double sessionFragmentation;

  /// Notification load (0.0 - 1.0)
  final double notificationLoad;

  /// Distraction score from MLP (0.0 - 1.0)
  final double distractionScore;

  /// Focus hint from MLP (0.0 - 1.0)
  final double focusHint;

  const BehaviorWindowFeatures({
    required this.tapRateNorm,
    required this.keystrokeRateNorm,
    required this.scrollVelocityNorm,
    required this.idleRatio,
    required this.switchRateNorm,
    required this.burstiness,
    required this.sessionFragmentation,
    required this.notificationLoad,
    required this.distractionScore,
    required this.focusHint,
  });
}
