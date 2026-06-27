import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:wplm/wplm.dart';

import 'test_helpers.dart';

void main() {
  group('RevocationList', () {
    test('parses a signed CRL and detects a revoked key', () async {
      final signer = await TestSigner.create();
      const revokedKey = 'REVOKED-1234-5678';
      final String revokedHash =
          sha256.convert(utf8.encode(revokedKey)).toString();

      final token = await signer.sign(<String, dynamic>{
        'revoked_keys': <String>[revokedHash],
        'revoked_fingerprints': <String>[],
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      final list = await RevocationList.parse(
        token,
        SignatureVerifier.fromBase64(signer.publicKeyBase64),
      );

      expect(list.isKeyRevoked(revokedKey), isTrue);
      expect(list.isKeyRevoked('SOME-OTHER-KEY'), isFalse);
      expect(list.revokedKeyHashes, contains(revokedHash));
    });

    test('rejects a CRL signed by the wrong key', () async {
      final signer = await TestSigner.create();
      final other = await TestSigner.create();

      final token = await signer.sign(<String, dynamic>{
        'revoked_keys': <String>[],
        'revoked_fingerprints': <String>[],
        'iat': 1,
      });

      expect(
        () => RevocationList.parse(
          token,
          SignatureVerifier.fromBase64(other.publicKeyBase64),
        ),
        throwsA(isA<WplmSignatureInvalid>()),
      );
    });
  });
}
