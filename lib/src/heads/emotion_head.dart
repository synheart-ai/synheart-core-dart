import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/hsv.dart';
import '../models/emotion.dart';
import 'package:synheart_emotion/synheart_emotion.dart' as se;

/// Emotion Engine (Synheart Emotion Head)
///
/// Model head that subscribes to HSI Core stream and populates hsv.emotion
/// Uses EmotionEngine from synheart_emotion package for inference.
class EmotionHead {
  StreamSubscription<HumanStateVector>? _subscription;
  final BehaviorSubject<HumanStateVector> _emotionStream =
      BehaviorSubject<HumanStateVector>();

  se.EmotionEngine? _engine;
  final se.EmotionConfig _config = const se.EmotionConfig(
    window: Duration(seconds: 10),  // Short window for near-realtime
    step: Duration(seconds: 1),     // Frequent updates
    minRrCount: 5,                  // Lower threshold
  );

  bool _isActive = false;

  EmotionHead();

  /// Stream of HSVs with emotion populated
  Stream<HumanStateVector> get emotionStream => _emotionStream.stream;

  /// Start the emotion head, subscribing to base HSV stream
  void start(Stream<HumanStateVector> baseHsvStream) {
    if (_isActive) return;

    _isActive = true;
    _subscription = baseHsvStream.listen((baseHsv) {
      _ensureEngineInitialized();

      // Extract features for synheart_emotion engine
      final features = _extractOnnxFeatures(baseHsv);
      if (features == null) {
        // Not enough signal quality / missing biosignal features yet.
        return;
      }

      // Synthesize RR intervals from features for EmotionEngine
      // This is a temporary workaround until we have raw RR data in HSV
      final hr = features['hr_mean']!;
      final meanRr = features['mean_rr']!;

      // Generate synthetic RR intervals with slight variance to simulate natural variation
      final syntheticRR = List.generate(10, (i) {
        final variance = (i % 3 - 1) * 10.0; // Small variance: -10, 0, +10 ms
        return meanRr + variance;
      });

      // Push to EmotionEngine
      _engine!.push(
        hr: hr,
        rrIntervalsMs: syntheticRR,
        timestamp: DateTime.fromMillisecondsSinceEpoch(baseHsv.timestamp),
      );

      // Consume results from EmotionEngine
      final results = _engine!.consumeReady();
      if (results.isEmpty) {
        // No results ready yet (waiting for step interval or more data)
        return;
      }

      final result = results.first;

      // Map synheart_emotion EmotionResult -> synheart_core EmotionState
      final calm = (result.probabilities['Calm'] ?? 0.0).clamp(0.0, 1.0).toDouble();
      final stress = (result.probabilities['Stressed'] ?? 0.0).clamp(0.0, 1.0).toDouble();
      final amused = (result.probabilities['Amused'] ?? 0.0).clamp(0.0, 1.0).toDouble();

      final emotion = EmotionState(
        stress: stress,
        calm: calm,
        engagement: amused,
        activation: ((amused + stress) / 2.0).clamp(0.0, 1.0).toDouble(),
        valence: (calm + amused - stress).clamp(-1.0, 1.0).toDouble(),
      );

      // Update HSV with emotion
      final hsvWithEmotion = baseHsv.copyWithEmotion(emotion);

      // Emit updated HSV
      _emotionStream.add(hsvWithEmotion);
    });
  }

  /// Stop the emotion head
  Future<void> stop() async {
    _isActive = false;
    await _subscription?.cancel();
  }

  void _ensureEngineInitialized() {
    if (_engine != null) return;

    _engine = se.EmotionEngine.fromPretrained(
      _config,
      onLog: (level, message, {context}) {
        // Optional: log emotions for debugging
        // print('[EmotionHead][$level] $message');
      },
    );
  }

  /// Extract the synheart_emotion model feature map from HSV.
  ///
  /// The ONNX model expects HRV features, which we expose in the HSI embedding:
  /// - [0] HR_mean (bpm)
  /// - [1] RMSSD (ms)
  /// - [2] SDNN (ms)
  /// - [3] pNN50 (%)
  /// - [4] Mean_RR (ms)
  Map<String, double>? _extractOnnxFeatures(HumanStateVector hsv) {
    final emb = hsv.meta.embedding.vector;
    if (emb.length < 5) {
      return null;
    }

    final hrMean = emb[0];
    final rmssd = emb[1];
    final sdnn = emb[2];
    final pnn50 = emb[3];
    var meanRr = emb[4];

    if (hrMean <= 0) {
      return null;
    }
    if (meanRr <= 0) {
      // Fallback: derive mean RR from HR mean.
      meanRr = 60000.0 / hrMean;
    }

    return {
      'hr_mean': hrMean,
      'rmssd': rmssd,
      'sdnn': sdnn,
      'pnn50': pnn50,
      'mean_rr': meanRr,
    };
  }

  Future<void> dispose() async {
    await stop();
    // Clear EmotionEngine buffer
    _engine?.clear();
    _engine = null;
    await _emotionStream.close();
  }
}

