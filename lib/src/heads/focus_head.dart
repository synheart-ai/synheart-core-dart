import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/hsv.dart';
import '../models/focus.dart';
// import 'package:synheart_focus/synheart_focus.dart';

/// Focus Engine (Synheart Focus Head)
/// 
/// Model head that subscribes to HSI stream (optionally with emotion)
/// and populates hsv.focus
class FocusHead {
  // final FocusModel _focusModel; // From synheart_focus package
  StreamSubscription<HumanStateVector>? _subscription;
  final BehaviorSubject<HumanStateVector> _focusStream =
      BehaviorSubject<HumanStateVector>();

  bool _isActive = false;

  FocusHead() {
    // TODO: Initialize synheart_focus model
    // _focusModel = FocusModel();
  }

  /// Stream of HSVs with focus populated
  Stream<HumanStateVector> get focusStream => _focusStream.stream;

  /// Start the focus head, subscribing to HSV stream (with emotion)
  void start(Stream<HumanStateVector> emotionStream) {
    if (_isActive) return;

    _isActive = true;
    _subscription = emotionStream.listen((hsvWithEmotion) async {
      // Extract features from HSV for focus prediction
      final features = _extractFeatures(hsvWithEmotion);

      // Predict focus using synheart_focus model
      final focusScores = await _predictFocus(features);

      // Create focus state
      final focus = FocusState(
        score: focusScores['score'] ?? 0.0,
        cognitiveLoad: focusScores['cognitive_load'] ?? 0.0,
        clarity: focusScores['clarity'] ?? 0.0,
        distraction: focusScores['distraction'] ?? 0.0,
      );

      // Update HSV with focus
      final hsvWithFocus = hsvWithEmotion.copyWithFocus(focus);

      // Emit final HSV
      _focusStream.add(hsvWithFocus);
    });
  }

  /// Stop the focus head
  Future<void> stop() async {
    _isActive = false;
    await _subscription?.cancel();
  }

  /// Extract features from HSV for focus prediction
  Map<String, double> _extractFeatures(HumanStateVector hsv) {
    // Extract relevant features from HSV for focus model
    return {
      'hsi_embedding': hsv.meta.hsiEmbedding.isNotEmpty ? hsv.meta.hsiEmbedding.first : 0.0,
      'typing_cadence': hsv.behavior.typingCadence,
      'typing_burstiness': hsv.behavior.typingBurstiness,
      'idle_gaps': hsv.behavior.idleGaps,
      'app_switch_rate': hsv.behavior.appSwitchRate,
      'stress': hsv.emotion.stress,
      'calm': hsv.emotion.calm,
      'engagement': hsv.emotion.engagement,
      'activation': hsv.emotion.activation,
      'overload': hsv.context.overload,
      'cognitive_load': hsv.context.overload, // Can use context overload as proxy
      // Add more features as needed
    };
  }

  /// Predict focus using synheart_focus model
  Future<Map<String, double>> _predictFocus(Map<String, double> features) async {
    // TODO: Call synheart_focus package
    // return await _focusModel.predict(features);
    
    // Placeholder: return sample focus scores
    return {
      'score': 0.68,
      'cognitive_load': 0.32,
      'clarity': 0.71,
      'distraction': 0.19,
    };
  }

  Future<void> dispose() async {
    await stop();
    await _focusStream.close();
  }
}

