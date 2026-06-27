import 'dart:convert';

import 'crypto/crl.dart';
import 'crypto/signature_verifier.dart';
import 'device/device_info.dart';
import 'errors.dart';
import 'fingerprint/fingerprint_provider.dart';
import 'http/transport.dart';
import 'models/machine.dart';
import 'models/validation_result.dart';
import 'storage/token_store.dart';

/// The WPLM client. Talks to a WP License Manager server's `wplm/v1` REST API
/// and verifies signed license payloads offline.
///
/// ```dart
/// final wplm = WplmClient(
///   baseUrl: 'https://license.vendor.com',
///   productId: 42,
///   licenseKey: userKey,
/// );
/// await wplm.activate();
/// final result = await wplm.validate(offlineOk: true);
/// ```
class WplmClient {
  WplmClient({
    required String baseUrl,
    this.licenseKey,
    this.productId,
    this.publicKeyBase64,
    this.maxClockDrift = const Duration(minutes: 5),
    this.crlTtl = const Duration(hours: 1),
    WplmTransport? transport,
    TokenStore? store,
    FingerprintProvider? fingerprintProvider,
    DeviceInfoProvider? deviceInfoProvider,
  })  : _base = _normalizeBase(baseUrl),
        _transport = transport ?? HttpTransport(),
        _store = store ?? InMemoryTokenStore(),
        _deviceInfoProvider = deviceInfoProvider {
    _fingerprintProvider =
        fingerprintProvider ?? PersistedUuidFingerprintProvider(_store);
  }

  /// The license key being managed (required for validate/activate/etc.).
  final String? licenseKey;

  /// The product id this client licenses (optional, informational).
  final int? productId;

  /// The Ed25519 public key (standard base64) bundled for offline verification.
  /// When null, it is fetched from `/public-key` on first use and cached.
  final String? publicKeyBase64;

  /// Maximum allowed drift of a cached payload's issue time (replay protection).
  final Duration maxClockDrift;

  /// How long a cached CRL is considered fresh before a refresh is attempted.
  final Duration crlTtl;

  final Uri _base;
  final WplmTransport _transport;
  final TokenStore _store;
  final DeviceInfoProvider? _deviceInfoProvider;
  late final FingerprintProvider _fingerprintProvider;

  SignatureVerifier? _verifierCache;
  WplmDeviceInfo? _deviceInfoCache;

  static const String _kSignedPayload = 'wplm.signed_payload';
  static const String _kPublicKey = 'wplm.public_key';
  static const String _kCrl = 'wplm.crl';
  static const String _kCrlAt = 'wplm.crl_at';
  static const String _kTimeFloor = 'wplm.time_floor';

  // ---------------------------------------------------------------------------
  // Public operations
  // ---------------------------------------------------------------------------

  /// Validate the license. Online by default; when [offlineOk] is true and the
  /// network is unavailable, falls back to verifying the cached signed payload.
  Future<ValidationResult> validate({bool offlineOk = false}) async {
    final String key = _requireKey();
    try {
      final String fingerprint = await _fingerprintProvider.get();
      final Map<String, dynamic> data = await _post('/validate', {
        'license_key': key,
        'fingerprint': fingerprint,
      });

      final ValidationResult result = ValidationResult.fromJson(data);
      final String? signed = result.signedPayload;
      if (signed != null && signed.isNotEmpty) {
        await _store.write(_kSignedPayload, signed);
      }
      // Enforce product binding from the *signed* payload (not the unsigned
      // license JSON), so a key issued for another product is rejected even
      // online. No-op when productId is null.
      if (result.valid && productId != null) {
        if (signed == null || signed.isEmpty) {
          throw WplmProductMismatch(
            'License is valid but carries no signed payload to verify product '
            'binding for product $productId.',
            code: 'product_mismatch',
          );
        }
        _enforceProductId(await _verifyWithKeyRefresh(signed));
      }
      // A successful online call is a trusted clock reading — advance the
      // monotonic time floor so a later offline clock rollback is detectable.
      await _advanceTimeFloor(
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      );
      await _maybeRefreshCrl();
      return result;
    } on WplmNetworkError {
      if (offlineOk) {
        final ValidationResult? offline = await _validateOffline(key);
        if (offline != null) {
          return offline;
        }
      }
      rethrow;
    }
  }

