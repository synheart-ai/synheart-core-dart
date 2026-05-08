/// Typed view of the runtime's effective consent state.
///
/// Mirrors the JSON returned by
/// `synheart_core_consent_effective_state` / `synheart_core_current_consent`
/// (the native runtime's `consent_snapshot_summary_json` FFI export).
///
/// This is the **read-only** shape the SDK exposes to hosts for feature
/// gating and UI hydration. Use [`ConsentForm`] when constructing input to
/// `consentSubmitFormTyped`.
class ConsentEffectiveState {
  const ConsentEffectiveState({
    required this.biosignals,
    required this.phoneContext,
    required this.behavior,
    required this.cloudUpload,
    required this.syni,
    required this.vendorSync,
    required this.research,
    required this.timestampMs,
    required this.version,
  });

  /// Category-level: at least one biosignals channel is granted.
  final bool biosignals;

  /// Category-level: at least one phone-context channel is granted.
  final bool phoneContext;

  /// Category-level: at least one behavior channel is granted.
  final bool behavior;

  /// Cloud upload is permitted.
  final bool cloudUpload;

  /// Syni personalization is permitted.
  final bool syni;

  /// Vendor sync (Whoop/Garmin/etc.) is permitted.
  final bool vendorSync;

  /// Research export is permitted.
  final bool research;

  /// Last time the snapshot was updated (Unix ms, from runtime).
  final int timestampMs;

  /// Snapshot schema version as returned by runtime.
  final String version;

  /// Returns `true` if any coarse collection is granted. Useful for quick
  /// "has any consent at all" checks.
  bool get hasAnyGrant =>
      biosignals ||
      phoneContext ||
      behavior ||
      cloudUpload ||
      vendorSync ||
      research;

  factory ConsentEffectiveState.fromJson(Map<String, dynamic> json) {
    return ConsentEffectiveState(
      biosignals: json['biosignals'] == true,
      phoneContext: json['phone_context'] == true,
      behavior: json['behavior'] == true,
      cloudUpload: json['cloud_upload'] == true,
      syni: json['syni'] == true,
      vendorSync: json['vendor_sync'] == true,
      research: json['research'] == true,
      timestampMs: (json['timestamp_ms'] is int)
          ? json['timestamp_ms'] as int
          : 0,
      version: (json['version'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'biosignals': biosignals,
      'phone_context': phoneContext,
      'behavior': behavior,
      'cloud_upload': cloudUpload,
      'syni': syni,
      'vendor_sync': vendorSync,
      'research': research,
      'timestamp_ms': timestampMs,
      'version': version,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConsentEffectiveState &&
        other.biosignals == biosignals &&
        other.phoneContext == phoneContext &&
        other.behavior == behavior &&
        other.cloudUpload == cloudUpload &&
        other.syni == syni &&
        other.vendorSync == vendorSync &&
        other.research == research &&
        other.timestampMs == timestampMs &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(
    biosignals,
    phoneContext,
    behavior,
    cloudUpload,
    syni,
    vendorSync,
    research,
    timestampMs,
    version,
  );
}
