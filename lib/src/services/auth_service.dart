import '../modules/capabilities/capability_token.dart';

/// Authentication service for obtaining capability tokens
abstract class AuthService {
  /// Authenticate with app key and user ID
  Future<CapabilityToken> authenticate({
    required String appKey,
    required String userId,
  });
}

/// Mock authentication service for development
class MockAuthService implements AuthService {
  @override
  Future<CapabilityToken> authenticate({
    required String appKey,
    required String userId,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Return mock token with core capabilities
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(days: 30));

    return CapabilityToken(
      orgId: 'mock_org',
      projectId: 'mock_project',
      environment: 'development',
      capabilities: {
        'behavior': 'core',
        'wear': 'core',
        'phone': 'core',
        'hsi': 'core',
        'cloud': 'core',
      },
      signature: 'mock_signature', // In real implementation, this would be HMAC
      expiresAt: expiresAt,
      issuedAt: now,
    );
  }
}

/// Production authentication service (to be implemented)
class ProductionAuthService implements AuthService {
  final String baseUrl;

  ProductionAuthService({required this.baseUrl});

  @override
  Future<CapabilityToken> authenticate({
    required String appKey,
    required String userId,
  }) async {
    // TODO: Implement actual API call to authentication service
    // This would make an HTTP request to the Synheart backend
    throw UnimplementedError('Production auth not yet implemented');
  }
}
