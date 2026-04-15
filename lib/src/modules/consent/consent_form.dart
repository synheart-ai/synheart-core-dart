import '../interfaces/consent_provider.dart';

/// Editable consent form returned by synheart-core-runtime.
///
/// Mirrors the flat shape the runtime emits from
/// `synheart_core_consent_get_editable_form` (see
/// `synheart-core-runtime/src/consent/consent_form.rs`).
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
        other.allowVendorSync == allowVendorSync;
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
