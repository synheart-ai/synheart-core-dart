// ignore_for_file: avoid_print, prefer_const_constructors

import 'dart:convert';
import 'package:synheart_core/synheart_core.dart';

/// Example: Converting HSV to HSI 1.0 (JSON) export format
///
/// This demonstrates the Synheart Core hybrid architecture:
/// - HSV (Human State Vector): Internal, type-safe Dart representation
/// - HSI 1.0 (Human State Interface): External JSON format for interoperability
///
/// This example shows how to convert HSV to HSI 1.0 for external systems.
void main() {
  // Create a sample HumanStateVector (HSV - internal representation)
  final hsv = HumanStateVector(
    version: '1.0.0',
    timestamp: DateTime.utc(2025, 12, 28, 0, 0, 10).millisecondsSinceEpoch,
    emotion: EmotionState(
      stress: 0.3,
      calm: 0.6,
      engagement: 0.7,
      activation: 0.5,
      valence: 0.4,
    ),
    focus: FocusState(
      score: 0.75,
      cognitiveLoad: 0.4,
      clarity: 0.8,
      distraction: 0.25,
    ),
    behavior: BehaviorState(
      typingCadence: 0.65,
      typingBurstiness: 0.25,
      scrollVelocity: 0.55,
      idleGaps: 1.5,
      appSwitchRate: 0.15,
    ),
    context: ContextState(
      overload: 0.2,
      frustration: 0.15,
      engagement: 0.8,
      conversation: ConversationContext(
        avgReplyDelaySec: 3.5,
        burstiness: 0.3,
        interruptRate: 0.1,
      ),
      deviceState: DeviceStateContext(
        foreground: true,
        screenOn: true,
        focusMode: 'work',
      ),
      userPatterns: UserPatternsContext(
        morningFocusBias: 0.7,
        avgSessionMinutes: 52.0,
        baselineTypingCadence: 0.6,
      ),
    ),
    meta: MetaState(
      sessionId: 'demo-session-2025-12-28',
      device: DeviceInfo(
        platform: 'flutter',
        model: 'iPhone 15 Pro',
        osVersion: 'iOS 18.2',
      ),
      samplingRateHz: 2.0,
      embedding: StateEmbedding(
        vector: List.generate(64, (i) => (i * 0.01).toDouble()),
        timestamp: DateTime.utc(2025, 12, 28, 0, 0, 10).millisecondsSinceEpoch,
        windowType: 'micro',
        model: 'hsi-fusion-v1',
      ),
      axes: HSIAxes(
        affect: AffectAxis(arousalIndex: 0.62, valenceStability: 0.78),
        engagement: EngagementAxis(
          engagementStability: 0.72,
          interactionCadence: 0.58,
        ),
        activity: ActivityAxis(motionIndex: 0.35, postureStability: 0.88),
        context: ContextAxis(
          screenActiveRatio: 0.85,
          sessionFragmentation: 0.22,
        ),
      ),
    ),
  );

  print('=== HSV: Internal Representation (Fast, Type-Safe) ===\n');
  print('Affect Arousal Index: ${hsv.meta.axes.affect.arousalIndex}');
  print(
    'Engagement Stability: ${hsv.meta.axes.engagement.engagementStability}',
  );
  print('Emotion Stress: ${hsv.emotion.stress}');
  print('Focus Score: ${hsv.focus.score}');

  // Convert to HSI 1.0 canonical format
  final hsi10 = hsv.toHSI10(
    producerName: 'Synheart Core Demo',
    producerVersion: '1.0.0',
    instanceId: 'demo-instance-001',
  );

  print('\n=== HSI 1.0: External Format (JSON Interoperability) ===\n');

  // Serialize to pretty JSON
  final encoder = JsonEncoder.withIndent('  ');
  final jsonString = encoder.convert(hsi10.toJson());

  print(jsonString);

  print('\n=== Validation Summary ===\n');
  print('✓ HSI Version: ${hsi10.hsiVersion}');
  print('✓ Window Count: ${hsi10.windowIds.length}');
  print('✓ Affect Readings: ${hsi10.axes?.affect?.readings.length ?? 0}');
  print('✓ Behavior Readings: ${hsi10.axes?.behavior?.readings.length ?? 0}');
  print('✓ Embedding Dimension: ${hsi10.embeddings?.first.dimension}');
  print('✓ Privacy Compliant: ${!hsi10.privacy.containsPii}');

  print('\n✅ Successfully exported HSI 1.0 compliant payload!');
  print('   This payload can be validated against:');
  print('   /Users/izzy/Desktop/synheart/hsi/schema/hsi-1.0.schema.json');
}
