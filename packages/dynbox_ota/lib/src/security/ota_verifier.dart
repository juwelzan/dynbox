import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// Cryptographic verifier for OTA update payload digests and signatures.
class OtaVerifier {
  /// Verifies that [payloadBytes] matches the expected [expectedSha256].
  static bool verifyDigest(List<int> payloadBytes, String expectedSha256) {
    final actualDigest = crypto.sha256
        .convert(payloadBytes)
        .toString()
        .toLowerCase();
    return actualDigest == expectedSha256.toLowerCase().trim();
  }

  /// Verifies the signature of [manifestJson] or payload using [secretOrPublicKey].
  ///
  /// Supports HMAC-SHA256 signature verification for trusted server configurations.
  static bool verifySignature({
    required String data,
    required String signature,
    required String secretOrPublicKey,
  }) {
    if (signature.isEmpty || secretOrPublicKey.isEmpty) return false;
    final hmac = crypto.Hmac(crypto.sha256, utf8.encode(secretOrPublicKey));
    final expectedDigest = hmac
        .convert(utf8.encode(data))
        .toString()
        .toLowerCase();
    return expectedDigest == signature.toLowerCase().trim();
  }

  /// Computes HMAC-SHA256 signature for server/publisher tools.
  static String signData({required String data, required String secretKey}) {
    final hmac = crypto.Hmac(crypto.sha256, utf8.encode(secretKey));
    return hmac.convert(utf8.encode(data)).toString();
  }
}
