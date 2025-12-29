import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class HMACSigner {
  final String hmacSecret;

  HMACSigner({required this.hmacSecret});

  /// Generate time-windowed nonce
  /// Format: <unix_timestamp>_<random_hex>
  String generateNonce() {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final random = Random.secure();
    final randomHex = List.generate(12, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${timestamp}_$randomHex';
  }

  /// Compute HMAC-SHA256 signature
  /// Signing string format (newline-separated):
  /// METHOD
  /// PATH
  /// TENANT_ID
  /// TIMESTAMP
  /// NONCE
  /// SHA256(body_json)
  String computeSignature({
    required String method,
    required String path,
    required String tenantId,
    required int timestamp,
    required String nonce,
    required String bodyJson,
  }) {
    // Compute SHA256 of body
    final bodyHash = sha256.convert(utf8.encode(bodyJson)).toString();

    // Construct signing string
    final signingString = [
      method.toUpperCase(),
      path,
      tenantId,
      timestamp.toString(),
      nonce,
      bodyHash,
    ].join('\n');

    // Compute HMAC-SHA256
    final hmac = Hmac(sha256, utf8.encode(hmacSecret));
    final digest = hmac.convert(utf8.encode(signingString));

    return digest.toString();
  }
}
