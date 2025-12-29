import '../../models/hsv.dart';
import '../../models/behavior.dart';
import '../../models/context.dart';
import '../../models/hsi_axes.dart';
import '../interfaces/feature_providers.dart';
import 'channel_collector.dart';

/// Fusion Engine
///
/// Combines features from all modules into a base HSV
class FusionEngine {
  /// Fuse collected features into base HSV
  Future<HumanStateVector> fuse(
    CollectedFeatures features,
    WindowType window, {
    required int timestamp,
  }) async {
    // Build fused feature vector
    final fusedVector = _buildFusedVector(features);

    // Run embedding model
    final embeddingVector = await _computeEmbedding(fusedVector);

    // Compute HSI state axes
    final axes = _computeStateAxes(features);

    // Create embedding object
    final embedding = StateEmbedding(
      vector: embeddingVector,
      timestamp: timestamp,
      windowType: _getWindowTypeName(window),
    );

    // Create behavior state
    final behavior = _buildBehaviorState(features.behavior);

    // Create context state
    final context = _buildContextState(features.phone);

    // Create meta state with HSI axes and embedding
    final meta = MetaState(
      sessionId: 'sess-${DateTime.now().millisecondsSinceEpoch}',
      device: DeviceInfo(platform: 'flutter'),
      samplingRateHz: _getSamplingRate(window),
      embedding: embedding,
      axes: axes,
    );

    // Create base HSV (emotion and focus will be populated by heads)
    return HumanStateVector.base(
      timestamp: timestamp,
      behavior: behavior,
      context: context,
      meta: meta,
    );
  }