  /// Activate (bind) the current device. Idempotent: re-activating an existing
  /// device does not consume a new seat. Returns the [Machine].
  Future<Machine> activate({
    String? name,
    String? hostname,
    String? platform,
    String? appVersion,
  }) async {
    final String key = _requireKey();
    final String fingerprint = await _fingerprintProvider.get();
    final WplmDeviceInfo? info = await _deviceInfo();
    final Map<String, dynamic> data = await _post('/activate', {
      'license_key': key,
      'fingerprint': fingerprint,
      ..._deviceFields(
        name: name,
        hostname: hostname,
        platform: platform,
        appVersion: appVersion,
        info: info,
      ),
    });
    return Machine.fromJson(data);
  }

  /// Deactivate the current device, freeing its seat.
  Future<bool> deactivate() async {
    final String key = _requireKey();
    final String fingerprint = await _fingerprintProvider.get();
    final Map<String, dynamic> data = await _post('/deactivate', {
      'license_key': key,
      'fingerprint': fingerprint,
    });
    return data['deactivated'] == true;
  }

  /// Send a heartbeat (keep-alive / renew a floating lease). Returns the
  /// refreshed [Machine].
  Future<Machine> heartbeat({String? appVersion}) async {
    final String key = _requireKey();
    final String fingerprint = await _fingerprintProvider.get();
    final String? resolvedVersion =
        appVersion ?? (await _deviceInfo())?.appVersion;
    final Map<String, dynamic> data = await _post('/heartbeat', {
      'license_key': key,
      'fingerprint': fingerprint,
      if (resolvedVersion != null) 'app_version': resolvedVersion,
    });
    return Machine.fromJson(data);
  }

  /// Resolve cached device info from the provider (if any); fetched once.
  Future<WplmDeviceInfo?> _deviceInfo() async {
    if (_deviceInfoProvider == null) {
      return null;
    }
    return _deviceInfoCache ??= await _deviceInfoProvider.get();
  }

  /// Merge explicit args over provider-supplied device info, dropping nulls.
  Map<String, dynamic> _deviceFields({
    String? name,
    String? hostname,
    String? platform,
    String? appVersion,
    WplmDeviceInfo? info,
  }) {
    final Map<String, String> out = {};
    final String? n = name ?? info?.name;
    final String? h = hostname ?? info?.hostname;
    final String? p = platform ?? info?.platform;
    final String? v = appVersion ?? info?.appVersion;
    if (n != null && n.isNotEmpty) out['name'] = n;
    if (h != null && h.isNotEmpty) out['hostname'] = h;
    if (p != null && p.isNotEmpty) out['platform'] = p;
    if (v != null && v.isNotEmpty) out['app_version'] = v;
    return out;
  }

  /// Verify an arbitrary signed token offline; returns the decoded payload.
  /// Throws [WplmSignatureInvalid] on failure.
  Future<Map<String, dynamic>> verifyOffline(String token) async {
    final SignatureVerifier verifier = await _verifier();
    return verifier.verify(token);
  }

  /// Fetch, verify, and cache the revocation list from `/crl`.
  Future<RevocationList> checkCrl() async {
    final Map<String, dynamic> data = await _get('/crl');
    final String token = (data['crl'] as String?) ?? '';
    final SignatureVerifier verifier = await _verifier();
    final RevocationList list = await RevocationList.parse(token, verifier);
    await _store.write(_kCrl, token);
    await _store.write(
      _kCrlAt,
      DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
    );
    return list;
  }

