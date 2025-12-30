import 'package:json_annotation/json_annotation.dart';

part 'focus.g.dart';

/// Focus state populated by the Focus Engine (Synheart Focus head)
@JsonSerializable()
class FocusState {
  /// Overall focus score (0.0 - 1.0)
  final double score;

  /// Cognitive load (0.0 - 1.0)
  final double cognitiveLoad;

  /// Clarity level (0.0 - 1.0)
  final double clarity;

  /// Distraction level (0.0 - 1.0)
  final double distraction;

  FocusState({
    required this.score,
    required this.cognitiveLoad,
    required this.clarity,
    required this.distraction,
  });

  factory FocusState.fromJson(Map<String, dynamic> json) =>
      _$FocusStateFromJson(json);

  Map<String, dynamic> toJson() => _$FocusStateToJson(this);

  /// Create an empty focus state (before Focus Engine populates it)
  factory FocusState.empty() {
    return FocusState(
      score: 0.0,
      cognitiveLoad: 0.0,
      clarity: 0.0,
      distraction: 0.0,
    );
  }
}
