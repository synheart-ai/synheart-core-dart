import '../phone/phone_collectors.dart' show ScreenState;

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
    this.motionIndex,
    this.sleepStage,
    this.respRate,
  });
}

/// Activity classification codes
enum ActivityCode {
  /// Device is stationary
  stationary,

  /// User is walking
  walking,

  /// User is running
  running,

  /// User is in vehicle
  inVehicle,

  /// Unknown activity
  unknown,
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

  /// Motion vector [x, y, z] from accelerometer
  final List<double> motionVector;

  /// Gyroscope vector [gx, gy, gz] from gyroscope
  final List<double> gyroscopeVector;

  /// Activity classification code
  final ActivityCode activityCode;

  /// Screen state (on/off/locked/unlocked) - most recent state in window
  final ScreenState? screenState;

  /// App switch rate (normalized)
  final double appSwitchRate;

  /// Screen on ratio (proportion of window)
  final double screenOnRatio;

  /// Notification rate (per minute)
  final double notificationRate;

  /// Idle ratio (0.0 - 1.0) - proportion of time device was idle
  final double idleRatio;

  /// Detailed app context (Extended/Research only)
  final Map<String, dynamic>? appContext;

  /// Raw notification structure (Research only)
  final List<Map<String, dynamic>>? rawNotifications;

  const PhoneWindowFeatures({
    required this.motionLevel,
    required this.motionVector,
    required this.gyroscopeVector,
    required this.activityCode,
    this.screenState,
    required this.appSwitchRate,
    required this.screenOnRatio,
    required this.notificationRate,
    required this.idleRatio,
    this.appContext,
    this.rawNotifications,
  });

  /// Create a copy with updated values
  PhoneWindowFeatures copyWith({
    double? motionLevel,
    List<double>? motionVector,
    List<double>? gyroscopeVector,
    ActivityCode? activityCode,
    ScreenState? screenState,
    double? appSwitchRate,
    double? screenOnRatio,
    double? notificationRate,
    double? idleRatio,
    Map<String, dynamic>? appContext,
    List<Map<String, dynamic>>? rawNotifications,
  }) {
    return PhoneWindowFeatures(
      motionLevel: motionLevel ?? this.motionLevel,
      motionVector: motionVector ?? this.motionVector,
      gyroscopeVector: gyroscopeVector ?? this.gyroscopeVector,
      activityCode: activityCode ?? this.activityCode,
      screenState: screenState ?? this.screenState,
      appSwitchRate: appSwitchRate ?? this.appSwitchRate,
      screenOnRatio: screenOnRatio ?? this.screenOnRatio,
      notificationRate: notificationRate ?? this.notificationRate,
      idleRatio: idleRatio ?? this.idleRatio,
      appContext: appContext ?? this.appContext,
      rawNotifications: rawNotifications ?? this.rawNotifications,
    );
  }
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