  /// Release the underlying transport.
  void dispose() => _transport.close();

  // ---------------------------------------------------------------------------
  // Offline validation
  // ---------------------------------------------------------------------------

  /// Verify [token] online, recovering from server keypair rotation: if the
  /// cached public key fails verification, drop it, re-fetch `/public-key`
  /// once, and retry. This self-heals clients that cached an old public key
  /// before the vendor rotated the signing keypair.
  Future<Map<String, dynamic>> _verifyWithKeyRefresh(String token) async {
    try {
      return await (await _verifier()).verify(token);
    } on WplmSignatureInvalid {
      // Cached key may be stale — invalidate and re-fetch once.
      _verifierCache = null;
      await _store.delete(_kPublicKey);
      return (await _verifier()).verify(token);
    }
  }

  /// Reject a signed payload whose product binding does not match [productId].
  ///
  /// No-op when [productId] is null (the app opted out of product binding).
  /// When [productId] is set, the payload's signed `pid` must equal it; a
  /// missing or different `pid` throws [WplmProductMismatch]. Enforced from the
  /// signed payload so the rule holds identically online and offline.
  void _enforceProductId(Map<String, dynamic> payload) {
    final int? expected = productId;
    if (expected == null) {
      return;
    }
    final Object? pid = payload['pid'];
    final int? actual = pid is num ? pid.toInt() : null;
    if (actual != expected) {
      throw WplmProductMismatch(
        'License is bound to product ${actual ?? 'none'}, but this app is '
        'configured for product $expected.',
        code: 'product_mismatch',
      );
    }
  }

  Future<ValidationResult?> _validateOffline(String key) async {
    final String? token = await _store.read(_kSignedPayload);
    if (token == null || token.isEmpty) {
      return null;
    }

    final SignatureVerifier? verifier =
        await _verifierOrNull(allowNetwork: false);
    if (verifier == null) {
      return null; // No key available offline; cannot verify.
    }

    final Map<String, dynamic> payload;
    try {
      payload = await verifier.verify(token);
    } on WplmSignatureInvalid {
      return const ValidationResult(
        valid: false,
        code: 'signature_invalid',
        fromCache: true,
      );
    }

    // Product binding is enforced offline too: the signed `pid` must match the
    // configured productId. No-op when productId is null.
    _enforceProductId(payload);

    if (!SignatureVerifier.isWithinClockDrift(payload, maxClockDrift)) {
      return const ValidationResult(
        valid: false,
        code: 'clock_drift',
        fromCache: true,
      );
    }

    // Monotonic time floor (high-water mark): use the greater of the device
    // clock, the payload's issue time, and the highest time ever observed, so a
    // rolled-back device clock cannot un-expire the license while offline.
    final Object? iat = payload['iat'];
    if (iat is num) {
      await _advanceTimeFloor(iat.toInt());
    }
    final int deviceNow = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    await _advanceTimeFloor(deviceNow);
    final int effectiveNow = await _readTimeFloor();

    final Object? expires = payload['expires'];
    if (expires is String && expires.isNotEmpty) {
      final DateTime? exp = DateTime.tryParse(expires);
      if (exp != null &&
          effectiveNow > exp.toUtc().millisecondsSinceEpoch ~/ 1000) {
        return const ValidationResult(
          valid: false,
          code: 'expired',
          fromCache: true,
        );
      }
    }

    final RevocationList? crl = await _cachedCrl(verifier);
    if (crl != null && crl.isKeyRevoked(key)) {
      return const ValidationResult(
        valid: false,
        code: 'revoked',
        fromCache: true,
      );
    }

    return const ValidationResult(valid: true, fromCache: true);
  }

