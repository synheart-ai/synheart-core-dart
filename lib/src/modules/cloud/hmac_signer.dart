import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class HMACSigner {
  final String hmacSecret;

  HMACSigner({required this.hmacSecret});

  /// Generate UUID v4 nonce
  /// Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  String generateNonce() {
    final random = Random.secure();

    // Generate 16 random bytes (128 bits)
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // Set version (4) in the 7th byte
    bytes[6] = (bytes[6] & 0x0f) | 0x40;

    // Set variant (10) in the 9th byte
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    // Convert to UUID v4 format string
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Compute HMAC-SHA256 signature
  /// Formula: HMAC-SHA256(timestamp + payload_bytes, secret)
  ///
  /// Args:
  ///   timestamp: Unix timestamp as string
  ///   bodyJson: Raw JSON payload as string
  ///
  /// Returns:
  ///   Hex-encoded signature
  String computeSignature({
    required String timestamp,
    required String bodyJson,
  }) {
    // Convert timestamp and bodyJson to bytes
    final timestampBytes = utf8.encode(timestamp);
    final bodyBytes = utf8.encode(bodyJson);

    // Concatenate: timestamp + payload
    final message = <int>[...timestampBytes, ...bodyBytes];

    // Compute HMAC-SHA256
    final hmac = Hmac(sha256, utf8.encode(hmacSecret));
    final digest = hmac.convert(message);

    return digest.toString();
  }
}
