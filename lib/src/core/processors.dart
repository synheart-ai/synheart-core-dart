import 'dart:math';
import 'ingestion.dart';
import '../models/context.dart';
import '../models/behavior.dart';
import '../models/hsv.dart';

/// Processed signals ready for fusion
class ProcessedSignals {
  final ProcessedBiosignals biosignals;
  final ProcessedBehavioralSignals behavioral;
  final ProcessedContextSignals context;

  ProcessedSignals({
    required this.biosignals,
    required this.behavioral,
    required this.context,
  });
}

class ProcessedBiosignals {
  final double? normalizedHeartRate;
  final double? normalizedHrv;
  final double? rmssd;
  final double? sdnn;
  final double? motionEnergy;
  final List<double>? rrIntervals;

  ProcessedBiosignals({
    this.normalizedHeartRate,
    this.normalizedHrv,
    this.rmssd,
    this.sdnn,
    this.motionEnergy,
    this.rrIntervals,
  });
}

class ProcessedBehavioralSignals {
  final double typingCadence;
  final double typingBurstiness;
  final double scrollVelocity;
  final double idleGaps;
  final double appSwitchRate;

  ProcessedBehavioralSignals({
    required this.typingCadence,
    required this.typingBurstiness,
    required this.scrollVelocity,
    required this.idleGaps,
    required this.appSwitchRate,
  });
}

class ProcessedContextSignals {
  final double overload;
  final double frustration;
  final double engagement;
  final ConversationContext conversation;
  final DeviceStateContext deviceState;
  final UserPatternsContext userPatterns;

  ProcessedContextSignals({
    required this.overload,
    required this.frustration,
    required this.engagement,
    required this.conversation,
    required this.deviceState,
    required this.userPatterns,
  });
}

/// Signal Processor
/// 
/// Handles:
/// - Synchronization and windowing
/// - Noise reduction and artifact handling
/// - Vendor-agnostic normalization
/// - Baseline alignment
class SignalProcessor {
  /// Process raw signals into normalized, cleaned signals
  Future<ProcessedSignals> process(SignalData signals) async {
    // Process biosignals
    final biosignals = _processBiosignals(signals.biosignals);

    // Process behavioral signals
    final behavioral = _processBehavioral(signals.behavioral);

    // Process context signals
    final context = _processContext(signals.context);

    return ProcessedSignals(
      biosignals: biosignals,
      behavioral: behavioral,
      context: context,
    );
  }

  ProcessedBiosignals _processBiosignals(Biosignals? biosignals) {
    if (biosignals == null) {
      return ProcessedBiosignals();
    }

    // Normalize heart rate (assuming typical range 50-120 bpm)
    final normalizedHeartRate = biosignals.heartRate != null
        ? ((biosignals.heartRate! - 50) / 70).clamp(0.0, 1.0)
        : null;

    // Normalize HRV (assuming typical range 20-100 ms)
    final normalizedHrv = biosignals.hrv != null
        ? ((biosignals.hrv! - 20) / 80).clamp(0.0, 1.0)
        : null;

    // Calculate derived metrics
    double? rmssd;
    double? sdnn;
    if (biosignals.rrIntervals != null && biosignals.rrIntervals!.isNotEmpty) {
      rmssd = _calculateRMSSD(biosignals.rrIntervals!);
      sdnn = _calculateSDNN(biosignals.rrIntervals!);
    }

    // Motion energy
    final motionEnergy = biosignals.motion?.energy ?? 0.0;

    return ProcessedBiosignals(
      normalizedHeartRate: normalizedHeartRate,
      normalizedHrv: normalizedHrv,
      rmssd: rmssd,
      sdnn: sdnn,
      motionEnergy: motionEnergy,
      rrIntervals: biosignals.rrIntervals,
    );
  }

  ProcessedBehavioralSignals _processBehavioral(
      BehavioralSignals? behavioral) {
    if (behavioral == null) {
      return ProcessedBehavioralSignals(
        typingCadence: 0.0,
        typingBurstiness: 0.0,
        scrollVelocity: 0.0,
        idleGaps: 0.0,
        appSwitchRate: 0.0,
      );
    }

    // Normalize typing cadence (0.0 - 1.0)
    final typingCadence = (behavioral.typingCadence ?? 0.0).clamp(0.0, 1.0);

    // Calculate burstiness from typing bursts
    final typingBurstiness = behavioral.typingBursts != null
        ? _calculateBurstiness(behavioral.typingBursts!)
        : 0.0;

    // Normalize scroll velocity
    final scrollVelocity = (behavioral.scrollVelocity ?? 0.0).clamp(0.0, 1.0);

    // Average idle gaps
    final idleGaps = behavioral.idleGaps != null && behavioral.idleGaps!.isNotEmpty
        ? behavioral.idleGaps!.reduce((a, b) => a + b) /
            behavioral.idleGaps!.length
        : 0.0;

    // App switch rate (switches per minute)
    final appSwitchRate = behavioral.appSwitches != null
        ? _calculateSwitchRate(behavioral.appSwitches!)
        : 0.0;

    return ProcessedBehavioralSignals(
      typingCadence: typingCadence,
      typingBurstiness: typingBurstiness,
      scrollVelocity: scrollVelocity,
      idleGaps: idleGaps,
      appSwitchRate: appSwitchRate,
    );
  }