  /// Highest trusted unix-second time ever observed (online success, payload
  /// issue time, or a forward-moving device clock). Defaults to 0.
  Future<int> _readTimeFloor() async {
    final String? raw = await _store.read(_kTimeFloor);
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// Advance the monotonic time floor if [epochSeconds] is newer. Never moves
  /// backwards, so a rolled-back clock cannot lower it.
  Future<void> _advanceTimeFloor(int epochSeconds) async {
    if (epochSeconds <= 0) {
      return;
    }
    if (epochSeconds > await _readTimeFloor()) {
      await _store.write(_kTimeFloor, epochSeconds.toString());
    }
  }

  Future<RevocationList?> _cachedCrl(SignatureVerifier verifier) async {
    final String? token = await _store.read(_kCrl);
    if (token == null || token.isEmpty) {
      return null;
    }
    try {
      return await RevocationList.parse(token, verifier);
    } on WplmSignatureInvalid {
      return null;
    }
  }

  Future<void> _maybeRefreshCrl() async {
    final String? at = await _store.read(_kCrlAt);
    final bool fresh = at != null &&
        DateTime.now().toUtc().millisecondsSinceEpoch -
                (int.tryParse(at) ?? 0) <
            crlTtl.inMilliseconds;
    if (fresh) {
      return;
    }
    try {
      await checkCrl();
    } on WplmError {
      // Best-effort; a stale/missing CRL must not break online validation.
    }
  }

  // ---------------------------------------------------------------------------
  // Verifier resolution
  // ---------------------------------------------------------------------------

  Future<SignatureVerifier> _verifier() async {
    final SignatureVerifier? v = await _verifierOrNull(allowNetwork: true);
    if (v == null) {
      throw const WplmConfigError(
        'No Ed25519 public key available. Bundle publicKeyBase64 or call an '
        'online method once to fetch and cache it.',
      );
    }
    return v;
  }

  Future<SignatureVerifier?> _verifierOrNull(
      {required bool allowNetwork}) async {
    if (_verifierCache != null) {
      return _verifierCache;
    }
    String? b64 = publicKeyBase64 ?? await _store.read(_kPublicKey);
    if ((b64 == null || b64.isEmpty) && allowNetwork) {
      final Map<String, dynamic> data = await _get('/public-key');
      b64 = data['public_key'] as String?;
      if (b64 != null && b64.isNotEmpty) {
        await _store.write(_kPublicKey, b64);
      }
    }
    if (b64 == null || b64.isEmpty) {
      return null;
    }
    return _verifierCache = SignatureVerifier.fromBase64(b64);
  }

  // ---------------------------------------------------------------------------
  // HTTP plumbing
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final WplmResponse res = await _transport.send(
      method: 'POST',
      url: _base.resolve(_base.path + path),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: jsonEncode(body),
    );
    return _unwrap(res);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final WplmResponse res = await _transport.send(
      method: 'GET',
      url: _base.resolve(_base.path + path),
      headers: const {'Accept': 'application/json'},
    );
    return _unwrap(res);
  }

  /// Parse the response envelope, returning `data` on success or throwing the
  /// mapped [WplmError] on an API error.
  Map<String, dynamic> _unwrap(WplmResponse res) {
    final Object? decoded = _tryJson(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw WplmApiError(
        'Unexpected response (HTTP ${res.statusCode})',
        status: res.statusCode,
      );
    }

    if (decoded['success'] == true && decoded['data'] is Map<String, dynamic>) {
      return decoded['data'] as Map<String, dynamic>;
    }

    final String code = (decoded['code'] as String?) ?? 'wplm_unknown_error';
    final String message = (decoded['message'] as String?) ??
        'Request failed (HTTP ${res.statusCode}).';
    throw WplmError.fromCode(code, message, status: res.statusCode);
  }

  Object? _tryJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  String _requireKey() {
    final String? key = licenseKey;
    if (key == null || key.isEmpty) {
      throw const WplmConfigError('No licenseKey configured.');
    }
    return key;
  }

  static Uri _normalizeBase(String baseUrl) {
    final String trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$trimmed/wp-json/wplm/v1');
  }
}
