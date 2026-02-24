import 'emotion.dart';
import 'focus.dart';
import 'behavior.dart';
import 'context.dart';
import 'hsi_axes.dart';
import 'physiology.dart';
import 'state_quality.dart';
import 'provenance.dart';

/// Human State Vector (HSV) - Internal runtime representation of human state.
///
/// Aligned with synheart-runtime. The HSV is the canonical internal
/// representation fusing physiology, behavior, and context modalities.
/// External consumers receive HSI JSON (via synheart-runtime), never HSV directly.
///
/// This is the shared "state bus" that all Synheart components consume:
/// - Core produces the base HSV with physiology + behavior + context
/// - Emotion Head (via synheart-emotion SDK) populates [emotion]
/// - Focus Head (via synheart-focus SDK) populates [focus]
/// - synheart-runtime exports HSV → HSI internally
class HumanStateVector {
  /// HSV schema version
  final String version;

  /// Timestamp in milliseconds since epoch
  final int timestamp;

  /// Physiology domain — wearable-derived physiological readings.
  /// Populated by biosignal pipeline (WHOOP, Garmin, etc.)
  final PhysiologyState physiology;

  /// Emotion state (populated by synheart-emotion SDK via Emotion Head)
  final EmotionState emotion;

  /// Focus state (populated by synheart-focus SDK via Focus Head)
  final FocusState focus;

  /// Behavioral metrics (from Behavior Module + Runtime processing)
  final BehaviorState behavior;

  /// Context information (from Context signals + Runtime processing)
  final ContextState context;

  /// Metadata (device, session, internal embeddings)
  final MetaState meta;

  /// Quality assessment of the fused state vector
  final StateQuality stateQuality;

  /// Data provenance and lineage information
  final ProvenanceInfo provenance;

  HumanStateVector({
    required this.version,
    required this.timestamp,
    required this.physiology,
    required this.emotion,
    required this.focus,
    required this.behavior,
    required this.context,
    required this.meta,
    this.stateQuality = StateQuality.empty,
    this.provenance = ProvenanceInfo.empty,
  });

  factory HumanStateVector.fromJson(Map<String, dynamic> json) {
    return HumanStateVector(
      version: json['version'] as String,
      timestamp: json['timestamp'] as int,
      physiology: json['physiology'] != null
          ? PhysiologyState.fromJson(json['physiology'] as Map<String, dynamic>)
          : PhysiologyState.empty,
      emotion: EmotionState.fromJson(json['emotion'] as Map<String, dynamic>),
      focus: FocusState.fromJson(json['focus'] as Map<String, dynamic>),
      behavior: BehaviorState.fromJson(json['behavior'] as Map<String, dynamic>),
      context: ContextState.fromJson(json['context'] as Map<String, dynamic>),
      meta: MetaState.fromJson(json['meta'] as Map<String, dynamic>),
      stateQuality: json['state_quality'] != null
          ? StateQuality.fromJson(json['state_quality'] as Map<String, dynamic>)
          : StateQuality.empty,
      provenance: json['provenance'] != null
          ? ProvenanceInfo.fromJson(json['provenance'] as Map<String, dynamic>)
          : ProvenanceInfo.empty,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'timestamp': timestamp,
    'physiology': physiology.toJson(),
    'emotion': emotion.toJson(),
    'focus': focus.toJson(),
    'behavior': behavior.toJson(),
    'context': context.toJson(),
    'meta': meta.toJson(),
    'state_quality': stateQuality.toJson(),
    'provenance': provenance.toJson(),
  };

  /// Create a base HSV with empty emotion/focus (before heads populate them)
  factory HumanStateVector.base({
    required int timestamp,
    required BehaviorState behavior,
    required ContextState context,
    required MetaState meta,
    PhysiologyState physiology = PhysiologyState.empty,
    StateQuality stateQuality = StateQuality.empty,
    ProvenanceInfo provenance = ProvenanceInfo.empty,
    String version = '1.0.0',
  }) {
    return HumanStateVector(
      version: version,
      timestamp: timestamp,
      physiology: physiology,
      emotion: EmotionState.empty(),
      focus: FocusState.empty(),
      behavior: behavior,
      context: context,
      meta: meta,
      stateQuality: stateQuality,
      provenance: provenance,
    );
  }

  /// Create a copy with updated emotion state
  HumanStateVector copyWithEmotion(EmotionState emotion) {
    return HumanStateVector(
      version: version,
      timestamp: timestamp,
      physiology: physiology,
      emotion: emotion,
      focus: focus,
      behavior: behavior,
      context: context,
      meta: meta,
      stateQuality: stateQuality,
      provenance: provenance,
    );
  }

  /// Create a copy with updated focus state
  HumanStateVector copyWithFocus(FocusState focus) {
    return HumanStateVector(
      version: version,
      timestamp: timestamp,
      physiology: physiology,
      emotion: emotion,
      focus: focus,
      behavior: behavior,
      context: context,
      meta: meta,
      stateQuality: stateQuality,
      provenance: provenance,
    );
  }

  /// Create a copy with updated physiology state
  HumanStateVector copyWithPhysiology(PhysiologyState physiology) {
    return HumanStateVector(
      version: version,
      timestamp: timestamp,
      physiology: physiology,
      emotion: emotion,
      focus: focus,
      behavior: behavior,
      context: context,
      meta: meta,
      stateQuality: stateQuality,
      provenance: provenance,
    );
  }
}

/// Metadata state containing device, session, and HSI state axes
class MetaState {
  /// Session identifier
  final String sessionId;

