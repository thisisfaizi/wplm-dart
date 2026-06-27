import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'signature_verifier.dart';

/// A verified Certificate Revocation List fetched from `/crl`.
///
/// The CRL is itself an Ed25519-signed token. After verification it exposes the
/// set of revoked license-key hashes (SHA-256) and revoked device fingerprints
/// (server-side HMAC-SHA256).
///
/// Note: a client can match its **own license key** offline (it knows the
/// plaintext key, so it can compute the SHA-256), but it cannot recompute the
/// HMAC of its fingerprint without the server secret — device revocation is
/// therefore enforced online via `/validate`.
class RevocationList {
  const RevocationList({
    required this.revokedKeyHashes,
    required this.revokedFingerprints,
    this.generatedAt,
  });

  /// SHA-256 (hex) hashes of revoked/terminated license keys.
  final Set<String> revokedKeyHashes;

  /// HMAC-SHA256 (hex) hashes of revoked device fingerprints.
  final Set<String> revokedFingerprints;

  /// When the server generated the list.
  final DateTime? generatedAt;

  /// Verify [crlToken] with [verifier] and parse it.
  ///
  /// Throws [WplmSignatureInvalid] (from the verifier) if the CRL signature is
  /// invalid.
  static Future<RevocationList> parse(
    String crlToken,
    SignatureVerifier verifier,
  ) async {
    final Map<String, dynamic> payload = await verifier.verify(crlToken);

    Set<String> asStringSet(Object? v) =>
        v is List ? v.whereType<String>().toSet() : <String>{};

    final Object? generated = payload['generated_at'];

    return RevocationList(
      revokedKeyHashes: asStringSet(payload['revoked_keys']),
      revokedFingerprints: asStringSet(payload['revoked_fingerprints']),
      generatedAt: generated is String ? DateTime.tryParse(generated) : null,
    );
  }

  /// Whether [licenseKey] (plaintext) is revoked, by comparing its SHA-256.
  bool isKeyRevoked(String licenseKey) {
    final String hash = sha256.convert(utf8.encode(licenseKey)).toString();
    return revokedKeyHashes.contains(hash);
  }
}
