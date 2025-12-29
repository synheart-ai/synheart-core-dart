import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/synheart_core.dart';
import 'dart:convert';

void main() {
  group('HSI 1.0 Export', () {
    late HumanStateVector testHsv;

    setUp(() {
      // Create a test HSV with all axes populated
      testHsv = HumanStateVector(
        version: '1.0.0',
        timestamp: DateTime.utc(2025, 12, 28, 0, 0, 10).millisecondsSinceEpoch,
        emotion: EmotionState.empty(),
        focus: FocusState.empty(),
        behavior: BehaviorState(
          typingCadence: 0.5,
          typingBurstiness: 0.3,
          scrollVelocity: 0.4,
          idleGaps: 2.0,
          appSwitchRate: 0.1,
        ),
        context: ContextState(
          overload: 0.3,
          frustration: 0.2,
          engagement: 0.7,
          conversation: ConversationContext(
            avgReplyDelaySec: 5.0,
            burstiness: 0.4,
            interruptRate: 0.2,
          ),
          deviceState: DeviceStateContext(
            foreground: true,
            screenOn: true,
          ),
          userPatterns: UserPatternsContext(
            morningFocusBias: 0.6,
            avgSessionMinutes: 45.0,
            baselineTypingCadence: 0.5,
          ),
        ),
        meta: MetaState(
          sessionId: 'test-session-123',
          device: DeviceInfo(platform: 'flutter'),
          samplingRateHz: 2.0,
          embedding: StateEmbedding(
            vector: List.generate(64, (i) => i * 0.01),
            timestamp: DateTime.utc(2025, 12, 28, 0, 0, 10).millisecondsSinceEpoch,
            windowType: 'micro',
          ),
          axes: HSIAxes(
            affect: AffectAxis(
              arousalIndex: 0.72,
              valenceStability: 0.85,
            ),
            engagement: EngagementAxis(
              engagementStability: 0.68,
              interactionCadence: 0.54,
            ),
            activity: ActivityAxis(
              motionIndex: 0.42,
              postureStability: 0.91,
            ),
            context: ContextAxis(
              screenActiveRatio: 0.83,
              sessionFragmentation: 0.31,
            ),
          ),
        ),
      );
    });

    test('converts HumanStateVector to HSI 1.0 format', () {
      final hsi10 = testHsv.toHSI10();

      expect(hsi10.hsiVersion, equals('1.0'));
      expect(hsi10.windowIds, hasLength(1));
      expect(hsi10.windows, hasLength(1));
      expect(hsi10.producer.name, equals('Synheart Core SDK'));
      expect(hsi10.privacy.containsPii, isFalse);
    });

    test('generates valid timestamps', () {
      final hsi10 = testHsv.toHSI10();

      // Should be valid ISO 8601 timestamps
      expect(() => DateTime.parse(hsi10.observedAtUtc), returnsNormally);
      expect(() => DateTime.parse(hsi10.computedAtUtc), returnsNormally);

      // computed_at should be >= observed_at
      final observed = DateTime.parse(hsi10.observedAtUtc);
      final computed = DateTime.parse(hsi10.computedAtUtc);
      expect(computed.isAfter(observed) || computed.isAtSameMomentAs(observed), isTrue);
    });

    test('generates valid window structure', () {
      final hsi10 = testHsv.toHSI10();

      final windowId = hsi10.windowIds.first;
      expect(hsi10.windows.containsKey(windowId), isTrue);

      final window = hsi10.windows[windowId]!;
      expect(() => DateTime.parse(window.start), returnsNormally);
      expect(() => DateTime.parse(window.end), returnsNormally);

      // end should be after start
      final start = DateTime.parse(window.start);
      final end = DateTime.parse(window.end);
      expect(end.isAfter(start), isTrue);

      // Window should be 30 seconds for 'micro' type
      final duration = end.difference(start);
      expect(duration.inSeconds, equals(30));
    });

    test('converts affect axes to readings', () {
      final hsi10 = testHsv.toHSI10();

      expect(hsi10.axes, isNotNull);
      expect(hsi10.axes!.affect, isNotNull);

      final affectReadings = hsi10.axes!.affect!.readings;
      expect(affectReadings, hasLength(2));

      // Find arousal reading
      final arousal = affectReadings.firstWhere((r) => r.axis == 'arousal');
      expect(arousal.score, equals(0.72));
      expect(arousal.confidence, greaterThan(0.0));
      expect(arousal.confidence, lessThanOrEqualTo(1.0));
      expect(arousal.windowId, equals(hsi10.windowIds.first));
      expect(arousal.direction, equals('higher_is_more'));

      // Find valence_stability reading
      final valence = affectReadings.firstWhere((r) => r.axis == 'valence_stability');
      expect(valence.score, equals(0.85));
    });

    test('converts engagement/activity/context to behavior domain', () {
      final hsi10 = testHsv.toHSI10();

      expect(hsi10.axes, isNotNull);
      expect(hsi10.axes!.behavior, isNotNull);

      final behaviorReadings = hsi10.axes!.behavior!.readings;
      expect(behaviorReadings.length, greaterThanOrEqualTo(4));

      // Check engagement_stability
      final engagement = behaviorReadings.firstWhere(
        (r) => r.axis == 'engagement_stability',
        orElse: () => throw Exception('engagement_stability not found'),
      );
      expect(engagement.score, equals(0.68));

      // Check motion
      final motion = behaviorReadings.firstWhere(
        (r) => r.axis == 'motion',
        orElse: () => throw Exception('motion not found'),
      );
      expect(motion.score, equals(0.42));
    });

    test('converts embedding with proper structure', () {
      final hsi10 = testHsv.toHSI10();

      expect(hsi10.embeddings, isNotNull);
      expect(hsi10.embeddings, hasLength(1));

      final embedding = hsi10.embeddings!.first;
      expect(embedding.vector, hasLength(64));
      expect(embedding.dimension, equals(64));
      expect(embedding.encoding, equals('float64'));
      expect(embedding.confidence, greaterThan(0.0));
      expect(embedding.confidence, lessThanOrEqualTo(1.0));
      expect(embedding.windowId, equals(hsi10.windowIds.first));
      expect(embedding.model, equals('hsi-fusion-v1'));
    });

    test('includes required privacy fields', () {
      final hsi10 = testHsv.toHSI10();

      expect(hsi10.privacy.containsPii, isFalse);
      expect(hsi10.privacy.rawBiosignalsAllowed, isFalse);
      expect(hsi10.privacy.derivedMetricsAllowed, isTrue);
    });

    test('includes metadata', () {
      final hsi10 = testHsv.toHSI10();

      expect(hsi10.meta, isNotNull);
      expect(hsi10.meta!['sdk'], equals('synheart_core'));
      expect(hsi10.meta!['platform'], equals('flutter'));
      expect(hsi10.meta!['sampling_rate_hz'], equals(2.0));
    });

    test('serializes to valid JSON', () {
      final hsi10 = testHsv.toHSI10();
      final json = hsi10.toJson();

      // Should be serializable
      expect(() => jsonEncode(json), returnsNormally);

      // Check top-level required fields
      expect(json['hsi_version'], equals('1.0'));
      expect(json['observed_at_utc'], isA<String>());
      expect(json['computed_at_utc'], isA<String>());
      expect(json['producer'], isA<Map>());
      expect(json['window_ids'], isA<List>());
      expect(json['windows'], isA<Map>());
      expect(json['privacy'], isA<Map>());
    });

    test('allows custom producer metadata', () {
      final hsi10 = testHsv.toHSI10(
        producerName: 'Custom Producer',
        producerVersion: '2.0.0',
        instanceId: 'custom-instance-456',
      );

      expect(hsi10.producer.name, equals('Custom Producer'));
      expect(hsi10.producer.version, equals('2.0.0'));
      expect(hsi10.producer.instanceId, equals('custom-instance-456'));
    });

    test('handles partial axes gracefully', () {
      // Create HSV with only affect axis populated
      final partialHsv = HumanStateVector(
        version: '1.0.0',
        timestamp: DateTime.utc(2025, 12, 28).millisecondsSinceEpoch,
        emotion: EmotionState.empty(),
        focus: FocusState.empty(),
        behavior: BehaviorState(
          typingCadence: 0.5,
          typingBurstiness: 0.3,
          scrollVelocity: 0.4,
          idleGaps: 2.0,
          appSwitchRate: 0.1,
        ),
        context: ContextState(
          overload: 0.3,
          frustration: 0.2,
          engagement: 0.7,
          conversation: ConversationContext(
            avgReplyDelaySec: 5.0,
            burstiness: 0.4,
            interruptRate: 0.2,
          ),
          deviceState: DeviceStateContext(foreground: true, screenOn: true),
          userPatterns: UserPatternsContext(
            morningFocusBias: 0.6,
            avgSessionMinutes: 45.0,
            baselineTypingCadence: 0.5,
          ),
        ),
        meta: MetaState(
          sessionId: 'test',
          device: DeviceInfo(platform: 'flutter'),
          samplingRateHz: 2.0,
          embedding: StateEmbedding(
            vector: List.filled(64, 0.0),
            timestamp: DateTime.utc(2025, 12, 28).millisecondsSinceEpoch,
            windowType: 'micro',
          ),
          axes: HSIAxes(
            affect: AffectAxis(arousalIndex: 0.5), // Only arousal
            engagement: EngagementAxis.empty(),
            activity: ActivityAxis.empty(),
            context: ContextAxis.empty(),
          ),
        ),
      );

      final hsi10 = partialHsv.toHSI10();

      expect(hsi10.axes, isNotNull);
      expect(hsi10.axes!.affect, isNotNull);
      expect(hsi10.axes!.affect!.readings, hasLength(1));
      expect(hsi10.axes!.affect!.readings.first.axis, equals('arousal'));
    });

    test('JSON round-trip preserves data', () {
      final hsi10 = testHsv.toHSI10();
      final json = hsi10.toJson();
      final recovered = HSI10Payload.fromJson(json);

      expect(recovered.hsiVersion, equals(hsi10.hsiVersion));
      expect(recovered.observedAtUtc, equals(hsi10.observedAtUtc));
      expect(recovered.producer.name, equals(hsi10.producer.name));
      expect(recovered.windowIds, equals(hsi10.windowIds));
      expect(recovered.privacy.containsPii, equals(hsi10.privacy.containsPii));
    });
  });

  group('HSI 1.0 Window Types', () {
    test('micro window is 30 seconds', () {
      final hsv = _createTestHSV('micro');
      final hsi10 = hsv.toHSI10();

      final window = hsi10.windows[hsi10.windowIds.first]!;
      final duration = DateTime.parse(window.end)
          .difference(DateTime.parse(window.start));
      expect(duration.inSeconds, equals(30));
      expect(window.label, equals('micro_window'));
    });

    test('short window is 5 minutes', () {
      final hsv = _createTestHSV('short');
      final hsi10 = hsv.toHSI10();

      final window = hsi10.windows[hsi10.windowIds.first]!;
      final duration = DateTime.parse(window.end)
          .difference(DateTime.parse(window.start));
      expect(duration.inMinutes, equals(5));
      expect(window.label, equals('short_window'));
    });

    test('medium window is 1 hour', () {
      final hsv = _createTestHSV('medium');
      final hsi10 = hsv.toHSI10();

      final window = hsi10.windows[hsi10.windowIds.first]!;
      final duration = DateTime.parse(window.end)
          .difference(DateTime.parse(window.start));
      expect(duration.inHours, equals(1));
      expect(window.label, equals('medium_window'));
    });

    test('long window is 24 hours', () {
      final hsv = _createTestHSV('long');
      final hsi10 = hsv.toHSI10();

      final window = hsi10.windows[hsi10.windowIds.first]!;
      final duration = DateTime.parse(window.end)
          .difference(DateTime.parse(window.start));
      expect(duration.inHours, equals(24));
      expect(window.label, equals('long_window'));
    });
  });
}

