import 'package:json_annotation/json_annotation.dart';

part 'emotion.g.dart';

/// Emotion state populated by the Emotion Engine (Synheart Emotion head)
@JsonSerializable()
class EmotionState {
  /// Stress level (0.0 - 1.0)
  final double stress;

  /// Calm level (0.0 - 1.0)
  final double calm;

  /// Engagement level (0.0 - 1.0)
  final double engagement;

  /// Activation level (0.0 - 1.0)
  final double activation;

  /// Valence (positive/negative emotion) (-1.0 to 1.0)
  final double valence;

  EmotionState({
    required this.stress,
    required this.calm,
    required this.engagement,
    required this.activation,
    required this.valence,
  });

  factory EmotionState.fromJson(Map<String, dynamic> json) =>
      _$EmotionStateFromJson(json);

  Map<String, dynamic> toJson() => _$EmotionStateToJson(this);

  /// Create an empty emotion state (before Emotion Engine populates it)
  factory EmotionState.empty() {
    return EmotionState(
      stress: 0.0,
      calm: 0.0,
      engagement: 0.0,
      activation: 0.0,
      valence: 0.0,
    );
  }
}

