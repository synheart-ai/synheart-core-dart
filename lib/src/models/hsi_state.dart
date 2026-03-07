import 'dart:convert';

/// A single HSI axis reading with value and confidence.
class HSIAxisValue {
  final double value;
  final double confidence;

  const HSIAxisValue({required this.value, required this.confidence});

  factory HSIAxisValue.fromJson(Map<String, dynamic> json) => HSIAxisValue(
        value: (json['value'] as num?)?.toDouble() ?? 0.0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {'value': value, 'confidence': confidence};
}

/// The four canonical HSI axes.
class HSIAxes {
  final HSIAxisValue? focus;
  final HSIAxisValue? arousal;
  final HSIAxisValue? capacity;
  final HSIAxisValue? sleep;

  const HSIAxes({this.focus, this.arousal, this.capacity, this.sleep});

  factory HSIAxes.fromJson(Map<String, dynamic> json) => HSIAxes(
        focus: json['focus'] is Map
            ? HSIAxisValue.fromJson(json['focus'] as Map<String, dynamic>)
            : null,
        arousal: json['arousal'] is Map
            ? HSIAxisValue.fromJson(json['arousal'] as Map<String, dynamic>)
            : null,
        capacity: json['capacity'] is Map
            ? HSIAxisValue.fromJson(json['capacity'] as Map<String, dynamic>)
            : null,
        sleep: json['sleep'] is Map
            ? HSIAxisValue.fromJson(json['sleep'] as Map<String, dynamic>)
            : null,
      );
}

/// Typed HSI state emitted by `Synheart.onStateUpdate` (RFC-CORE-0007 §3).
///
/// Preserves the raw JSON for backward compatibility while providing
/// typed axis accessors.
class HSIState {
  final String subjectId;
  final int timestampMs;
  final HSIAxes hsi;
  final String rawJson;

  const HSIState({
    required this.subjectId,
    required this.timestampMs,
    required this.hsi,
    required this.rawJson,
  });

  /// Parse an HSI JSON string from the runtime into a typed [HSIState].
  factory HSIState.fromJson(String json, {String subjectId = ''}) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final timestampMs = (map['timestamp_ms'] as num?)?.toInt() ??
          (map['observed_at_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;

      final hsiMap = (map['hsi'] as Map<String, dynamic>?) ?? map;
      final sid = (map['subject_id'] as String?) ?? subjectId;

      return HSIState(
        subjectId: sid,
        timestampMs: timestampMs,
        hsi: HSIAxes.fromJson(hsiMap),
        rawJson: json,
      );
    } catch (_) {
      return HSIState(
        subjectId: subjectId,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        hsi: const HSIAxes(),
        rawJson: json,
      );
    }
  }
}
