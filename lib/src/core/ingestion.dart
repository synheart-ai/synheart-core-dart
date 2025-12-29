import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'data_sources.dart';
import 'logger.dart';
import '../modules/interfaces/feature_providers.dart';

/// Raw signal data from various sources
class SignalData {
  /// Biosignals from Wear SDK/Service
  final Biosignals? biosignals;

  /// Behavioral signals from Phone SDK
  final BehavioralSignals? behavioral;

  /// Context signals from Context Adapters
  final ContextSignals? context;

  SignalData({
    this.biosignals,
    this.behavioral,
    this.context,
  });
}

/// Biosignals from Wear SDK/Service
class Biosignals {
  /// Heart rate (bpm)
  final double? heartRate;

  /// Heart rate variability (ms)
  final double? hrv;

  /// R-R intervals (ms)
  final List<double>? rrIntervals;

  /// Accelerometer/motion data
  final MotionData? motion;

  /// Sleep stage metadata
  final SleepStage? sleepStage;

  /// Respiration rate (breaths per minute)
  final double? respirationRate;

  Biosignals({
    this.heartRate,
    this.hrv,
    this.rrIntervals,
    this.motion,
    this.sleepStage,
    this.respirationRate,
  });
}

/// Motion data from accelerometer
class MotionData {
  final double x;
  final double y;
  final double z;
  final double? energy;

  MotionData({
    required this.x,
    required this.y,
    required this.z,
    this.energy,
  });
}

// SleepStage is defined in feature_providers.dart - imported above

/// Behavioral signals from Phone SDK
class BehavioralSignals {
  /// Keystroke/tap cadence
  final double? typingCadence;

  /// Typing bursts
  final List<DateTime>? typingBursts;

  /// Scroll velocity
  final double? scrollVelocity;

  /// Idle gaps between interactions (seconds)
  final List<double>? idleGaps;

  /// App switch events
  final List<DateTime>? appSwitches;

  BehavioralSignals({
    this.typingCadence,
    this.typingBursts,
    this.scrollVelocity,
    this.idleGaps,
    this.appSwitches,
  });
}

/// Context signals from Context Adapters
class ContextSignals {
  /// Conversation timing
  final ConversationTiming? conversation;

  /// Device state
  final DeviceState? deviceState;

  /// User patterns
  final UserPatterns? userPatterns;

  ContextSignals({
    this.conversation,
    this.deviceState,
    this.userPatterns,
  });
}

/// Conversation timing metrics
class ConversationTiming {
  final List<double> replyDelays; // seconds
  final List<DateTime> messageBursts;
  final List<DateTime> interrupts;

  ConversationTiming({
    required this.replyDelays,
    required this.messageBursts,
    required this.interrupts,
  });
}

/// Device state information
class DeviceState {
  final bool foreground;
  final bool screenOn;
  final String? focusMode; // 'work', 'personal', 'none', etc.

  DeviceState({
    required this.foreground,
    required this.screenOn,
    this.focusMode,
  });
}

/// User pattern information
class UserPatterns {
  final double? morningFocusBias;
  final double? avgSessionMinutes;
  final double? baselineTypingCadence;

  UserPatterns({
    this.morningFocusBias,
    this.avgSessionMinutes,
    this.baselineTypingCadence,
  });
}

/// Ingestion Service
///
/// Collects signals from pluggable data sources:
/// - BiosignalDataSource (wearables, mock data, etc.)
/// - BehavioralDataSource (phone SDK, etc.)
/// - ContextDataSource (context adapters, etc.)
///
/// This service is data-source agnostic and uses dependency injection.
class IngestionService {
  final BehaviorSubject<SignalData> _signalStream =
      BehaviorSubject<SignalData>();

  Stream<SignalData> get signalStream => _signalStream.stream;

  bool _isRunning = false;

  // Pluggable data sources (injected via constructor)
  final BiosignalDataSource _biosignalSource;
  final BehavioralDataSource _behavioralSource;
  final ContextDataSource _contextSource;

  // Stream subscriptions
  StreamSubscription<Biosignals>? _biosignalSubscription;
  StreamSubscription<BehavioralSignals>? _behavioralSubscription;
  StreamSubscription<ContextSignals>? _contextSubscription;

  // Latest data cache from each source
  Biosignals? _latestBiosignals;
  BehavioralSignals? _latestBehavioral;
  ContextSignals? _latestContext;

  IngestionService({
    BiosignalDataSource? biosignalSource,
    BehavioralDataSource? behavioralSource,
    ContextDataSource? contextSource,
  })  : _biosignalSource = biosignalSource ?? MockBiosignalDataSource(),
        _behavioralSource = behavioralSource ?? MockBehavioralDataSource(),
        _contextSource = contextSource ?? MockContextDataSource();

  /// Start ingestion
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      // Initialize all data sources
      await _biosignalSource.initialize();
      await _behavioralSource.initialize();
      await _contextSource.initialize();

      // Subscribe to biosignal stream
      _biosignalSubscription = _biosignalSource.biosignalStream.listen(
        (biosignals) {
          _latestBiosignals = biosignals;
          _emitCombinedSignals();
        },
        onError: (error) {
          SynheartLogger.log('Biosignal stream error: $error', error: error);
        },
      );

      // Subscribe to behavioral stream
      _behavioralSubscription = _behavioralSource.behavioralStream.listen(
        (behavioral) {
          _latestBehavioral = behavioral;
          _emitCombinedSignals();
        },
        onError: (error) {
          SynheartLogger.log('Behavioral stream error: $error', error: error);
        },
      );

      // Subscribe to context stream
      _contextSubscription = _contextSource.contextStream.listen(
        (context) {
          _latestContext = context;
          _emitCombinedSignals();
        },
        onError: (error) {
          SynheartLogger.log('Context stream error: $error', error: error);
        },
      );
    } catch (e) {
      SynheartLogger.log('Failed to initialize data sources: $e', error: e);
      rethrow;
    }
  }

  /// Stop ingestion
  Future<void> stop() async {
    _isRunning = false;
    await _biosignalSubscription?.cancel();
    await _behavioralSubscription?.cancel();
    await _contextSubscription?.cancel();
    _biosignalSubscription = null;
    _behavioralSubscription = null;
    _contextSubscription = null;
  }

  /// Emit a signal update
  void emitSignal(SignalData signal) {
    if (_isRunning) {
      _signalStream.add(signal);
    }
  }

  /// Combine latest data from all sources and emit
  void _emitCombinedSignals() {
    if (!_isRunning) return;

    // Only emit if we have at least biosignal data
    if (_latestBiosignals == null) return;

    emitSignal(SignalData(
      biosignals: _latestBiosignals,
      behavioral: _latestBehavioral,
      context: _latestContext,
    ));
  }

  Future<void> dispose() async {
    await stop();
    await _biosignalSource.dispose();
    await _behavioralSource.dispose();
    await _contextSource.dispose();
    await _signalStream.close();
  }
}
