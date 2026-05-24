import '../interfaces/consent_provider.dart';
import 'consent_effective_state.dart';
import 'consent_form.dart';

/// Canonical metadata for [ConsentType]. Use this to iterate the SDK's
/// complete set of consent channels instead of hardcoding strings or
/// per-field switches — adding a new channel then only requires extending
/// the [ConsentType] enum and the four methods below (plus the underlying
/// state/form fields), not every consumer of consent state.
extension ConsentTypeMeta on ConsentType {
  /// String identifier used by `Synheart.hasConsent` / `grantConsentType`
  /// / `revokeConsentType`, and the camelCase form of consent keys hosts
  /// pass into the SDK.
  String get wireKey {
    switch (this) {
      case ConsentType.biosignals:
        return 'biosignals';
      case ConsentType.behavior:
        return 'behavior';
      case ConsentType.phoneContext:
        return 'phoneContext';
      case ConsentType.cloudUpload:
        return 'cloudUpload';
      case ConsentType.syni:
        return 'syni';
      case ConsentType.vendorSync:
        return 'vendorSync';
      case ConsentType.research:
        return 'research';
    }
  }

  /// Default human-readable label. Hosts typically override per-app; this
  /// is the safe fallback so a freshly-added channel has *some* label.
  String get displayName {
    switch (this) {
      case ConsentType.biosignals:
        return 'Wearable sensors';
      case ConsentType.behavior:
        return 'Behavior';
      case ConsentType.phoneContext:
        return 'Motion & phone context';
      case ConsentType.cloudUpload:
        return 'Cloud upload';
      case ConsentType.syni:
        return 'Syni AI Coach';
      case ConsentType.vendorSync:
        return 'Integrations';
      case ConsentType.research:
        return 'Research participation';
    }
  }

  /// Read the typed bool for this channel from a [ConsentEffectiveState].
  bool valueOn(ConsentEffectiveState s) {
    switch (this) {
      case ConsentType.biosignals:
        return s.biosignals;
      case ConsentType.behavior:
        return s.behavior;
      case ConsentType.phoneContext:
        return s.phoneContext;
      case ConsentType.cloudUpload:
        return s.cloudUpload;
      case ConsentType.syni:
        return s.syni;
      case ConsentType.vendorSync:
        return s.vendorSync;
      case ConsentType.research:
        return s.research;
    }
  }

  /// Read the typed bool for this channel from a [ConsentForm].
  /// `cloudUpload` / `vendorSync` / `research` map to the form's
  /// historical `allowCloud` / `allowVendorSync` / `allowResearch`
  /// fields; the asymmetric naming is preserved on the form for
  /// backward compatibility.
  bool valueOnForm(ConsentForm f) {
    switch (this) {
      case ConsentType.biosignals:
        return f.biosignals;
      case ConsentType.behavior:
        return f.behavior;
      case ConsentType.phoneContext:
        return f.phoneContext;
      case ConsentType.cloudUpload:
        return f.allowCloud;
      case ConsentType.syni:
        return f.syni;
      case ConsentType.vendorSync:
        return f.allowVendorSync;
      case ConsentType.research:
        return f.allowResearch;
    }
  }
}

/// Snapshot every channel of a [ConsentEffectiveState] into a [Map] —
/// the canonical iteration shape across SDK consumers.
extension ConsentEffectiveStateMap on ConsentEffectiveState {
  Map<ConsentType, bool> toChannelMap() => {
    for (final c in ConsentType.values) c: c.valueOn(this),
  };
}

/// Snapshot a [ConsentForm] into a channel map.
extension ConsentFormMap on ConsentForm {
  Map<ConsentType, bool> toChannelMap() => {
    for (final c in ConsentType.values) c: c.valueOnForm(this),
  };
}
