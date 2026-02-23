/// Types of consent
enum ConsentType {
  /// Consent for biosignal collection
  biosignals,

  /// Consent for behavioral data collection
  behavior,

  /// Consent for phone context data collection
  phoneContext,

  /// Consent for cloud uploads
  cloudUpload,

  /// Consent for Syni personalization
  syni,

  /// Consent for focus estimation
  focusEstimation,

  /// Consent for emotion estimation
  emotionEstimation,
}

/// Snapshot of user consent at a point in time
class ConsentSnapshot {
  /// Consent for biosignal collection
  final bool biosignals;

  /// Consent for behavioral data collection
  final bool behavior;

  /// Consent for phone context data collection
  final bool phoneContext;

  /// Consent for cloud uploads
  final bool cloudUpload;

  /// Consent for Syni personalization
  final bool syni;

  /// Consent for focus estimation
  final bool focusEstimation;

  /// Consent for emotion estimation
  final bool emotionEstimation;

  /// Timestamp when this consent was given
  final DateTime timestamp;

  /// Schema version for this consent snapshot
  final String version;

  /// Whether user explicitly denied consent (vs never asked)
  /// This distinguishes "pending" (never asked) from "denied" (user declined)
  final bool explicitlyDenied;

  const ConsentSnapshot({
    required this.biosignals,
    required this.behavior,
    required this.phoneContext,
    required this.cloudUpload,
    required this.syni,
    this.focusEstimation = false,
    this.emotionEstimation = false,
    required this.timestamp,
    this.version = '1.0.0',
    this.explicitlyDenied = false,
  });

  /// Check if a specific consent type is allowed
  bool allows(ConsentType type) {
    switch (type) {
      case ConsentType.biosignals:
        return biosignals;
      case ConsentType.behavior:
        return behavior;
      case ConsentType.phoneContext:
        return phoneContext;
      case ConsentType.cloudUpload:
        return cloudUpload;
      case ConsentType.syni:
        return syni;
      case ConsentType.focusEstimation:
        return focusEstimation;
      case ConsentType.emotionEstimation:
        return emotionEstimation;
    }
  }

  /// Create a copy with updated values
  ConsentSnapshot copyWith({
    bool? biosignals,
    bool? behavior,
    bool? phoneContext,
    bool? cloudUpload,
    bool? syni,
    bool? focusEstimation,
    bool? emotionEstimation,
    DateTime? timestamp,
    String? version,
    bool? explicitlyDenied,
  }) {
    return ConsentSnapshot(
      biosignals: biosignals ?? this.biosignals,
      behavior: behavior ?? this.behavior,
      phoneContext: phoneContext ?? this.phoneContext,
      cloudUpload: cloudUpload ?? this.cloudUpload,
      syni: syni ?? this.syni,
      focusEstimation: focusEstimation ?? this.focusEstimation,
      emotionEstimation: emotionEstimation ?? this.emotionEstimation,
      timestamp: timestamp ?? this.timestamp,
      version: version ?? this.version,
      explicitlyDenied: explicitlyDenied ?? this.explicitlyDenied,
    );
  }

  /// Create a consent snapshot with all consents denied
  ///
  /// [explicitlyDenied] indicates if user explicitly declined (true)
  /// or if consent was never requested (false, default)
  factory ConsentSnapshot.none({bool explicitlyDenied = false}) {
    return ConsentSnapshot(
      biosignals: false,
      behavior: false,
      phoneContext: false,
      cloudUpload: false,
      syni: false,
      focusEstimation: false,
      emotionEstimation: false,
      timestamp: DateTime.now(),
      explicitlyDenied: explicitlyDenied,
    );
  }

  /// Create a consent snapshot with all consents granted
  factory ConsentSnapshot.all() {
    return ConsentSnapshot(
      biosignals: true,
      behavior: true,
      phoneContext: true,
      cloudUpload: true,
      syni: true,
      focusEstimation: true,
      emotionEstimation: true,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'biosignals': biosignals,
      'behavior': behavior,
      'phoneContext': phoneContext,
      'cloudUpload': cloudUpload,
      'syni': syni,
      'focusEstimation': focusEstimation,
      'emotionEstimation': emotionEstimation,
      'timestamp': timestamp.toIso8601String(),
      'version': version,
      'explicitlyDenied': explicitlyDenied,
    };
  }

  factory ConsentSnapshot.fromJson(Map<String, dynamic> json) {
    return ConsentSnapshot(
      biosignals: json['biosignals'] as bool,
      behavior: json['behavior'] as bool,
      phoneContext: json['phoneContext'] as bool,
      cloudUpload: json['cloudUpload'] as bool,
      syni: json['syni'] as bool,
      focusEstimation: json['focusEstimation'] as bool? ?? false,
      emotionEstimation: json['emotionEstimation'] as bool? ?? false,
      timestamp: DateTime.parse(json['timestamp'] as String),
      version: json['version'] as String? ?? '1.0.0',
      explicitlyDenied: json['explicitlyDenied'] as bool? ?? false,
    );
  }
}

/// Provider interface for consent management
abstract class ConsentProvider {
  /// Get the current consent snapshot
  ConsentSnapshot current();

  /// Observe consent changes
  Stream<ConsentSnapshot> observe();

  /// Update consent (internal use)
  Future<void> updateConsent(ConsentSnapshot newConsent);
}
