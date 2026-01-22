/// Consent profile from consent service
class ConsentProfile {
  /// Profile ID
  final String id;

  /// Profile name
  final String name;

  /// Profile description
  final String description;

  /// Consent channels configuration
  final ConsentChannels channels;

  /// Whether cloud upload is enabled
  final bool cloudEnabled;

  /// Whether vendor sync is enabled
  final bool vendorSyncEnabled;

  /// Whether this is the default profile
  final bool isDefault;

  ConsentProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.channels,
    required this.cloudEnabled,
    required this.vendorSyncEnabled,
    required this.isDefault,
  });

  /// Create from JSON
  factory ConsentProfile.fromJson(Map<String, dynamic> json) {
    return ConsentProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      channels: ConsentChannels.fromJson(
        json['channels'] as Map<String, dynamic>,
      ),
      cloudEnabled:
          json['cloud'] as bool? ?? json['cloudEnabled'] as bool? ?? false,
      vendorSyncEnabled: json['vendorSyncEnabled'] as bool? ?? false,
      isDefault:
          json['is_default'] as bool? ?? json['isDefault'] as bool? ?? false,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'channels': channels.toJson(),
      'cloud': cloudEnabled,
      'vendorSyncEnabled': vendorSyncEnabled,
      'is_default': isDefault,
    };
  }
}

/// Consent channels configuration
class ConsentChannels {
  /// Biosignals consent configuration
  final BiosignalsConsent biosignals;

  /// Phone context consent configuration
  final PhoneContextConsent phoneContext;

  /// Behavior consent configuration
  final BehaviorConsent behavior;

  /// Interpretation consent configuration
  final InterpretationConsent interpretation;

  ConsentChannels({
    required this.biosignals,
    required this.phoneContext,
    required this.behavior,
    required this.interpretation,
  });

  /// Create from JSON
  factory ConsentChannels.fromJson(Map<String, dynamic> json) {
    return ConsentChannels(
      biosignals: BiosignalsConsent.fromJson(
        json['biosignals'] as Map<String, dynamic>? ?? {},
      ),
      phoneContext: PhoneContextConsent.fromJson(
        json['phoneContext'] as Map<String, dynamic>? ?? {},
      ),
      behavior: BehaviorConsent.fromJson(
        json['behavior'] as Map<String, dynamic>? ?? {},
      ),
      interpretation: InterpretationConsent.fromJson(
        json['interpretation'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'biosignals': biosignals.toJson(),
      'phoneContext': phoneContext.toJson(),
      'behavior': behavior.toJson(),
      'interpretation': interpretation.toJson(),
    };
  }
}

/// Biosignals consent configuration
class BiosignalsConsent {
  /// Consent for vitals (HR, HRV)
  final bool vitals;

  /// Consent for sleep data
  final bool sleep;

  BiosignalsConsent({required this.vitals, required this.sleep});

  factory BiosignalsConsent.fromJson(Map<String, dynamic> json) {
    return BiosignalsConsent(
      vitals: json['vitals'] as bool? ?? false,
      sleep: json['sleep'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'vitals': vitals, 'sleep': sleep};
  }
}

/// Phone context consent configuration
class PhoneContextConsent {
  /// Consent for motion data
  final bool motion;

  /// Consent for screen state
  final bool screenState;

  PhoneContextConsent({required this.motion, required this.screenState});

  factory PhoneContextConsent.fromJson(Map<String, dynamic> json) {
    return PhoneContextConsent(
      motion: json['motion'] as bool? ?? false,
      screenState: json['screenState'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'motion': motion, 'screenState': screenState};
  }
}

/// Behavior consent configuration
class BehaviorConsent {
  /// Consent for behavior tracking
  final bool enabled;

  BehaviorConsent({required this.enabled});

  factory BehaviorConsent.fromJson(Map<String, dynamic> json) {
    return BehaviorConsent(enabled: json['enabled'] as bool? ?? false);
  }

  Map<String, dynamic> toJson() {
    return {'enabled': enabled};
  }
}

/// Interpretation consent configuration
class InterpretationConsent {
  /// Consent for focus estimation
  final bool focusEstimation;

  /// Consent for emotion estimation
  final bool emotionEstimation;

  InterpretationConsent({
    required this.focusEstimation,
    required this.emotionEstimation,
  });

  factory InterpretationConsent.fromJson(Map<String, dynamic> json) {
    return InterpretationConsent(
      focusEstimation: json['focus_estimation'] as bool? ?? false,
      emotionEstimation: json['emotion_estimation'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'focus_estimation': focusEstimation,
      'emotion_estimation': emotionEstimation,
    };
  }
}
