import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/hsv.dart';
import '../models/emotion.dart';
import 'package:synheart_emotion/synheart_emotion.dart' as se;

/// Emotion Engine (Synheart Emotion Head)
/// 
/// Model head that subscribes to HSI Core stream and populates hsv.emotion
class EmotionHead {
  StreamSubscription<HumanStateVector>? _subscription;
  final BehaviorSubject<HumanStateVector> _emotionStream =
      BehaviorSubject<HumanStateVector>();

  se.OnnxEmotionModel? _model;
  Future<se.OnnxEmotionModel>? _modelFuture;

  bool _isActive = false;

  EmotionHead();

  /// Stream of HSVs with emotion populated
  Stream<HumanStateVector> get emotionStream => _emotionStream.stream;

  /// Start the emotion head, subscribing to base HSV stream
  void start(Stream<HumanStateVector> baseHsvStream) {
    if (_isActive) return;

    _isActive = true;
    _subscription = baseHsvStream.listen((baseHsv) async {
      final model = await _ensureModelLoaded();

      // Extract features for synheart_emotion ONNX model
      final features = _extractOnnxFeatures(baseHsv);
      if (features == null) {
        // Not enough signal quality / missing biosignal features yet.
        return;
      }

      // Predict emotion probabilities using synheart_emotion
      final probs = await model.predictAsync(features);

      // Map synheart_emotion outputs -> synheart_core EmotionState
      final calm = (probs['Calm'] ?? 0.0).clamp(0.0, 1.0).toDouble();
      final stress = (probs['Stressed'] ?? 0.0).clamp(0.0, 1.0).toDouble();
      final amused = (probs['Amused'] ?? 0.0).clamp(0.0, 1.0).toDouble();

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

  Future<se.OnnxEmotionModel> _ensureModelLoaded() {
    if (_model != null) {
      return Future.value(_model);
    }
    _modelFuture ??= se.OnnxEmotionModel.loadFromAsset(
      // Dependency assets must be loaded with the packages/ prefix.
      modelAssetPath:
          'packages/synheart_emotion/assets/ml/extratrees_wrist_all_v1_0.onnx',
      metaAssetPath:
          'packages/synheart_emotion/assets/ml/extratrees_wrist_all_v1_0.meta.json',
    ).then((m) {
      _model = m;
      return m;
    });
    return _modelFuture!;
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
    final emb = hsv.meta.hsiEmbedding;
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
    final model = _model;
    _model = null;
    if (model != null) {
      await model.dispose();
    }
    await _emotionStream.close();
  }
}

