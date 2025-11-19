import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'capability_token.dart';

/// Verifies capability tokens
class CapabilityVerifier {
  /// Verify the HMAC signature of a capability token
  bool verifySignature(CapabilityToken token, String secret) {
    final message = _buildSignatureMessage(token);
    final key = utf8.encode(secret);
    final bytes = utf8.encode(message);

    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    final expectedSignature = base64.encode(digest.bytes);

    return expectedSignature == token.signature;
  }

  /// Check if token is expired
  bool isExpired(CapabilityToken token) {
    return token.isExpired;
  }

  /// Verify token validity (signature + expiration)
  bool isValid(CapabilityToken token, String secret) {
    return !isExpired(token) && verifySignature(token, secret);
  }

  /// Parse capabilities from token
  SDKCapabilities parse(CapabilityToken token) {
    if (isExpired(token)) {
      throw CapabilityException('Capability token is expired');
    }

    return SDKCapabilities.fromToken(token);
  }

  /// Build the message for HMAC signature
  String _buildSignatureMessage(CapabilityToken token) {
    // Message format: orgId:projectId:environment:capabilities:issuedAt:expiresAt
    final capabilitiesStr = json.encode(token.capabilities);
    return '${token.orgId}:${token.projectId}:${token.environment}:'
        '$capabilitiesStr:${token.issuedAt.millisecondsSinceEpoch}:'
        '${token.expiresAt.millisecondsSinceEpoch}';
  }
}

/// Exception thrown when capability verification fails
class CapabilityException implements Exception {
  final String message;
  final String? code;

  CapabilityException(this.message, {this.code});

  @override
  String toString() => 'CapabilityException: $message';
}