  /// Device information
  final DeviceInfo device;

  /// Sampling rate in Hz
  final double samplingRateHz;

  /// Internal HSI embedding (64D dense vector)
  final StateEmbedding embedding;

  /// HSI state axes - core state representation indices
  final HSIAxes axes;

  /// SRM baseline status (EMPTY, WARMING, READY) — null if SRM not active.
  final String? baselineStatus;

  /// SRM snapshot identifier — null if SRM not active.
  final String? srmSnapshotId;

  /// SRM schema version — null if SRM not active.
  final String? srmVersion;

  /// Total distinct calendar days across SRM strata.
  final int? baselineDays;

  /// Total accepted windows across SRM strata.
  final int? baselineSessions;

  MetaState({
    required this.sessionId,
    required this.device,
    required this.samplingRateHz,
    required this.embedding,
    required this.axes,
    this.baselineStatus,
    this.srmSnapshotId,
    this.srmVersion,
    this.baselineDays,
    this.baselineSessions,
  });

  factory MetaState.fromJson(Map<String, dynamic> json) {
    return MetaState(
      sessionId: json['sessionId'] as String,
      device: DeviceInfo.fromJson(json['device'] as Map<String, dynamic>),
      samplingRateHz: (json['samplingRateHz'] as num).toDouble(),
      embedding: StateEmbedding.fromJson(json['embedding'] as Map<String, dynamic>),
      axes: HSIAxes.fromJson(json['axes'] as Map<String, dynamic>),
      baselineStatus: json['baselineStatus'] as String?,
      srmSnapshotId: json['srmSnapshotId'] as String?,
      srmVersion: json['srmVersion'] as String?,
      baselineDays: (json['baselineDays'] as num?)?.toInt(),
      baselineSessions: (json['baselineSessions'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'device': device.toJson(),
    'samplingRateHz': samplingRateHz,
    'embedding': embedding.toJson(),
    'axes': axes.toJson(),
    if (baselineStatus != null) 'baselineStatus': baselineStatus,
    if (srmSnapshotId != null) 'srmSnapshotId': srmSnapshotId,
    if (srmVersion != null) 'srmVersion': srmVersion,
    if (baselineDays != null) 'baselineDays': baselineDays,
    if (baselineSessions != null) 'baselineSessions': baselineSessions,
  };
}

/// HSI Axes - All state representation axes
class HSIAxes {
  /// Affect axis (arousal, valence stability)
  final AffectAxis affect;

  /// Engagement axis (interaction patterns)
  final EngagementAxis engagement;

  /// Activity axis (motion, posture)
  final ActivityAxis activity;

  /// Context axis (screen time, fragmentation)
  final ContextAxis context;

  HSIAxes({
    required this.affect,
    required this.engagement,
    required this.activity,
    required this.context,
  });

  factory HSIAxes.fromJson(Map<String, dynamic> json) {
    return HSIAxes(
      affect: AffectAxis.fromJson(json['affect'] as Map<String, dynamic>),
      engagement: EngagementAxis.fromJson(json['engagement'] as Map<String, dynamic>),
      activity: ActivityAxis.fromJson(json['activity'] as Map<String, dynamic>),
      context: ContextAxis.fromJson(json['context'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'affect': affect.toJson(),
    'engagement': engagement.toJson(),
    'activity': activity.toJson(),
    'context': context.toJson(),
  };

  factory HSIAxes.empty() => HSIAxes(
    affect: AffectAxis.empty(),
    engagement: EngagementAxis.empty(),
    activity: ActivityAxis.empty(),
    context: ContextAxis.empty(),
  );
}

/// Device information
class DeviceInfo {
  /// Platform (e.g., 'ios', 'android')
  final String platform;

  /// Optional device model
  final String? model;

  /// Optional OS version
  final String? osVersion;

  DeviceInfo({required this.platform, this.model, this.osVersion});

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      platform: json['platform'] as String,
      model: json['model'] as String?,
      osVersion: json['osVersion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'platform': platform,
    if (model != null) 'model': model,
    if (osVersion != null) 'osVersion': osVersion,
  };
}
