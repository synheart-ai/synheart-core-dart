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
  /// Secret key for generating mock signatures (matches 'mock_secret' in synheart.dart)
  static const String _mockSecret = 'mock_secret';

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

    // Generate proper HMAC signature for development
    final signature = _generateSignature(
      orgId: 'mock_org',
      projectId: 'mock_project',
      environment: 'development',
      capabilities: capabilities,
      issuedAt: now,
      expiresAt: expiresAt,
      secret: _mockSecret,
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

  /// Generate HMAC signature for capability token
  /// This matches the signature generation in CapabilityVerifier
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
    final message = '$orgId:$projectId:$environment:'
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
