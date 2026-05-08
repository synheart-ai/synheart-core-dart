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

/// Modality availability derived from `meta.provenance.sources[*].signals` per
/// the Synheart Runtime signal-modality mapping spec.
///
/// Apps gate UX on these booleans (e.g. drop physiology copy when
/// `physiological == false`).
class Modalities {
  final bool physiological;
  final bool kinematic;
  final bool digital;

  const Modalities({
    this.physiological = false,
    this.kinematic = false,
    this.digital = false,
  });

  bool get isEmpty => !physiological && !kinematic && !digital;
}

/// Per-modality fidelity bundle. Pre-canonical: in HSI 1.3 this becomes
/// per-axis `tiers`. Lower-numbered tier = higher fidelity.
class Tiers {
  final int? physiological; // 1..=4 from `source.source_tier`
  final int? kinematic; // 1..=3 from `meta.synheart.tiers.kinematic`
  final int? digital; // 1..=3 from `meta.synheart.tiers.digital`

  const Tiers({this.physiological, this.kinematic, this.digital});

  bool get isEmpty =>
      physiological == null && kinematic == null && digital == null;
}

/// Map a single signal name to its modality per the contract doc.
String? _signalToModality(String signal) {
  switch (signal) {
    case 'hrv':
    case 'rr':
    case 'ecg':
    case 'ppg':
    case 'spo2':
    case 'resp':
    case 'eda':
    case 'gsr':
    case 'temp':
    case 'hr':
      return 'physiological';
    case 'accel':
    case 'gyro':
    case 'mag':
      return 'kinematic';
    case 'touch':
    case 'scroll':
    case 'app_switch':
    case 'typing':
    case 'notification':
    case 'clipboard':
      return 'digital';
    default:
      return null; // unknown / future signal — ignore
  }
}

Modalities _deriveModalities(Map<String, dynamic> payload) {
  bool physio = false;
  bool kin = false;
  bool dig = false;
  final sources = payload['meta'] is Map
      ? (payload['meta'] as Map)['provenance'] is Map
            ? ((payload['meta'] as Map)['provenance'] as Map)['sources']
            : null
      : null;
  if (sources is Map) {
    for (final entry in sources.values) {
      if (entry is! Map) continue;
      final signals = entry['signals'];
      if (signals is! List) continue;
      for (final sig in signals) {
        if (sig is! String) continue;
        switch (_signalToModality(sig)) {
          case 'physiological':
            physio = true;
            break;
          case 'kinematic':
            kin = true;
            break;
          case 'digital':
            dig = true;
            break;
        }
      }
    }
  }
  return Modalities(physiological: physio, kinematic: kin, digital: dig);
}

Tiers _deriveTiers(Map<String, dynamic> payload) {
  int? physio;
  int? kin;
  int? dig;

  // Physiological: walk sources, take worst-numbered (highest int) from any
  // source emitting a physiological signal.
  final sources = payload['meta'] is Map
      ? (payload['meta'] as Map)['provenance'] is Map
            ? ((payload['meta'] as Map)['provenance'] as Map)['sources']
            : null
      : null;
  if (sources is Map) {
    for (final entry in sources.values) {
      if (entry is! Map) continue;
      final signals = entry['signals'];
      if (signals is! List) continue;
      final isPhysio = signals.any(
        (s) => s is String && _signalToModality(s) == 'physiological',
      );
      if (!isPhysio) continue;
      final st = entry['source_tier'];
      if (st is num) {
        final v = st.toInt();
        physio = (physio == null) ? v : (physio > v ? physio : v);
      }
    }
  }

  // Kinematic / digital: residual shim under meta.synheart.tiers.
  final shim = payload['meta'] is Map
      ? (payload['meta'] as Map)['synheart'] is Map
            ? ((payload['meta'] as Map)['synheart'] as Map)['tiers']
            : null
      : null;
  if (shim is Map) {
    final k = shim['kinematic'];
    if (k is num) kin = k.toInt();
    final d = shim['digital'];
    if (d is num) dig = d.toInt();
  }

  return Tiers(physiological: physio, kinematic: kin, digital: dig);
}

/// Typed HSI state emitted by `Synheart.onStateUpdate` (RFC-CORE-0007 §3).
///
/// Provides typed axis accessors and retains `rawJson` for diagnostic use.
/// `modalities` and `tiers` are derived from `meta.provenance.sources[*]
/// .signals` and `meta.synheart.tiers` per the Synheart signal-modality
/// mapping contract.
class HSIState {
  final String subjectId;
  final int timestampMs;
  final HSIAxes hsi;
  final Modalities modalities;
  final Tiers tiers;
  final String rawJson;

  const HSIState({
    required this.subjectId,
    required this.timestampMs,
    required this.hsi,
    required this.rawJson,
    this.modalities = const Modalities(),
    this.tiers = const Tiers(),
  });

  /// Parse an HSI JSON string from the runtime into a typed [HSIState].
  factory HSIState.fromJson(String json, {String subjectId = ''}) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final timestampMs =
          (map['timestamp_ms'] as num?)?.toInt() ??
          (map['observed_at_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;

      final hsiMap = (map['hsi'] as Map<String, dynamic>?) ?? map;
      final sid = (map['subject_id'] as String?) ?? subjectId;

      return HSIState(
        subjectId: sid,
        timestampMs: timestampMs,
        hsi: HSIAxes.fromJson(hsiMap),
        modalities: _deriveModalities(map),
        tiers: _deriveTiers(map),
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
