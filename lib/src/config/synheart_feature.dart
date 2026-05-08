/// Feature identifiers for the four-authority activation model.
///
/// A feature is **operational** when all four conditions hold:
/// ```
/// FeatureOperational = Activation AND Consent AND Capability AND SessionActive
/// ```
enum SynheartFeature {
  /// Biosignal collection (HR, HRV) via wearable
  wear('biosignals'),

  /// User interaction tracking (taps, keystrokes, gestures)
  behavior('behavior'),

  /// Device motion, screen state, and app context
  phoneContext('phoneContext'),

  /// Cloud upload connector
  cloud('cloudUpload'),

  /// Syni hooks integration
  syni('syni');

  const SynheartFeature(this.requiredConsent);

  /// The consent type required for this feature to operate.
  final String requiredConsent;
}