  ProcessedContextSignals _processContext(ContextSignals? context) {
    if (context == null) {
      return ProcessedContextSignals(
        overload: 0.0,
        frustration: 0.0,
        engagement: 0.0,
        conversation: ConversationContext(
          avgReplyDelaySec: 0.0,
          burstiness: 0.0,
          interruptRate: 0.0,
        ),
        deviceState: DeviceStateContext(
          foreground: true,
          screenOn: true,
        ),
        userPatterns: UserPatternsContext(
          morningFocusBias: 0.5,
          avgSessionMinutes: 0.0,
          baselineTypingCadence: 0.0,
        ),
      );
    }

    // Process conversation timing
    final conversation = context.conversation != null
        ? ConversationContext(
            avgReplyDelaySec: context.conversation!.replyDelays.isNotEmpty
                ? context.conversation!.replyDelays.reduce((a, b) => a + b) /
                    context.conversation!.replyDelays.length
                : 0.0,
            burstiness: _calculateBurstiness(context.conversation!.messageBursts),
            interruptRate: context.conversation!.interrupts.length / 60.0, // per minute
          )
        : ConversationContext(
            avgReplyDelaySec: 0.0,
            burstiness: 0.0,
            interruptRate: 0.0,
          );

    // Device state
    final deviceState = DeviceStateContext(
      foreground: context.deviceState?.foreground ?? true,
      screenOn: context.deviceState?.screenOn ?? true,
      focusMode: context.deviceState?.focusMode,
    );

    // User patterns
    final userPatterns = UserPatternsContext(
      morningFocusBias: context.userPatterns?.morningFocusBias ?? 0.5,
      avgSessionMinutes: context.userPatterns?.avgSessionMinutes ?? 0.0,
      baselineTypingCadence: context.userPatterns?.baselineTypingCadence ?? 0.0,
    );

    // TODO: Calculate overload, frustration, engagement from context
    return ProcessedContextSignals(
      overload: 0.0,
      frustration: 0.0,
      engagement: 0.0,
      conversation: conversation,
      deviceState: deviceState,
      userPatterns: userPatterns,
    );
  }

  double _calculateRMSSD(List<double> rrIntervals) {
    if (rrIntervals.length < 2) return 0.0;
    double sum = 0.0;
    for (int i = 1; i < rrIntervals.length; i++) {
      final diff = rrIntervals[i] - rrIntervals[i - 1];
      sum += diff * diff;
    }
    return sqrt(sum / (rrIntervals.length - 1));
  }

  double _calculateSDNN(List<double> rrIntervals) {
    if (rrIntervals.isEmpty) return 0.0;
    final mean = rrIntervals.reduce((a, b) => a + b) / rrIntervals.length;
    final variance = rrIntervals
        .map((x) => (x - mean) * (x - mean))
        .reduce((a, b) => a + b) /
        rrIntervals.length;
    return sqrt(variance);
  }

  double _calculateBurstiness(List<DateTime> events) {
    if (events.length < 2) return 0.0;
    // Simple burstiness: variance of inter-event intervals
    final intervals = <double>[];
    for (int i = 1; i < events.length; i++) {
      intervals.add(
          events[i].difference(events[i - 1]).inMilliseconds / 1000.0);
    }
    if (intervals.isEmpty) return 0.0;
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    final variance = intervals
        .map((x) => (x - mean) * (x - mean))
        .reduce((a, b) => a + b) /
        intervals.length;
    return (variance / (mean + 0.001)).clamp(0.0, 1.0); // Normalize
  }

  double _calculateSwitchRate(List<DateTime> switches) {
    if (switches.isEmpty) return 0.0;
    // Count switches in last minute
    final now = DateTime.now();
    final recentSwitches = switches
        .where((s) => now.difference(s).inSeconds < 60)
        .length;
    return recentSwitches / 60.0; // switches per minute
  }
}

/// Fusion Engine
/// 
/// Computes:
/// - Low-level derived metrics
/// - Deep latent embedding (hsi_embedding)
/// - Base HSV
class FusionEngine {
  /// Fuse processed signals into base HSV
  Future<HumanStateVector> fuse(
    ProcessedSignals signals, {
    required int timestamp,
  }) async {
    // TODO: Implement actual fusion model (Tiny Transformer or CNN-LSTM)
    // For now, create a placeholder embedding
    final hsiEmbedding = _generatePlaceholderEmbedding(signals);

    // Create behavior state
    final behavior = BehaviorState(
      typingCadence: signals.behavioral.typingCadence,
      typingBurstiness: signals.behavioral.typingBurstiness,
      scrollVelocity: signals.behavioral.scrollVelocity,
      idleGaps: signals.behavioral.idleGaps,
      appSwitchRate: signals.behavioral.appSwitchRate,
    );

    // Create context state
    final context = ContextState(
      overload: signals.context.overload,
      frustration: signals.context.frustration,
      engagement: signals.context.engagement,
      conversation: signals.context.conversation,
      deviceState: signals.context.deviceState,
      userPatterns: signals.context.userPatterns,
    );

    // Create meta state
    final meta = MetaState(
      sessionId: 'sess-${DateTime.now().millisecondsSinceEpoch}',
      device: DeviceInfo(platform: 'flutter'),
      samplingRateHz: 2.0,
      hsiEmbedding: hsiEmbedding,
    );

    // Create base HSV (emotion and focus will be empty initially)
    return HumanStateVector.base(
      timestamp: timestamp,
      behavior: behavior,
      context: context,
      meta: meta,
    );
  }

  /// Generate placeholder embedding (will be replaced with actual model)
  List<double> _generatePlaceholderEmbedding(ProcessedSignals signals) {
    // Placeholder: simple feature vector
    return [
      signals.biosignals.normalizedHeartRate ?? 0.0,
      signals.biosignals.normalizedHrv ?? 0.0,
      signals.behavioral.typingCadence,
      signals.behavioral.typingBurstiness,
      signals.behavioral.scrollVelocity,
      signals.context.overload,
      signals.context.frustration,
      signals.context.engagement,
      // ... more features
    ];
  }
}

