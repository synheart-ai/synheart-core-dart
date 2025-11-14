import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/hsv.dart';
import '../models/emotion.dart';
// import 'package:synheart_emotion/synheart_emotion.dart';

/// Emotion Engine (Synheart Emotion Head)
/// 
/// Model head that subscribes to HSI Core stream and populates hsv.emotion
class EmotionHead {
  // final EmotionModel _emotionModel; // From synheart_emotion package
  StreamSubscription<HumanStateVector>? _subscription;
  final BehaviorSubject<HumanStateVector> _emotionStream =
      BehaviorSubject<HumanStateVector>();

  bool _isActive = false;

  EmotionHead() {
    // TODO: Initialize synheart_emotion model
    // _emotionModel = EmotionModel();
  }

  /// Stream of HSVs with emotion populated
  Stream<HumanStateVector> get emotionStream => _emotionStream.stream;

  /// Start the emotion head, subscribing to base HSV stream
  void start(Stream<HumanStateVector> baseHsvStream) {
    if (_isActive) return;

    _isActive = true;
    _subscription = baseHsvStream.listen((baseHsv) async {
      // Extract features from base HSV
      final features = _extractFeatures(baseHsv);

      // Predict emotion using synheart_emotion model
      final emotionScores = await _predictEmotion(features);

      // Create emotion state
      final emotion = EmotionState(
        stress: emotionScores['stress'] ?? 0.0,
        calm: emotionScores['calm'] ?? 0.0,
        engagement: emotionScores['engagement'] ?? 0.0,
        activation: emotionScores['activation'] ?? 0.0,
        valence: emotionScores['valence'] ?? 0.0,
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

  /// Extract features from HSV for emotion prediction
  Map<String, double> _extractFeatures(HumanStateVector hsv) {
    // Extract relevant features from HSV for emotion model
    return {
      'hsi_embedding': hsv.meta.hsiEmbedding.isNotEmpty ? hsv.meta.hsiEmbedding.first : 0.0,
      'hr': hsv.meta.hsiEmbedding.length > 0 ? hsv.meta.hsiEmbedding[0] : 0.0,
      'hrv': hsv.meta.hsiEmbedding.length > 1 ? hsv.meta.hsiEmbedding[1] : 0.0,
      'typing_cadence': hsv.behavior.typingCadence,
      'typing_burstiness': hsv.behavior.typingBurstiness,
      'scroll_velocity': hsv.behavior.scrollVelocity,
      'overload': hsv.context.overload,
      'frustration': hsv.context.frustration,
      'engagement': hsv.context.engagement,
      // Add more features as needed
    };
  }

  /// Predict emotion using synheart_emotion model
  Future<Map<String, double>> _predictEmotion(Map<String, double> features) async {
    // TODO: Call synheart_emotion package
    // return await _emotionModel.predict(features);
    
    // Placeholder: return sample emotion scores
    return {
      'stress': 0.21,
      'calm': 0.74,
      'engagement': 0.68,
      'activation': 0.45,
      'valence': 0.31,
    };
  }

  Future<void> dispose() async {
    await stop();
    await _emotionStream.close();
  }
}

