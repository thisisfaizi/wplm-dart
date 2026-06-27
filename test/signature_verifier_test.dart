import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:wplm/wplm.dart';

/// Produce a WPLM-format signed token exactly like the server:
/// `base64url(json) . "." . base64url(sign(base64url(json)))`.
Future<({String token, String publicKeyBase64})> _issue(
  Map<String, dynamic> payload,
) async {
  final Ed25519 algorithm = Ed25519();
  final SimpleKeyPair keyPair = await algorithm.newKeyPair();
  final SimplePublicKey pub = await keyPair.extractPublicKey();

  String b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  final String body = b64url(utf8.encode(jsonEncode(payload)));
  final Signature sig =
      await algorithm.sign(utf8.encode(body), keyPair: keyPair);

  return (
    token: '$body.${b64url(sig.bytes)}',
    publicKeyBase64: base64.encode(pub.bytes),
  );
}

void main() {
  group('SignatureVerifier', () {
    test('verifies a genuine token and returns the payload', () async {
      final payload = <String, dynamic>{
        'key': 'ABCD-EFGH-IJKL-MNOP',
        'expires': '2027-01-01T00:00:00Z',
        'max': 3,
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };
      final issued = await _issue(payload);
      final verifier = SignatureVerifier.fromBase64(issued.publicKeyBase64);

      final decoded = await verifier.verify(issued.token);

      expect(decoded['key'], 'ABCD-EFGH-IJKL-MNOP');
      expect(decoded['max'], 3);
    });

    test('rejects a tampered token', () async {
      final issued = await _issue(<String, dynamic>{'key': 'X', 'iat': 1});
      final verifier = SignatureVerifier.fromBase64(issued.publicKeyBase64);

      // Flip the last character of the payload body.
      final tampered = 'A${issued.token.substring(1)}';

      expect(
        () => verifier.verify(tampered),
        throwsA(isA<WplmSignatureInvalid>()),
      );
    });

    test('rejects a token signed by a different key', () async {
      final a = await _issue(<String, dynamic>{'key': 'A', 'iat': 1});
      final b = await _issue(<String, dynamic>{'key': 'B', 'iat': 1});
      // Verify A's token with B's public key.
      final verifier = SignatureVerifier.fromBase64(b.publicKeyBase64);

      expect(
        () => verifier.verify(a.token),
        throwsA(isA<WplmSignatureInvalid>()),
      );
    });

    test('rejects a malformed token', () async {
      final issued = await _issue(<String, dynamic>{'key': 'A', 'iat': 1});
      final verifier = SignatureVerifier.fromBase64(issued.publicKeyBase64);

      expect(
        () => verifier.verify('not-a-token'),
        throwsA(isA<WplmSignatureInvalid>()),
      );
    });

    test('clock-drift check accepts fresh and old, rejects future iat', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // Fresh payload: accepted.
      expect(
        SignatureVerifier.isWithinClockDrift(
          {'iat': now},
          const Duration(minutes: 5),
        ),
        isTrue,
      );
      // Old payload (issued an hour ago): still accepted — offline validity is
      // governed by `expires`, not time-boxed to the drift window.
      expect(
        SignatureVerifier.isWithinClockDrift(
          {'iat': now - 3600},
          const Duration(minutes: 5),
        ),
        isTrue,
      );
      // Payload issued in the future beyond the drift window: rejected (the
      // device clock was rolled back).
      expect(
        SignatureVerifier.isWithinClockDrift(
          {'iat': now + 3600},
          const Duration(minutes: 5),
        ),
        isFalse,
      );
    });
  });
}
