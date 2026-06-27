import 'package:test/test.dart';
import 'package:wplm/wplm.dart';

import 'test_helpers.dart';

class _FakeDeviceInfo implements DeviceInfoProvider {
  @override
  Future<WplmDeviceInfo> get() async => const WplmDeviceInfo(
        name: 'Surface',
        hostname: 'DESKTOP-1',
        platform: 'Windows 11 · Surface Pro 9',
        appVersion: '2.3.4',
      );
}

void main() {
  group('WplmClient online', () {
    test('validate parses a valid result and caches the signed payload',
        () async {
      final store = InMemoryTokenStore();
      final transport = FakeTransport((method, url, body) {
        if (url.path.endsWith('/validate')) {
          return WplmResponse(
            200,
            successBody(<String, dynamic>{
              'valid': true,
              'license': <String, dynamic>{'id': 1, 'status': 1},
              'signed_payload': 'header.sig',
              'needs_activation': false,
            }),
          );
        }
        // The opportunistic CRL refresh after a successful validate.
        return WplmResponse(200, successBody(<String, dynamic>{'crl': ''}));
      });

      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        transport: transport,
        store: store,
      );

      final result = await client.validate();

      expect(result.valid, isTrue);
      expect(result.license?.id, 1);
      expect(await store.read('wplm.signed_payload'), 'header.sig');
    });

    test('activate returns a Machine', () async {
      final transport = FakeTransport(
        (m, u, b) => WplmResponse(
          201,
          successBody(<String, dynamic>{
            'id': 7,
            'license_id': 1,
            'fingerprint': 'fp',
            'status': 1,
          }),
        ),
      );
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        transport: transport,
      );

      final machine = await client.activate(name: 'Office PC');

      expect(machine.id, 7);
      expect(machine.isActive, isTrue);
    });

    test('activate sends device info from the provider', () async {
      final transport = FakeTransport(
        (m, u, b) => WplmResponse(
          201,
          successBody(<String, dynamic>{
            'id': 1,
            'license_id': 1,
            'fingerprint': 'fp',
            'status': 1,
          }),
        ),
      );
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        transport: transport,
        deviceInfoProvider: _FakeDeviceInfo(),
      );

      await client.activate();

      final String body = transport.calls.last.body ?? '';
      expect(body, contains('"name":"Surface"'));
      expect(body, contains('"hostname":"DESKTOP-1"'));
      expect(body, contains('Windows 11'));
      expect(body, contains('"app_version":"2.3.4"'));
    });

    test('explicit activate args override the device info provider', () async {
      final transport = FakeTransport(
        (m, u, b) => WplmResponse(
          201,
          successBody(<String, dynamic>{
            'id': 1,
            'license_id': 1,
            'fingerprint': 'fp',
            'status': 1,
          }),
        ),
      );
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        transport: transport,
        deviceInfoProvider: _FakeDeviceInfo(),
      );

      await client.activate(name: 'Custom Name');

      final String body = transport.calls.last.body ?? '';
      expect(body, contains('"name":"Custom Name"'));
      expect(body, isNot(contains('"name":"Surface"')));
    });

    test('maps a server error code to a typed error', () async {
      final transport = FakeTransport(
        (m, u, b) => WplmResponse(
          422,
          errorBody('machine_limit_exceeded', 'No seats left', 422),
        ),
      );
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        transport: transport,
      );

      expect(client.activate(), throwsA(isA<WplmLimitExceeded>()));
    });

    test('deactivate returns true', () async {
      final transport = FakeTransport(
        (m, u, b) => WplmResponse(
            200, successBody(<String, dynamic>{'deactivated': true})),
      );
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        transport: transport,
      );

      expect(await client.deactivate(), isTrue);
    });

    test('throws WplmConfigError when no license key is set', () async {
      final client = WplmClient(
        baseUrl: 'https://example.test',
        transport: FakeTransport(
          (m, u, b) => WplmResponse(200, successBody(<String, dynamic>{})),
        ),
      );
      expect(client.validate(), throwsA(isA<WplmConfigError>()));
    });
  });

  group('WplmClient offline-first', () {
    test('validates offline from a cached signed payload', () async {
      final signer = await TestSigner.create();
      final token = await signer.sign(<String, dynamic>{
        'key': 'KEY',
        'expires': '2099-01-01T00:00:00Z',
        'max': 3,
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      final store = InMemoryTokenStore();
      await store.write('wplm.signed_payload', token);

      // Transport always fails (offline).
      final transport = FakeTransport((m, u, b) {
        throw const WplmNetworkError('offline');
      });

      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        publicKeyBase64: signer.publicKeyBase64,
        transport: transport,
        store: store,
      );

      final result = await client.validate(offlineOk: true);

      expect(result.valid, isTrue);
      expect(result.fromCache, isTrue);
    });

    test('offline detects an expired cached payload', () async {
      final signer = await TestSigner.create();
      final token = await signer.sign(<String, dynamic>{
        'key': 'KEY',
        'expires': '2000-01-01T00:00:00Z',
        'max': 3,
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      final store = InMemoryTokenStore();
      await store.write('wplm.signed_payload', token);

      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        publicKeyBase64: signer.publicKeyBase64,
        transport: FakeTransport((m, u, b) {
          throw const WplmNetworkError('offline');
        }),
        store: store,
      );

      final result = await client.validate(offlineOk: true);

      expect(result.valid, isFalse);
      expect(result.code, 'expired');
      expect(result.fromCache, isTrue);
    });

    test('offline rejects an expired license even if the clock is rolled back',
        () async {
      final signer = await TestSigner.create();
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // By the device clock the license is still valid (expires tomorrow), so
      // without the time floor this would pass...
      final expires =
          DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String();
      final token = await signer.sign(<String, dynamic>{
        'key': 'KEY',
        'expires': expires,
        'max': 3,
        'iat': nowSec - 7 * 24 * 3600,
      });

      final store = InMemoryTokenStore();
      await store.write('wplm.signed_payload', token);
      // ...but the app previously observed a time PAST the expiry (high-water
      // mark two days out), proving the clock was rolled back — so it's expired.
      await store.write(
        'wplm.time_floor',
        (nowSec + 2 * 24 * 3600).toString(),
      );

      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        publicKeyBase64: signer.publicKeyBase64,
        transport: FakeTransport((m, u, b) {
          throw const WplmNetworkError('offline');
        }),
        store: store,
      );

      final result = await client.validate(offlineOk: true);

      expect(result.valid, isFalse);
      expect(result.code, 'expired');
    });

    test('rethrows network error when offline and no cache', () async {
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        transport: FakeTransport((m, u, b) {
          throw const WplmNetworkError('offline');
        }),
        store: InMemoryTokenStore(),
      );

      expect(
        client.validate(offlineOk: true),
        throwsA(isA<WplmNetworkError>()),
      );
    });
  });

  group('WplmClient product binding', () {
    Future<({String token, String publicKey})> signWithPid(int? pid) async {
      final signer = await TestSigner.create();
      final token = await signer.sign(<String, dynamic>{
        'key': 'KEY',
        'expires': '2099-01-01T00:00:00Z',
        'max': 3,
        'pid': pid,
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      return (token: token, publicKey: signer.publicKeyBase64);
    }

    test('online: matching pid passes', () async {
      final s = await signWithPid(42);
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        productId: 42,
        publicKeyBase64: s.publicKey,
        transport: FakeTransport((m, u, b) {
          if (u.path.endsWith('/validate')) {
            return WplmResponse(
              200,
              successBody(<String, dynamic>{
                'valid': true,
                'license': <String, dynamic>{'id': 1, 'status': 1},
                'signed_payload': s.token,
                'needs_activation': false,
              }),
            );
          }
          return WplmResponse(200, successBody(<String, dynamic>{'crl': ''}));
        }),
        store: InMemoryTokenStore(),
      );

      final result = await client.validate();
      expect(result.valid, isTrue);
    });

    test('online: mismatched pid throws WplmProductMismatch', () async {
      final s = await signWithPid(99); // key is for product 99
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        productId: 42, // but this app is product 42
        publicKeyBase64: s.publicKey,
        transport: FakeTransport((m, u, b) {
          if (u.path.endsWith('/validate')) {
            return WplmResponse(
              200,
              successBody(<String, dynamic>{
                'valid': true,
                'license': <String, dynamic>{'id': 1, 'status': 1},
                'signed_payload': s.token,
                'needs_activation': false,
              }),
            );
          }
          return WplmResponse(200, successBody(<String, dynamic>{'crl': ''}));
        }),
        store: InMemoryTokenStore(),
      );

      expect(client.validate(), throwsA(isA<WplmProductMismatch>()));
    });

    test('offline: matching pid passes', () async {
      final s = await signWithPid(42);
      final store = InMemoryTokenStore();
      await store.write('wplm.signed_payload', s.token);
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        productId: 42,
        publicKeyBase64: s.publicKey,
        transport: FakeTransport((m, u, b) {
          throw const WplmNetworkError('offline');
        }),
        store: store,
      );

      final result = await client.validate(offlineOk: true);
      expect(result.valid, isTrue);
      expect(result.fromCache, isTrue);
    });

    test('offline: mismatched pid throws WplmProductMismatch', () async {
      final s = await signWithPid(99);
      final store = InMemoryTokenStore();
      await store.write('wplm.signed_payload', s.token);
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        productId: 42,
        publicKeyBase64: s.publicKey,
        transport: FakeTransport((m, u, b) {
          throw const WplmNetworkError('offline');
        }),
        store: store,
      );

      expect(
        client.validate(offlineOk: true),
        throwsA(isA<WplmProductMismatch>()),
      );
    });

    test('offline: pid enforced even when productId set but token has no pid',
        () async {
      final s = await signWithPid(null); // legacy token, no pid
      final store = InMemoryTokenStore();
      await store.write('wplm.signed_payload', s.token);
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        productId: 42,
        publicKeyBase64: s.publicKey,
        transport: FakeTransport((m, u, b) {
          throw const WplmNetworkError('offline');
        }),
        store: store,
      );

      expect(
        client.validate(offlineOk: true),
        throwsA(isA<WplmProductMismatch>()),
      );
    });

    test('backward compatible: no productId configured skips pid check',
        () async {
      final s = await signWithPid(null); // legacy token, no pid
      final store = InMemoryTokenStore();
      await store.write('wplm.signed_payload', s.token);
      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        // productId intentionally null = opt out of product binding
        publicKeyBase64: s.publicKey,
        transport: FakeTransport((m, u, b) {
          throw const WplmNetworkError('offline');
        }),
        store: store,
      );

      final result = await client.validate(offlineOk: true);
      expect(result.valid, isTrue);
    });

    test('online recovers from a rotated signing key', () async {
      // Token signed by the CURRENT key, but the store holds a STALE key.
      final good = await signWithPid(42);
      final stale = await TestSigner.create();
      final store = InMemoryTokenStore();
      await store.write('wplm.public_key', stale.publicKeyBase64);

      final client = WplmClient(
        baseUrl: 'https://example.test',
        licenseKey: 'KEY',
        productId: 42,
        // publicKeyBase64 omitted so it reads the stale store key first.
        transport: FakeTransport((m, u, b) {
          if (u.path.endsWith('/validate')) {
            return WplmResponse(
              200,
              successBody(<String, dynamic>{
                'valid': true,
                'license': <String, dynamic>{'id': 1, 'status': 1},
                'signed_payload': good.token,
                'needs_activation': false,
              }),
            );
          }
          if (u.path.endsWith('/public-key')) {
            return WplmResponse(
              200,
              successBody(<String, dynamic>{'public_key': good.publicKey}),
            );
          }
          return WplmResponse(200, successBody(<String, dynamic>{'crl': ''}));
        }),
        store: store,
      );

      final result = await client.validate();
      expect(result.valid, isTrue);
    });
  });
}
