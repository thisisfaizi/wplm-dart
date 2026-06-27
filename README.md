# WPLM SDK for Dart & Flutter

[![CI](https://github.com/wplm/wplm-dart/actions/workflows/ci.yaml/badge.svg)](https://github.com/wplm/wplm-dart/actions/workflows/ci.yaml)
[![pub package](https://img.shields.io/pub/v/wplm.svg)](https://pub.dev/packages/wplm)

The official Dart/Flutter client for **[WP License Manager (WPLM)](https://github.com/wplm/wp-license-manager)**.
Validate, activate, and verify software licenses — **online and fully offline** —
on Android, iOS, Windows, macOS, Linux, web, and plain Dart.

- ✅ `validate` / `activate` / `deactivate` / `heartbeat`
- 🔏 **Offline** Ed25519 signature verification (no network needed)
- 🛡️ Signed CRL check (reject revoked keys offline)
- 🔌 Pluggable HTTP transport, fingerprint provider, and secure storage
- 🧱 Pure Dart core (no Flutter dependency) — works everywhere
- 🧯 Typed errors, retries with backoff, replay/clock-drift protection

## Install

```yaml
dependencies:
  wplm: ^0.1.0
```

## Quick start

```dart
import 'package:wplm/wplm.dart';

final wplm = WplmClient(
  baseUrl: 'https://license.vendor.com',
  productId: 42,
  licenseKey: userEnteredKey,
);

// Bind this device (consumes a seat).
final machine = await wplm.activate();

// Check the license (online; falls back to a cached signed payload offline).
final result = await wplm.validate(offlineOk: true);
if (result.valid) {
  // unlock pro features
}

// Keep a floating lease alive.
await wplm.heartbeat();

// Free the seat on sign-out.
await wplm.deactivate();
```

## Offline verification

`validate(offlineOk: true)` verifies the cached, Ed25519-signed payload locally
and checks it against the cached revocation list — so your app keeps working
without a network, and a revoked key is rejected within your CRL refresh window.

```dart
final result = await wplm.validate(offlineOk: true);
print(result.fromCache); // true when verified offline
```

## Flutter integration (hardware fingerprint + secure storage)

The core is pure Dart with a persisted-UUID fingerprint and in-memory store by
default. For a hardware-bound fingerprint and OS secure storage, plug in
`device_info_plus` and `flutter_secure_storage`:

```dart
final wplm = WplmClient(
  baseUrl: '...',
  licenseKey: key,
  fingerprintProvider: MyDeviceInfoFingerprint(), // implements FingerprintProvider
  store: MySecureStore(),                          // implements TokenStore
);
```

See [`example/`](example/) for a complete wiring.

## Error handling

```dart
try {
  await wplm.activate();
} on WplmLimitExceeded {
  // no seats available
} on WplmRevoked {
  // license revoked
} on WplmNetworkError {
  // offline / server unreachable
}
```

## License

MIT — see [LICENSE](LICENSE). This SDK ships only the public key; no secrets.
