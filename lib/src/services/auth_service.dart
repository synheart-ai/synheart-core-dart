import 'dart:convert';
import 'package:crypto/crypto.dart';
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
  /// Secret key used for signing mock tokens (must match the secret used in verification)
  static const String mockSecret = 'mock_secret';

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

    final capabilities = {
      'behavior': 'core',
      'wear': 'core',
      'phone': 'core',
      'hsi': 'core',
      'cloud': 'core',
    };

    // Generate proper HMAC signature using the same algorithm as CapabilityVerifier
    final signature = _generateSignature(
      orgId: 'mock_org',
      projectId: 'mock_project',
      environment: 'development',
      capabilities: capabilities,
      issuedAt: now,
      expiresAt: expiresAt,
      secret: mockSecret,
    );

    return CapabilityToken(
      orgId: 'mock_org',
      projectId: 'mock_project',
      environment: 'development',
      capabilities: capabilities,
      signature: signature,
      expiresAt: expiresAt,
      issuedAt: now,
    );
  }

  /// Generate HMAC-SHA256 signature for a capability token
  /// Uses the same format as CapabilityVerifier._buildSignatureMessage
  String _generateSignature({
    required String orgId,
    required String projectId,
    required String environment,
    required Map<String, String> capabilities,
    required DateTime issuedAt,
    required DateTime expiresAt,
    required String secret,
  }) {
    // Message format: orgId:projectId:environment:capabilities:issuedAt:expiresAt
    final capabilitiesStr = json.encode(capabilities);
    final message =
        '$orgId:$projectId:$environment:'
        '$capabilitiesStr:${issuedAt.millisecondsSinceEpoch}:'
        '${expiresAt.millisecondsSinceEpoch}';

    final key = utf8.encode(secret);
    final bytes = utf8.encode(message);

    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return base64.encode(digest.bytes);
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
