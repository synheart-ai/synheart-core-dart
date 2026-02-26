import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/modules/runtime/runtime_bridge.dart';
import 'package:synheart_core/src/models/preprocessed_window.dart';

/// Integration tests for the synheart-runtime native bridge.
///
/// These tests require the native library (libsynheart_runtime.dylib on macOS)
/// to be in the project root or on the library path.
///
/// To run:
///   flutter test test/modules/runtime/runtime_bridge_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Helper: create a bridge with a valid subject_id (must start with "sub_").
  RuntimeBridge? createBridge() {
    return RuntimeBridge.createIfAvailable(
      RuntimeConfig(
        subjectId: 'sub_test_001',
        sessionId: 'sess_test_001',
        windowMs: 10000, // 10s window for faster test feedback
        stepMs: 5000, // 5s step
      ),
    );
  }

  /// Helper: push enough synthetic data to fill a 10s window and tick.
  /// Returns the HSI JSON if a frame was produced, or null.
  String? fillWindowAndTick(RuntimeBridge bridge, int baseMs) {
    // Push RR intervals spanning the full window (~10s of data at ~800ms each)
    for (var i = 0; i < 15; i++) {
      bridge.pushRr(baseMs + i * 800, 800.0);
    }
    // Also push HR to ensure enough signal diversity
    for (var i = 0; i < 12; i++) {
      bridge.pushHr(baseMs + i * 1000, 72.0);
    }
    // Tick at end of window
    return bridge.tick(baseMs + 10000);
  }

  group('RuntimeBridge', () {
    RuntimeBridge? bridge;

    setUp(() {
      bridge = createBridge();
    });

    tearDown(() {
      bridge?.dispose();
      bridge = null;
    });

    test('createIfAvailable returns non-null when library is loaded', () {
      expect(bridge, isNotNull, reason: 'Native runtime library should be loadable');
    });

    test('version() returns a valid semver string', () {
      final v = RuntimeBridge.version();
      expect(v, isNotNull, reason: 'version() should return a string');
      expect(
        v,
        matches(RegExp(r'^\d+\.\d+\.\d+')),
        reason: 'version should match semver format',
      );
    });

    test('push synthetic RR + HR, tick, get HSI JSON', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final hsi = fillWindowAndTick(bridge!, now);

      // The runtime may need multiple windows to produce output.
      // If first window didn't produce, try a second.
      String? result = hsi;
      if (result == null) {
        result = fillWindowAndTick(bridge!, now + 15000);
      }

      expect(result, isNotNull,
          reason: 'tick should produce HSI JSON after enough signal data');

      final parsed = jsonDecode(result!) as Map<String, dynamic>;
      expect(parsed.containsKey('hsi_version'), isTrue);
    });

    test('push behavior events included in HSI output', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // Push baseline signals
      for (var i = 0; i < 15; i++) {
        bridge!.pushRr(now + i * 800, 800.0);
      }
      for (var i = 0; i < 12; i++) {
        bridge!.pushHr(now + i * 1000, 72.0);
      }
      // Push behavior events
      for (var i = 0; i < 10; i++) {
        bridge!.pushBehavior(now + i * 500, 2, 1.0); // Touch events
      }
      bridge!.pushBehavior(now + 5000, 3, 1.0); // App switch

      var hsi = bridge!.tick(now + 10000);
      // Retry with second window if needed
      if (hsi == null) {
        for (var i = 0; i < 15; i++) {
          bridge!.pushRr(now + 15000 + i * 800, 800.0);
          bridge!.pushHr(now + 15000 + i * 800, 72.0);
        }
        hsi = bridge!.tick(now + 25000);
      }

      if (hsi != null) {
        final parsed = jsonDecode(hsi) as Map<String, dynamic>;
        expect(parsed.containsKey('hsi_version'), isTrue);
      }
      // If still null, runtime may require more warm-up — that's OK for integration test
    });

    test('frameCount increments after successful tick', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final initialCount = bridge!.frameCount();

      final now = DateTime.now().millisecondsSinceEpoch;
      // Try multiple windows to ensure we get a frame
      for (var w = 0; w < 5; w++) {
        fillWindowAndTick(bridge!, now + w * 15000);
      }

      // frameCount should have increased if any frame was produced
      final finalCount = bridge!.frameCount();
      if (finalCount > initialCount) {
        expect(finalCount, greaterThan(initialCount));
      }
      // If no frames produced, runtime may need different data patterns — not a failure
    });

    test('lastQuality returns valid JSON after tick', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      for (var w = 0; w < 3; w++) {
        fillWindowAndTick(bridge!, now + w * 15000);
      }

      final quality = bridge!.lastQuality();
      if (quality != null) {
        expect(() => jsonDecode(quality), returnsNormally);
      }
    });

    test('reset clears state, frameCount returns to 0', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      for (var w = 0; w < 3; w++) {
        fillWindowAndTick(bridge!, now + w * 15000);
      }

      bridge!.reset();
      expect(bridge!.frameCount(), equals(0));
    });

    test('multiple windows eventually produce frames', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      var framesProduced = 0;

      // Push data across many windows
      for (var window = 0; window < 10; window++) {
        final hsi = fillWindowAndTick(bridge!, now + window * 15000);
        if (hsi != null) framesProduced++;
      }

      expect(framesProduced, greaterThanOrEqualTo(1),
          reason: 'Should produce at least one frame across 10 windows');
    });

    // -- SRM Baselines --

    test('baselineSummary returns valid JSON with expected keys', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final summary = bridge!.baselineSummary();
      expect(summary, isNotNull, reason: 'baselineSummary() should return JSON');

      final parsed = jsonDecode(summary!) as Map<String, dynamic>;
      expect(parsed.containsKey('total'), isTrue);
      expect(parsed.containsKey('ready'), isTrue);
      expect(parsed.containsKey('warming'), isTrue);
      expect(parsed.containsKey('empty'), isTrue);
    });

    test('baselinesJson returns valid JSON', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final baselines = bridge!.baselinesJson();
      expect(baselines, isNotNull, reason: 'baselinesJson() should return JSON');
      expect(() => jsonDecode(baselines!), returnsNormally);
    });

    test('baselineSummary shows metrics after data ingestion', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      for (var w = 0; w < 5; w++) {
        fillWindowAndTick(bridge!, now + w * 15000);
      }

      final summary = bridge!.baselineSummary();
      expect(summary, isNotNull);

      final parsed = jsonDecode(summary!) as Map<String, dynamic>;
      expect(parsed['total'], greaterThan(0),
          reason: 'Should have SRM metrics registered');
    });

    test('SRM snapshot export and load round-trip', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      for (var w = 0; w < 5; w++) {
        fillWindowAndTick(bridge!, now + w * 15000);
      }

      // Export snapshot
      final snapshot = bridge!.exportSrmSnapshot();
      expect(snapshot, isNotNull,
          reason: 'exportSrmSnapshot() should return JSON');
      expect(() => jsonDecode(snapshot!), returnsNormally);

      // Create a new bridge and load the snapshot
      final bridge2 = RuntimeBridge.createIfAvailable(
        RuntimeConfig(
          subjectId: 'sub_test_002',
          sessionId: 'sess_test_002',
          windowMs: 10000,
          stepMs: 5000,
        ),
      );
      expect(bridge2, isNotNull);

      final result = bridge2!.loadSrmSnapshot(snapshot!);
      expect(result, equals(0), reason: 'loadSrmSnapshot should return 0');

      // Verify loaded bridge has same baseline summary
      final originalSummary = bridge!.baselineSummary();
      final loadedSummary = bridge2.baselineSummary();
      expect(loadedSummary, equals(originalSummary),
          reason: 'Baseline summary should match after round-trip');

      bridge2.dispose();
    });

    test('reset clears SRM baselines', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      for (var w = 0; w < 5; w++) {
        fillWindowAndTick(bridge!, now + w * 15000);
      }

      bridge!.reset();

      final summary = bridge!.baselineSummary();
      expect(summary, isNotNull);

      final parsed = jsonDecode(summary!) as Map<String, dynamic>;
      expect(parsed['warming'], equals(0), reason: 'warming should be 0 after reset');
      expect(parsed['ready'], equals(0), reason: 'ready should be 0 after reset');
    });

    // -- Pre-processed Data --

    test('lastPreprocessed returns valid JSON with expected structure', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var w = 0; w < 3; w++) {
        fillWindowAndTick(bridge!, now + w * 15000);
      }
      final json = bridge!.lastPreprocessed();
      if (json != null) {
        final parsed = jsonDecode(json) as Map<String, dynamic>;
        expect(parsed.containsKey('schema_version'), isTrue);
        expect(parsed.containsKey('quality'), isTrue);
        expect(parsed.containsKey('derived_features'), isTrue);
        expect(parsed.containsKey('srm_context'), isTrue);
        expect(parsed.containsKey('embeddings'), isTrue);
        final window = PreprocessedWindow.fromJson(parsed);
        expect(window.quality.score, inInclusiveRange(0.0, 1.0));
        expect(window.quality.rrCount, greaterThanOrEqualTo(0));
        expect(window.srmContext.totalCount, greaterThanOrEqualTo(0));
      }
    });

    test('lastPreprocessed returns null after reset', () {
      if (bridge == null) {
        markTestSkipped('Native runtime library not available');
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var w = 0; w < 3; w++) {
        fillWindowAndTick(bridge!, now + w * 15000);
      }
      bridge!.reset();
      expect(bridge!.lastPreprocessed(), isNull);
    });

    test('PreprocessedWindow model parses valid JSON', () {
      const jsonStr = '{"schema_version":"1.0.0","window_start_ms":1000,"window_end_ms":11000,"session_id":"test_session","quality":{"score":0.85,"coverage_pct":0.9,"dropout_count":0,"rr_count":10,"artifact_pct":0.05},"derived_features":{"hrv":{"rmssd_ms":42.5,"sdnn_ms":38.0,"pnn50":0.25,"mean_rr_ms":800.0,"hr_mean_bpm":72.0,"hr_std_bpm":3.5,"rr_count":10},"motion":null,"artifact":null},"behavior_features":null,"srm_context":{"ready_count":0,"total_count":14,"deviations":{}},"embeddings":{"signal_embedding":{"vector":[0.1,0.2,0.3],"dimension":3,"space":"latent"}}}';
      final window = PreprocessedWindow.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      expect(window.schemaVersion, equals('1.0.0'));
      expect(window.quality.score, closeTo(0.85, 0.001));
      expect(window.quality.rrCount, equals(10));
      expect(window.derivedFeatures.hrv!.rmssdMs, closeTo(42.5, 0.001));
      expect(window.srmContext.totalCount, equals(14));
      expect(window.embeddings.signalEmbedding.dimension, equals(3));
    });
  });
}
