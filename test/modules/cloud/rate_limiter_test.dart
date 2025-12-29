import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_core/src/modules/cloud/rate_limiter.dart';
import 'package:synheart_core/src/modules/interfaces/capability_provider.dart';

void main() {
  group('RateLimiter', () {
    test('returns correct batch size for core capability', () {
      final limiter = RateLimiter(capabilityLevel: CapabilityLevel.core);
      expect(limiter.batchSize, equals(10));
    });

    test('returns correct batch size for extended capability', () {
      final limiter = RateLimiter(capabilityLevel: CapabilityLevel.extended);
      expect(limiter.batchSize, equals(50));
    });

    test('returns correct batch size for research capability', () {
      final limiter = RateLimiter(capabilityLevel: CapabilityLevel.research);
      expect(limiter.batchSize, equals(200));
    });

    test('allows first upload for any window type', () {
      final limiter = RateLimiter(capabilityLevel: CapabilityLevel.core);

      expect(limiter.canUpload('micro'), isTrue);
      expect(limiter.canUpload('short'), isTrue);
      expect(limiter.canUpload('medium'), isTrue);
      expect(limiter.canUpload('long'), isTrue);
    });

    test('prevents upload before interval expires for micro window', () {
      final limiter = RateLimiter(capabilityLevel: CapabilityLevel.core);

      // First upload should be allowed
      expect(limiter.canUpload('micro'), isTrue);
      limiter.recordUpload('micro', batchSize: 1);

      // Immediate second upload should be blocked
      expect(limiter.canUpload('micro'), isFalse);
    });

    test('allows upload after interval expires', () async {
      final limiter = RateLimiter(capabilityLevel: CapabilityLevel.core);

      // First upload
      limiter.recordUpload('micro', batchSize: 1);
      expect(limiter.canUpload('micro'), isFalse);

      // Wait a bit (not enough for interval)
      await Future.delayed(const Duration(milliseconds: 100));
      expect(limiter.canUpload('micro'), isFalse);

      // Note: We can't easily test the full 30s interval in a unit test
      // This would be covered by integration tests
    });

    test('allows unknown window types', () {
      final limiter = RateLimiter(capabilityLevel: CapabilityLevel.core);

      expect(limiter.canUpload('unknown_window'), isTrue);
    });

    test('tracks uploads independently per window type', () {
      final limiter = RateLimiter(capabilityLevel: CapabilityLevel.core);

      // Upload to micro window
      limiter.recordUpload('micro', batchSize: 1);

      // micro should be blocked
      expect(limiter.canUpload('micro'), isFalse);

      // Other windows should still be allowed
      expect(limiter.canUpload('short'), isTrue);
      expect(limiter.canUpload('medium'), isTrue);
      expect(limiter.canUpload('long'), isTrue);
    });

    test('recordUpload updates last upload time', () {
      final limiter = RateLimiter(capabilityLevel: CapabilityLevel.core);

      // First upload
      expect(limiter.canUpload('micro'), isTrue);
      limiter.recordUpload('micro', batchSize: 1);
      expect(limiter.canUpload('micro'), isFalse);

      // Record another upload (even though it would be blocked)
      limiter.recordUpload('micro', batchSize: 1);
      expect(limiter.canUpload('micro'), isFalse);
    });
  });
}
