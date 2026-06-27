import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../errors.dart';

/// Verifies WPLM signed tokens (license payloads and the CRL) offline using the
/// server's Ed25519 public key.
///
/// Token format (must match the server exactly):
/// `base64url(json) . "." . base64url(ed25519_detached_signature)`,
/// where the signature is computed over the **base64url(json) string** (not the
/// raw JSON). The public key is the standard-base64 value from `/public-key`.
class SignatureVerifier {
  /// Create a verifier from raw 32-byte Ed25519 public key bytes.
  SignatureVerifier(this._publicKeyBytes);

  /// Create a verifier from the standard-base64 public key (as returned by the
  /// `/public-key` endpoint under `data.public_key`).
  factory SignatureVerifier.fromBase64(String base64PublicKey) {
    try {
      return SignatureVerifier(base64.decode(base64PublicKey.trim()));
    } on FormatException catch (e) {
      throw WplmSignatureInvalid('Invalid public key encoding: ${e.message}');
    }
  }

  final List<int> _publicKeyBytes;
  static final Ed25519 _ed25519 = Ed25519();

  /// Verify [token] and return its decoded JSON payload.
  ///
  /// Throws [WplmSignatureInvalid] if the token is malformed or the signature
  /// does not verify against the public key.
  Future<Map<String, dynamic>> verify(String token) async {
    final int dot = token.indexOf('.');
    if (dot <= 0 || dot >= token.length - 1) {
      throw const WplmSignatureInvalid('Malformed signed token');
    }

    final String body = token.substring(0, dot);
    final List<int> signatureBytes = _base64UrlDecode(token.substring(dot + 1));

    final bool ok = await _ed25519.verify(
      utf8.encode(body),
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(_publicKeyBytes, type: KeyPairType.ed25519),
      ),
    );
    if (!ok) {
      throw const WplmSignatureInvalid('Signature verification failed');
    }

    final Object? decoded = json.decode(utf8.decode(_base64UrlDecode(body)));
    if (decoded is! Map<String, dynamic>) {
      throw const WplmSignatureInvalid('Signed payload is not a JSON object');
    }
    return decoded;
  }

  /// Whether the payload's `iat` (issued-at unix seconds) is acceptable for a
  /// cached payload.
  ///
  /// This is a one-sided check: the payload must not appear to be issued in the
  /// *future* by more than [maxDrift]. A future `iat` means the device clock was
  /// rolled back (tamper). An arbitrarily *old* payload is fine — offline
  /// validity is governed by `expires`, not time-boxed to [maxDrift] — otherwise
  /// offline use would stop working [maxDrift] after the last online check.
  static bool isWithinClockDrift(
    Map<String, dynamic> payload,
    Duration maxDrift,
  ) {
    final Object? iat = payload['iat'];
    if (iat is! num) {
      return true; // No timestamp to check.
    }
    final DateTime issued =
        DateTime.fromMillisecondsSinceEpoch(iat.toInt() * 1000, isUtc: true);
    // issued - now > maxDrift  ⇒  payload comes from the future ⇒ reject.
    return issued.difference(DateTime.now().toUtc()) <= maxDrift;
  }

  /// Decode a base64url string that may be missing `=` padding (the server
  /// strips padding when emitting tokens).
  static List<int> _base64UrlDecode(String input) {
    final String normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    final int remainder = normalized.length % 4;
    final String padded =
        remainder == 0 ? normalized : normalized + ('=' * (4 - remainder));
    try {
      return base64.decode(padded);
    } on FormatException catch (e) {
      throw WplmSignatureInvalid('Invalid base64url segment: ${e.message}');
    }
  }
}
