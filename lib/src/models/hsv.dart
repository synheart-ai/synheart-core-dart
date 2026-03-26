/// Human State Vector - INTERNAL ONLY
///
/// The HSV is an intermediate representation computed by synheart-runtime.
/// It contains per-head inference results (emotion, focus, capacity, etc.)
/// with confidence and metadata.
///
/// This is NOT part of the public API - consumers use HSI instead.
/// Used internally for quality assessment, diagnostics, and SRM baselines.
class HumanStateVector {
  final int timestamp;
  final Map<String, dynamic> meta;
  final Map<String, dynamic> physiology;
  final double? heartRate;
  final double? hrvRmssd;
  final double? hrvSdnn;
  final List<double> hsiEmbedding;
  final Map<String, dynamic>? behavior;
  final Map<String, dynamic>? context;
  final Map<String, dynamic> stateQuality;
  final Map<String, dynamic> provenance;

  HumanStateVector({
    required this.timestamp,
    required this.meta,
    required this.physiology,
    this.heartRate,
    this.hrvRmssd,
    this.hrvSdnn,
    this.hsiEmbedding = const [],
    this.behavior,
    this.context,
    required this.stateQuality,
    required this.provenance,
  });

  factory HumanStateVector.fromJson(Map<String, dynamic> json) {
    return HumanStateVector(
      timestamp: json['timestamp'] as int? ?? 0,
      meta: json['meta'] as Map<String, dynamic>? ?? {},
      physiology: json['physiology'] as Map<String, dynamic>? ?? {},
      heartRate: (json['heartRate'] as num?)?.toDouble(),
      hrvRmssd: (json['hrvRmssd'] as num?)?.toDouble(),
      hrvSdnn: (json['hrvSdnn'] as num?)?.toDouble(),
      hsiEmbedding: (json['hsiEmbedding'] as List?)?.cast<double>() ?? [],
      behavior: json['behavior'] as Map<String, dynamic>?,
      context: json['context'] as Map<String, dynamic>?,
      stateQuality: json['stateQuality'] as Map<String, dynamic>? ?? {},
      provenance: json['provenance'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'meta': meta,
      'physiology': physiology,
      'heartRate': heartRate,
      'hrvRmssd': hrvRmssd,
      'hrvSdnn': hrvSdnn,
      'hsiEmbedding': hsiEmbedding,
      'behavior': behavior,
      'context': context,
      'stateQuality': stateQuality,
      'provenance': provenance,
    };
  }
}
