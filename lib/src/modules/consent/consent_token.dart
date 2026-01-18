import 'dart:convert';

/// JWT consent token issued by consent service
class ConsentToken {
  /// JWT token string
  final String token;

  /// Token expiration time
  final DateTime expiresAt;

  /// Consent profile ID that this token was issued for
  final String profileId;

  /// Token scopes (e.g., ["bio:vitals", "cloud:upload"])
  final List<String> scopes;

  /// Decoded JWT claims (for validation)
  final Map<String, dynamic> claims;

  ConsentToken({
    required this.token,
    required this.expiresAt,
    required this.profileId,
    required this.scopes,
    required this.claims,
  });

  /// Check if token is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Check if token is valid (not expired)
  bool get isValid => !isExpired;

  /// Check if token expires soon (within specified duration)
  bool expiresSoon([Duration threshold = const Duration(minutes: 5)]) {
    return expiresAt.difference(DateTime.now()) <= threshold;
  }

  /// Create from JSON response
  ///
  /// Supports multiple API response formats:
  /// 1. RFC format: { "token": "...", "expires_at": "2026-01-10T19:00:00Z", "profile_id": "...", "scopes": [...] }
  /// 2. Actual API format: { "access_token": "...", "expires_in": 86400, "consent_profile_id": "...", "token_type": "Bearer" }
  factory ConsentToken.fromJson(Map<String, dynamic> json) {
    // Safely extract token (required field)
    // API may return either "token" or "access_token"
    final token = json['token'] ?? json['access_token'];
    if (token == null) {
      throw FormatException(
        'Missing required field "token" or "access_token" in consent token response. Available keys: ${json.keys.join(", ")}',
      );
    }
    if (token is! String) {
      throw FormatException(
        'Field "token"/"access_token" must be a String, got ${token.runtimeType}',
      );
    }

    // Safely extract expiration time
    // API may return either "expires_at" (ISO string) or "expires_in" (seconds)
    DateTime expiresAt;
    if (json['expires_at'] != null) {
      // RFC format: ISO 8601 timestamp string
      final expiresAtStr = json['expires_at'];
      if (expiresAtStr is! String) {
        throw FormatException(
          'Field "expires_at" must be a String, got ${expiresAtStr.runtimeType}',
        );
      }
      expiresAt = DateTime.parse(expiresAtStr).toLocal();
    } else if (json['expires_in'] != null) {
      // Actual API format: seconds until expiration
      final expiresIn = json['expires_in'];
      if (expiresIn is! int) {
        throw FormatException(
          'Field "expires_in" must be an int (seconds), got ${expiresIn.runtimeType}',
        );
      }
      expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    } else {
      throw FormatException(
        'Missing required field "expires_at" or "expires_in" in consent token response. Available keys: ${json.keys.join(", ")}',
      );
    }

    // Decode JWT to extract claims (basic decoding, no signature verification)
    final parts = token.split('.');
    if (parts.length != 3) {
      throw FormatException('Invalid JWT format');
    }

    // Decode payload (second part)
    final payload = parts[1];
    // Add padding if needed
    final normalizedPayload = payload.padRight(
      (payload.length + 3) ~/ 4 * 4,
      '=',
    );
    final decodedBytes = base64Url.decode(normalizedPayload);
    final claims = jsonDecode(utf8.decode(decodedBytes)) as Map<String, dynamic>;

    // Extract profile ID - API may return either "profile_id" or "consent_profile_id"
    final profileId = json['profile_id'] as String? ??
        json['consent_profile_id'] as String? ??
        claims['profile_id'] as String? ??
        claims['consent_profile_id'] as String? ??
        '';

    // Extract scopes - may be in response or in JWT claims
    final scopes = (json['scopes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        (claims['scopes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return ConsentToken(
      token: token,
      expiresAt: expiresAt,
      profileId: profileId,
      scopes: scopes,
      claims: claims,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'expires_at': expiresAt.toIso8601String(),
      'profile_id': profileId,
      'scopes': scopes,
      'claims': claims,
    };
  }

  /// Create from stored JSON
  factory ConsentToken.fromStoredJson(Map<String, dynamic> json) {
    return ConsentToken(
      token: json['token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      profileId: json['profile_id'] as String,
      scopes: (json['scopes'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      claims: json['claims'] as Map<String, dynamic>,
    );
  }
}

/// Consent status enumeration
enum ConsentStatus {
  /// Consent granted with valid token
  granted,

  /// Consent pending (user hasn't responded)
  pending,

  /// Consent denied by user
  denied,

  /// Token expired
  expired,
}

