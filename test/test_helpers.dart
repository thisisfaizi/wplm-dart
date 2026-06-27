import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:wplm/wplm.dart';

/// Issues WPLM-format signed tokens in tests, mirroring the server's Signer.
class TestSigner {
  TestSigner._(this._algorithm, this._keyPair, this.publicKeyBase64);

  final Ed25519 _algorithm;
  final SimpleKeyPair _keyPair;

  /// Standard-base64 public key (as the server's `/public-key` returns).
  final String publicKeyBase64;

  static Future<TestSigner> create() async {
    final Ed25519 algorithm = Ed25519();
    final SimpleKeyPair keyPair = await algorithm.newKeyPair();
    final SimplePublicKey pub = await keyPair.extractPublicKey();
    return TestSigner._(algorithm, keyPair, base64.encode(pub.bytes));
  }

  String _b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  /// Sign [payload] into a `base64url(json).base64url(sig)` token.
  Future<String> sign(Map<String, dynamic> payload) async {
    final String body = _b64url(utf8.encode(jsonEncode(payload)));
    final Signature sig =
        await _algorithm.sign(utf8.encode(body), keyPair: _keyPair);
    return '$body.${_b64url(sig.bytes)}';
  }
}

/// A scripted [WplmTransport] for unit tests.
class FakeTransport implements WplmTransport {
  FakeTransport(this.handler);

  /// Returns a canned response for a request.
  final WplmResponse Function(String method, Uri url, String? body) handler;

  /// Records every request for assertions.
  final List<({String method, Uri url, String? body})> calls =
      <({String method, Uri url, String? body})>[];

  @override
  Future<WplmResponse> send({
    required String method,
    required Uri url,
    Map<String, String>? headers,
    String? body,
  }) async {
    calls.add((method: method, url: url, body: body));
    return handler(method, url, body);
  }

  @override
  void close() {}
}

/// Build a success envelope body.
String successBody(Map<String, dynamic> data) => jsonEncode(<String, dynamic>{
      'success': true,
      'data': data,
      'meta': <String, dynamic>{},
    });

/// Build a WP_Error envelope body.
String errorBody(String code, String message, int status) => jsonEncode(
      <String, dynamic>{
        'code': code,
        'message': message,
        'data': <String, dynamic>{'status': status},
      },
    );
