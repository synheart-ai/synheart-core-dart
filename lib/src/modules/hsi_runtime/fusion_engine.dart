import '../../models/hsv.dart';
import '../../models/behavior.dart';
import '../../models/context.dart';
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

    // Run embedding model (placeholder for now)
    final embedding = await _computeEmbedding(fusedVector);

    // Create behavior state
    final behavior = _buildBehaviorState(features.behavior);

    // Create context state
    final context = _buildContextState(features.phone);

    // Create meta state
    final meta = MetaState(
      sessionId: 'sess-${DateTime.now().millisecondsSinceEpoch}',
      device: DeviceInfo(platform: 'flutter'),
      samplingRateHz: _getSamplingRate(window),
      hsiEmbedding: embedding,
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
}
