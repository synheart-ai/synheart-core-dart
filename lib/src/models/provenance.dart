/// Data provenance tracking aligned with synheart-engine HSV.
///
/// Mirrors `ProvenanceInfo` from synheart-engine — records the origin and lineage of data
/// that contributed to the Human State Vector.

/// Provenance metadata describing where HSV data originated.
///
/// Used during HSI export to populate `sources` and `meta`
/// fields, and by downstream analytics for data lineage tracking.
class ProvenanceInfo {
  /// Unique identifiers of data sources that contributed.
  final List<String> sourceIds;

  /// Vendor names that contributed data (e.g., "whoop", "garmin").
  final List<String> vendors;

  /// Device identifier.
  final String deviceId;

  /// IANA timezone of the observation.
  final String timezone;

  /// Number of distinct calendar days in the SRM baseline.
  final int baselineDays;

  /// Number of accepted SRM windows (baseline sessions).
  final int baselineSessions;

  /// SRM baseline status: EMPTY, WARMING, or READY.
  final String? baselineStatus;

  /// SRM snapshot identifier for traceability.
  final String? srmSnapshotId;

  /// Inference mode: deterministic, probabilistic, or composite.
  final String? inferenceMode;

  const ProvenanceInfo({
    this.sourceIds = const [],
    this.vendors = const [],
    this.deviceId = '',
    this.timezone = 'UTC',
    this.baselineDays = 0,
    this.baselineSessions = 0,
    this.baselineStatus,
    this.srmSnapshotId,
    this.inferenceMode,
  });

  factory ProvenanceInfo.fromJson(Map<String, dynamic> json) {
    return ProvenanceInfo(
      sourceIds: (json['source_ids'] as List<dynamic>?)?.cast<String>() ?? [],
      vendors: (json['vendors'] as List<dynamic>?)?.cast<String>() ?? [],
      deviceId: json['device_id'] as String? ?? '',
      timezone: json['timezone'] as String? ?? 'UTC',
      baselineDays: (json['baseline_days'] as num?)?.toInt() ?? 0,
      baselineSessions: (json['baseline_sessions'] as num?)?.toInt() ?? 0,
      baselineStatus: json['baseline_status'] as String?,
      srmSnapshotId: json['srm_snapshot_id'] as String?,
      inferenceMode: json['inference_mode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'source_ids': sourceIds,
    'vendors': vendors,
    'device_id': deviceId,
    'timezone': timezone,
    'baseline_days': baselineDays,
    'baseline_sessions': baselineSessions,
    if (baselineStatus != null) 'baseline_status': baselineStatus,
    if (srmSnapshotId != null) 'srm_snapshot_id': srmSnapshotId,
    if (inferenceMode != null) 'inference_mode': inferenceMode,
  };

  /// Empty provenance with no source information.
  static const ProvenanceInfo empty = ProvenanceInfo();
}