  /// Build fused feature vector from collected features
  List<double> _buildFusedVector(CollectedFeatures features) {
    final vector = <double>[];

    // Wear features (biosignals)
    if (features.wear != null) {
      vector.add(features.wear!.hrAverage ?? 0.0);
      vector.add(features.wear!.hrvRmssd ?? 0.0);
      vector.add(features.wear!.hrvSdnn ?? 0.0);
      vector.add(features.wear!.pnn50 ?? 0.0);
      vector.add(features.wear!.meanRrMs ?? 0.0);
      vector.add(features.wear!.motionIndex ?? 0.0);
      vector.add(features.wear!.respRate ?? 0.0);
    } else {
      vector.addAll([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
    }

    // Phone features (context)
    if (features.phone != null) {
      vector.add(features.phone!.motionLevel);
      vector.add(features.phone!.screenOnRatio);
      vector.add(features.phone!.appSwitchRate);
      vector.add(features.phone!.notificationRate);
    } else {
      vector.addAll([0.0, 0.0, 0.0, 0.0]);
    }

    // Behavior features
    if (features.behavior != null) {
      vector.add(features.behavior!.tapRateNorm);
      vector.add(features.behavior!.keystrokeRateNorm);
      vector.add(features.behavior!.scrollVelocityNorm);
      vector.add(features.behavior!.idleRatio);
      vector.add(features.behavior!.switchRateNorm);
      vector.add(features.behavior!.burstiness);
      vector.add(features.behavior!.sessionFragmentation);
      vector.add(features.behavior!.notificationLoad);
    } else {
      vector.addAll([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
    }

    return vector;
  }

  /// Compute embedding from fused vector (placeholder)
  Future<List<double>> _computeEmbedding(List<double> fusedVector) async {
    // TODO: Implement actual embedding model (MLP/Tiny Transformer)
    // For now, return the fused vector padded/truncated to 64D
    if (fusedVector.length >= 64) {
      return fusedVector.sublist(0, 64);
    } else {
      return [...fusedVector, ...List.filled(64 - fusedVector.length, 0.0)];
    }
  }

  /// Build behavior state from features
  BehaviorState _buildBehaviorState(BehaviorWindowFeatures? features) {
    if (features == null) {
      return BehaviorState(
        typingCadence: 0.0,
        typingBurstiness: 0.0,
        scrollVelocity: 0.0,
        idleGaps: 0.0,
        appSwitchRate: 0.0,
      );
    }

    return BehaviorState(
      typingCadence: features.keystrokeRateNorm,
      typingBurstiness: features.burstiness,
      scrollVelocity: features.scrollVelocityNorm,
      idleGaps: features.idleRatio,
      appSwitchRate: features.switchRateNorm,
    );
  }

  /// Build context state from phone features
  ContextState _buildContextState(PhoneWindowFeatures? features) {
    // Placeholder context state
    return ContextState(
      overload: features?.notificationRate ?? 0.0,
      frustration: 0.0,
      engagement: features?.screenOnRatio ?? 0.0,
      conversation: ConversationContext(
        avgReplyDelaySec: 0.0,
        burstiness: 0.0,
        interruptRate: 0.0,
      ),
      deviceState: DeviceStateContext(
        foreground: true,
        screenOn: features != null && features.screenOnRatio > 0.5,
        focusMode: null,
      ),
      userPatterns: UserPatternsContext(
        morningFocusBias: 0.5,
        avgSessionMinutes: 0.0,
        baselineTypingCadence: 0.0,
      ),
    );
  }

  /// Get sampling rate for window type
  double _getSamplingRate(WindowType window) {
    switch (window) {
      case WindowType.window30s:
        return 2.0; // 2 Hz
      case WindowType.window5m:
        return 0.2; // 0.2 Hz
      case WindowType.window1h:
        return 1.0 / 3600; // 1 sample per hour
      case WindowType.window24h:
        return 1.0 / 86400; // 1 sample per day
    }
  }

  /// Get window type name string
  String _getWindowTypeName(WindowType window) {
    switch (window) {
      case WindowType.window30s:
        return 'micro';
      case WindowType.window5m:
        return 'short';
      case WindowType.window1h:
        return 'medium';
      case WindowType.window24h:
        return 'long';
    }
  }

  /// Compute HSI state axes from collected features
  HSIAxes _computeStateAxes(CollectedFeatures features) {
    return HSIAxes(
      affect: _computeAffectAxis(features),
      engagement: _computeEngagementAxis(features),
      activity: _computeActivityAxis(features),
      context: _computeContextAxis(features),
    );
  }

  /// Compute Affect Axis (arousal and valence stability)
  AffectAxis _computeAffectAxis(CollectedFeatures features) {
    final wear = features.wear;

    if (wear == null) {
      return AffectAxis.empty();
    }

    // Arousal Index: combination of HR and HRV
    // Higher HR and lower HRV indicate higher arousal
    double? arousalIndex;
    if (wear.hrAverage != null && wear.hrvRmssd != null) {
      // Normalize HR (assuming 40-180 bpm range)
      final hrNorm = ((wear.hrAverage! - 40) / 140).clamp(0.0, 1.0);

      // Normalize HRV RMSSD (assuming 10-100ms range, inverted for arousal)
      final hrvNorm = 1.0 - ((wear.hrvRmssd! - 10) / 90).clamp(0.0, 1.0);

      // Combine with weighted average (60% HR, 40% HRV)
      arousalIndex = (0.6 * hrNorm + 0.4 * hrvNorm).clamp(0.0, 1.0);
    }

    // Valence Stability: based on HRV stability (SDNN)
    // Higher SDNN indicates more variation, lower stability
    double? valenceStability;
    if (wear.hrvSdnn != null) {
      // Normalize SDNN (assuming 20-100ms range, inverted for stability)
      valenceStability = 1.0 - ((wear.hrvSdnn! - 20) / 80).clamp(0.0, 1.0);
    }

    return AffectAxis(
      arousalIndex: arousalIndex,
      valenceStability: valenceStability,
    );
  }

  /// Compute Engagement Axis (interaction stability and cadence)
  EngagementAxis _computeEngagementAxis(CollectedFeatures features) {
    final behavior = features.behavior;

    if (behavior == null) {
      return EngagementAxis.empty();
    }

    // Engagement Stability: inverse of burstiness
    // Lower burstiness = more stable engagement
    final engagementStability = (1.0 - behavior.burstiness).clamp(0.0, 1.0);

    // Interaction Cadence: combination of tap rate and keystroke rate
    final interactionCadence =
        (0.5 * behavior.tapRateNorm + 0.5 * behavior.keystrokeRateNorm)
            .clamp(0.0, 1.0);

    return EngagementAxis(
      engagementStability: engagementStability,
      interactionCadence: interactionCadence,
    );
  }

  /// Compute Activity Axis (motion and posture)
  ActivityAxis _computeActivityAxis(CollectedFeatures features) {
    final wear = features.wear;
    final phone = features.phone;

    // Motion Index: combine wear motion and phone motion
    double? motionIndex;

    if (wear?.motionIndex != null && phone != null) {
      // Average of wear and phone motion
      motionIndex =
          (0.5 * wear!.motionIndex! + 0.5 * phone.motionLevel).clamp(0.0, 1.0);
    } else if (wear?.motionIndex != null) {
      motionIndex = wear!.motionIndex!.clamp(0.0, 1.0);
    } else if (phone != null) {
      motionIndex = phone.motionLevel.clamp(0.0, 1.0);
    }

    // Posture Stability: inverse of motion index
    // Lower motion = more stable posture
    final postureStability =
        motionIndex != null ? (1.0 - motionIndex).clamp(0.0, 1.0) : null;

    return ActivityAxis(
      motionIndex: motionIndex,
      postureStability: postureStability,
    );
  }

  /// Compute Context Axis (screen time and fragmentation)
  ContextAxis _computeContextAxis(CollectedFeatures features) {
    final phone = features.phone;
    final behavior = features.behavior;

    if (phone == null && behavior == null) {
      return ContextAxis.empty();
    }

    // Screen Active Ratio: directly from phone features
    final screenActiveRatio = phone?.screenOnRatio.clamp(0.0, 1.0);

    // Session Fragmentation: combine app switch rate and behavior fragmentation
    double? sessionFragmentation;

    if (phone != null && behavior != null) {
      // Average of normalized app switch rate and session fragmentation
      // Assume max 10 switches/min
      final appSwitchNorm = (phone.appSwitchRate / 10.0).clamp(0.0, 1.0);
      sessionFragmentation =
          (0.5 * appSwitchNorm + 0.5 * behavior.sessionFragmentation)
              .clamp(0.0, 1.0);
    } else if (phone != null) {
      sessionFragmentation = (phone.appSwitchRate / 10.0).clamp(0.0, 1.0);
    } else if (behavior != null) {
      sessionFragmentation = behavior.sessionFragmentation.clamp(0.0, 1.0);
    }

    return ContextAxis(
      screenActiveRatio: screenActiveRatio,
      sessionFragmentation: sessionFragmentation,
    );
  }
}