/// Helper to create a test HSV with specific window type
HumanStateVector _createTestHSV(String windowType) {
  return HumanStateVector(
    version: '1.0.0',
    timestamp: DateTime.utc(2025, 12, 28, 0, 0, 10).millisecondsSinceEpoch,
    emotion: EmotionState.empty(),
    focus: FocusState.empty(),
    behavior: BehaviorState(
      typingCadence: 0.5,
      typingBurstiness: 0.3,
      scrollVelocity: 0.4,
      idleGaps: 2.0,
      appSwitchRate: 0.1,
    ),
    context: ContextState(
      overload: 0.3,
      frustration: 0.2,
      engagement: 0.7,
      conversation: ConversationContext(
        avgReplyDelaySec: 5.0,
        burstiness: 0.4,
        interruptRate: 0.2,
      ),
      deviceState: DeviceStateContext(foreground: true, screenOn: true),
      userPatterns: UserPatternsContext(
        morningFocusBias: 0.6,
        avgSessionMinutes: 45.0,
        baselineTypingCadence: 0.5,
      ),
    ),
    meta: MetaState(
      sessionId: 'test-session',
      device: DeviceInfo(platform: 'flutter'),
      samplingRateHz: 2.0,
      embedding: StateEmbedding(
        vector: List.filled(64, 0.0),
        timestamp: DateTime.utc(2025, 12, 28, 0, 0, 10).millisecondsSinceEpoch,
        windowType: windowType,
      ),
      axes: HSIAxes(
        affect: AffectAxis(arousalIndex: 0.5),
        engagement: EngagementAxis.empty(),
        activity: ActivityAxis.empty(),
        context: ContextAxis.empty(),
      ),
    ),
  );
}
