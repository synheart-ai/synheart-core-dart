import '../interfaces/capability_provider.dart';

/// Capability token received from authentication service
class CapabilityToken {
  /// Organization ID
  final String orgId;

  /// Project ID
  final String projectId;

  /// Environment (dev, staging, production)
  final String environment;

  /// Capability levels per module
  final Map<String, String> capabilities;

  /// HMAC signature for verification
  final String signature;

  /// Token expiration timestamp
  final DateTime expiresAt;

  /// Token issue timestamp
  final DateTime issuedAt;

  const CapabilityToken({
    required this.orgId,
    required this.projectId,
    required this.environment,
    required this.capabilities,
    required this.signature,
    required this.expiresAt,
    required this.issuedAt,
  });

  /// Check if token is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Check if token is valid (not expired and issued in past)
  bool get isValid =>
      !isExpired &&
      DateTime.now().isAfter(issuedAt) &&
      expiresAt.isAfter(issuedAt);

  Map<String, dynamic> toJson() {
    return {
      'org_id': orgId,
      'project_id': projectId,
      'environment': environment,
      'capabilities': capabilities,
      'signature': signature,
      'expires_at': expiresAt.toIso8601String(),
      'issued_at': issuedAt.toIso8601String(),
    };
  }

  factory CapabilityToken.fromJson(Map<String, dynamic> json) {
    return CapabilityToken(
      orgId: json['org_id'] as String,
      projectId: json['project_id'] as String,
      environment: json['environment'] as String,
      capabilities: Map<String, String>.from(json['capabilities'] as Map),
      signature: json['signature'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      issuedAt: DateTime.parse(json['issued_at'] as String),
    );
  }
}

/// SDK capabilities parsed from token
class SDKCapabilities {
  /// Behavior module capability level
  final CapabilityLevel behavior;

  /// Wear module capability level
  final CapabilityLevel wear;

  /// Phone module capability level
  final CapabilityLevel phone;

  /// HSI module capability level
  final CapabilityLevel hsi;

  /// Cloud module capability level
  final CapabilityLevel cloud;

  const SDKCapabilities({
    required this.behavior,
    required this.wear,
    required this.phone,
    required this.hsi,
    required this.cloud,
  });

  /// Get capability level for a module
  CapabilityLevel getLevel(Module module) {
    switch (module) {
      case Module.behavior:
        return behavior;
      case Module.wear:
        return wear;
      case Module.phone:
        return phone;
      case Module.hsi:
        return hsi;
      case Module.cloud:
        return cloud;
    }
  }

  /// Create capabilities from token
  factory SDKCapabilities.fromToken(CapabilityToken token) {
    return SDKCapabilities(
      behavior: _parseLevel(token.capabilities['behavior']),
      wear: _parseLevel(token.capabilities['wear']),
      phone: _parseLevel(token.capabilities['phone']),
      hsi: _parseLevel(token.capabilities['hsi']),
      cloud: _parseLevel(token.capabilities['cloud']),
    );
  }

  /// Parse capability level from string
  static CapabilityLevel _parseLevel(String? level) {
    switch (level?.toLowerCase()) {
      case 'core':
        return CapabilityLevel.core;
      case 'extended':
        return CapabilityLevel.extended;
      case 'research':
        return CapabilityLevel.research;
      default:
        return CapabilityLevel.none;
    }
  }

  /// Create default capabilities (core level for all modules)
  factory SDKCapabilities.defaultCapabilities() {
    return const SDKCapabilities(
      behavior: CapabilityLevel.core,
      wear: CapabilityLevel.core,
      phone: CapabilityLevel.core,
      hsi: CapabilityLevel.core,
      cloud: CapabilityLevel.core,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'behavior': behavior.name,
      'wear': wear.name,
      'phone': phone.name,
      'hsi': hsi.name,
      'cloud': cloud.name,
    };
  }
}
