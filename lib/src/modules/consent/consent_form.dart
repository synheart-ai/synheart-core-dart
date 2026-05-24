import '../interfaces/consent_provider.dart';

/// Editable consent form returned by the native runtime.
///
/// Mirrors the flat shape the runtime emits from
/// `synheart_core_consent_get_editable_form`.
///
/// The runtime intentionally surfaces consent at the **category level**
/// (`biosignals`, `phone_context`, `behavior`) rather than exposing per-channel
/// toggles to hosts. Channel-level truth is stored inside the runtime and
/// intersected against the cloud default profile on submit.
class ConsentForm {
  const ConsentForm({
    required this.profileId,
    required this.biosignals,
    required this.phoneContext,
    required this.behavior,
    required this.consentTier,
    required this.allowCloud,
    required this.allowResearch,
    required this.allowVendorSync,
    this.syni = false,
  });

  /// Profile id the runtime resolved this form against. `"offline-default"`
  /// when no cloud profile has been cached yet.
  final String profileId;

  /// Category-level toggle: at least one biosignals channel granted.
  final bool biosignals;

  /// Category-level toggle: at least one phone-context channel granted.
  final bool phoneContext;

  /// Category-level toggle: at least one behavior channel granted.
  final bool behavior;

  /// Processing tier (`local`, `cloud`, `research`).
  final ConsentTier consentTier;

  /// Top-level switch: cloud processing permitted.
  final bool allowCloud;

  /// Top-level switch: research export permitted.
  final bool allowResearch;

  /// Top-level switch: vendor sync (Whoop/Garmin/etc.) permitted.
  final bool allowVendorSync;

  /// Feature toggle: on-device + cloud Syni (LLM coach) permitted.
  ///
  /// The runtime tracks this independently of biosignals / cloud upload
  /// (consumers should still gate cloud-Syni on [allowCloud] for the
  /// same reason RAMEN does — see the SDK README).
  final bool syni;

  /// Build a [ConsentForm] from a channel map — the symmetric inverse of
  /// `ConsentForm.toChannelMap()` (defined in `consent_type_meta.dart`).
  ///
  /// Convenience for hosts that already track consent state as a
  /// `Map<ConsentType, bool>` (the recommended shape for iterating
  /// channels generically). Avoids spelling out every named field at the
  /// call site, and adding a new channel doesn't require updating every
  /// `ConsentForm(...)` invocation.
  factory ConsentForm.fromChannelMap({
    required String profileId,
    required ConsentTier consentTier,
    required Map<ConsentType, bool> channels,
  }) {
    bool get(ConsentType t) => channels[t] ?? false;
    return ConsentForm(
      profileId: profileId,
      biosignals: get(ConsentType.biosignals),
      phoneContext: get(ConsentType.phoneContext),
      behavior: get(ConsentType.behavior),
      consentTier: consentTier,
      allowCloud: get(ConsentType.cloudUpload),
      allowResearch: get(ConsentType.research),
      allowVendorSync: get(ConsentType.vendorSync),
      syni: get(ConsentType.syni),
    );
  }

  factory ConsentForm.fromJson(Map<String, dynamic> json) {
    return ConsentForm(
      profileId: (json['profile_id'] ?? '').toString(),
      biosignals: json['biosignals'] == true,
      phoneContext: json['phone_context'] == true,
      behavior: json['behavior'] == true,
      consentTier: parseConsentTier(json['consent_tier']?.toString()),
      allowCloud: json['allow_cloud'] == true,
      allowResearch: json['allow_research'] == true,
      allowVendorSync: json['allow_vendor_sync'] == true,
      syni: json['syni'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profile_id': profileId,
      'biosignals': biosignals,
      'phone_context': phoneContext,
      'behavior': behavior,
      'consent_tier': consentTier.name,
      'allow_cloud': allowCloud,
      'allow_research': allowResearch,
      'allow_vendor_sync': allowVendorSync,
      'syni': syni,
    };
  }

  ConsentForm copyWith({
    String? profileId,
    bool? biosignals,
    bool? phoneContext,
    bool? behavior,
    ConsentTier? consentTier,
    bool? allowCloud,
    bool? allowResearch,
    bool? allowVendorSync,
    bool? syni,
  }) {
    return ConsentForm(
      profileId: profileId ?? this.profileId,
      biosignals: biosignals ?? this.biosignals,
      phoneContext: phoneContext ?? this.phoneContext,
      behavior: behavior ?? this.behavior,
      consentTier: consentTier ?? this.consentTier,
      allowCloud: allowCloud ?? this.allowCloud,
      allowResearch: allowResearch ?? this.allowResearch,
      allowVendorSync: allowVendorSync ?? this.allowVendorSync,
      syni: syni ?? this.syni,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConsentForm &&
        other.profileId == profileId &&
        other.biosignals == biosignals &&
        other.phoneContext == phoneContext &&
        other.behavior == behavior &&
        other.consentTier == consentTier &&
        other.allowCloud == allowCloud &&
        other.allowResearch == allowResearch &&
        other.allowVendorSync == allowVendorSync &&
        other.syni == syni;
  }

  @override
  int get hashCode => Object.hash(
    profileId,
    biosignals,
    phoneContext,
    behavior,
    consentTier,
    allowCloud,
    allowResearch,
    allowVendorSync,
    syni,
  );
}

ConsentTier parseConsentTier(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'cloud':
      return ConsentTier.cloud;
    case 'research':
      return ConsentTier.research;
    case 'local':
    default:
      return ConsentTier.local;
  }
}
