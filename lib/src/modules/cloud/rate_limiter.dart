import '../interfaces/capability_provider.dart';

class RateLimiter {
  final CapabilityLevel capabilityLevel;
  final Map<String, DateTime> _lastUpload = {};

  // Upload frequency per window type (from CLOUD_PROTOCOL.md)
  static const Map<String, Duration> _uploadIntervals = {
    'micro': Duration(seconds: 30),
    'short': Duration(minutes: 2),
    'medium': Duration(minutes: 10),
    'long': Duration(hours: 1),
  };

  RateLimiter({required this.capabilityLevel});

  /// Get batch size based on capability level
  int get batchSize {
    switch (capabilityLevel) {
      case CapabilityLevel.core:
        return 10;
      case CapabilityLevel.extended:
        return 50;
      case CapabilityLevel.research:
        return 200;
      default:
        return 10;
    }
  }

  /// Check if upload is allowed for this window type
  bool canUpload(String windowType) {
    final interval = _uploadIntervals[windowType];
    if (interval == null) return true; // Unknown window type - allow

    final lastUpload = _lastUpload[windowType];
    if (lastUpload == null) return true; // Never uploaded before

    final now = DateTime.now();
    final elapsed = now.difference(lastUpload);

    return elapsed >= interval;
  }

  /// Record an upload for rate limiting
  void recordUpload(String windowType, {required int batchSize}) {
    _lastUpload[windowType] = DateTime.now();
  }
}
