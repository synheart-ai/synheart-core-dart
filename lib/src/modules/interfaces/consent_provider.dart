/// Types of consent
enum ConsentType {
  /// Consent for biosignal collection
  biosignals,

  /// Consent for behavioral data collection
  behavior,

  /// Consent for motion/context data collection
  motion,

  /// Consent for cloud uploads
  cloudUpload,

  /// Consent for Syni personalization
  syni,
}

/// Snapshot of user consent at a point in time
class ConsentSnapshot {
  /// Consent for biosignal collection
  final bool biosignals;

  /// Consent for behavioral data collection
  final bool behavior;

  /// Consent for motion/context data collection
  final bool motion;

  /// Consent for cloud uploads
  final bool cloudUpload;

  /// Consent for Syni personalization
  final bool syni;

  /// Timestamp when this consent was given
  final DateTime timestamp;

  /// Schema version for this consent snapshot
  final String version;

  const ConsentSnapshot({
    required this.biosignals,
    required this.behavior,
    required this.motion,
    required this.cloudUpload,
    required this.syni,
    required this.timestamp,
    this.version = '1.0.0',
  });

  /// Check if a specific consent type is allowed
  bool allows(ConsentType type) {
    switch (type) {
      case ConsentType.biosignals:
        return biosignals;
      case ConsentType.behavior:
        return behavior;
      case ConsentType.motion:
        return motion;
      case ConsentType.cloudUpload:
        return cloudUpload;
      case ConsentType.syni:
        return syni;
    }
  }

  /// Create a copy with updated values
  ConsentSnapshot copyWith({
    bool? biosignals,
    bool? behavior,
    bool? motion,
    bool? cloudUpload,
    bool? syni,
    DateTime? timestamp,
    String? version,
  }) {
    return ConsentSnapshot(
      biosignals: biosignals ?? this.biosignals,
      behavior: behavior ?? this.behavior,
      motion: motion ?? this.motion,
      cloudUpload: cloudUpload ?? this.cloudUpload,
      syni: syni ?? this.syni,
      timestamp: timestamp ?? this.timestamp,
      version: version ?? this.version,
    );
  }

  /// Create a consent snapshot with all consents denied
  factory ConsentSnapshot.none() {
    return ConsentSnapshot(
      biosignals: false,
      behavior: false,
      motion: false,
      cloudUpload: false,
      syni: false,
      timestamp: DateTime.now(),
    );
  }

  /// Create a consent snapshot with all consents granted
  factory ConsentSnapshot.all() {
    return ConsentSnapshot(
      biosignals: true,
      behavior: true,
      motion: true,
      cloudUpload: true,
      syni: true,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'biosignals': biosignals,
      'behavior': behavior,
      'motion': motion,
      'cloudUpload': cloudUpload,
      'syni': syni,
      'timestamp': timestamp.toIso8601String(),
      'version': version,
    };
  }

  factory ConsentSnapshot.fromJson(Map<String, dynamic> json) {
    return ConsentSnapshot(
      biosignals: json['biosignals'] as bool,
      behavior: json['behavior'] as bool,
      motion: json['motion'] as bool,
      cloudUpload: json['cloudUpload'] as bool,
      syni: json['syni'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      version: json['version'] as String? ?? '1.0.0',
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
