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
      vendorSyncEnabled:
          json['vendor_sync'] as bool? ?? json['vendorSyncEnabled'] as bool? ?? false,
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
      'vendor_sync': vendorSyncEnabled,
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
        json['phone_context'] as Map<String, dynamic>? ??
            json['phoneContext'] as Map<String, dynamic>? ??
            {},
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

  /// Consent for advanced cardiac metrics
  final bool cardioAdvanced;

  /// Consent for neuromuscular signals
  final bool neuromuscular;

  /// Consent for wearable motion data
  final bool wearableMotion;

  BiosignalsConsent({
    required this.vitals,
    required this.sleep,
    this.cardioAdvanced = false,
    this.neuromuscular = false,
    this.wearableMotion = false,
  });

  factory BiosignalsConsent.fromJson(Map<String, dynamic> json) {
    return BiosignalsConsent(
      vitals: json['vitals'] as bool? ?? false,
      sleep: json['sleep'] as bool? ?? false,
      cardioAdvanced: json['cardio_advanced'] as bool? ?? false,
      neuromuscular: json['neuromuscular'] as bool? ?? false,
      wearableMotion: json['wearable_motion'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vitals': vitals,
      'sleep': sleep,
      'cardio_advanced': cardioAdvanced,
      'neuromuscular': neuromuscular,
      'wearable_motion': wearableMotion,
    };
  }
}

/// Phone context consent configuration
class PhoneContextConsent {
  /// Consent for device motion data
  final bool deviceMotion;

  /// Consent for device context
  final bool deviceContext;

  /// Consent for system state
  final bool systemState;

  /// Deprecated: use [deviceMotion] instead.
  @Deprecated('Use deviceMotion instead')
  bool get motion => deviceMotion;

  /// Deprecated: use [systemState] instead.
  @Deprecated('Use systemState instead')
  bool get screenState => systemState;

  PhoneContextConsent({
    this.deviceMotion = false,
    this.deviceContext = false,
    this.systemState = false,
  });

  factory PhoneContextConsent.fromJson(Map<String, dynamic> json) {
    return PhoneContextConsent(
      deviceMotion: json['device_motion'] as bool? ??
          json['motion'] as bool? ??
          false,
      deviceContext: json['device_context'] as bool? ?? false,
      systemState: json['system_state'] as bool? ??
          json['screenState'] as bool? ??
          json['screen_state'] as bool? ??
          false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device_motion': deviceMotion,
      'device_context': deviceContext,
      'system_state': systemState,
    };
  }
}

/// Behavior consent configuration
class BehaviorConsent {
  /// Consent for digital activity tracking
  final bool digitalActivity;

  /// Consent for notification pattern analysis
  final bool notificationPatterns;

  /// Consent for app context collection
  final bool appContext;

  /// Whether any behavior consent is active.
  bool get enabled => digitalActivity || notificationPatterns || appContext;

  BehaviorConsent({
    this.digitalActivity = false,
    this.notificationPatterns = false,
    this.appContext = false,
  });

  factory BehaviorConsent.fromJson(Map<String, dynamic> json) {
    // Backward compat: if old 'enabled' key exists and new keys don't,
    // map enabled → digitalActivity.
    final hasNewKeys = json.containsKey('digital_activity') ||
        json.containsKey('notification_patterns') ||
        json.containsKey('app_context');
    final legacyEnabled =
        !hasNewKeys ? (json['enabled'] as bool? ?? false) : false;

    return BehaviorConsent(
      digitalActivity:
          json['digital_activity'] as bool? ?? legacyEnabled,
      notificationPatterns:
          json['notification_patterns'] as bool? ?? false,
      appContext: json['app_context'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'digital_activity': digitalActivity,
      'notification_patterns': notificationPatterns,
      'app_context': appContext,
    };
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
