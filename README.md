<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=2,9,17&height=160&section=header&text=wplm-dart&fontSize=52&fontAlignY=42&animation=fadeIn&fontColor=ffffff" />

### WP License Manager — Dart / Flutter SDK

[![pub.dev](https://img.shields.io/pub/v/wplm?style=for-the-badge&logo=dart&logoColor=white&color=0175C2)](https://pub.dev/packages/wplm)
[![CI](https://img.shields.io/github/actions/workflow/status/wplm/wplm-dart/ci.yaml?style=for-the-badge&label=CI&logo=github-actions&logoColor=white)](https://github.com/thisisfaizi/wplm-dart/actions/workflows/ci.yaml)
[![Coverage](https://img.shields.io/codecov/c/github/wplm/wplm-dart?style=for-the-badge&logo=codecov&logoColor=white)](https://codecov.io/gh/wplm/wplm-dart)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)
[![Dart](https://img.shields.io/badge/Dart-3.0%2B-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)

<p>Offline-first Ed25519 license validation for Dart and Flutter apps,<br>
backed by a self-hosted <a href="https://github.com/thisisfaizi/wp-license-manager">WP License Manager</a> server.</p>

</div>

---

The official Dart/Flutter client for **[WP License Manager (WPLM)](https://github.com/thisisfaizi/wp-license-manager)**.
Validate, activate, and verify software licenses — **online and fully offline** —
on Android, iOS, Windows, macOS, Linux, web, and plain Dart.

- ✅ `validate` / `activate` / `deactivate` / `heartbeat`
- 🔏 **Offline** Ed25519 signature verification (no network needed)
- 🛡️ Signed CRL check (reject revoked keys offline)
- 🔌 Pluggable HTTP transport, fingerprint provider, and secure storage
- 🧱 Pure Dart core (no Flutter dependency) — works everywhere
- 🧯 Typed errors, retries with backoff, replay/clock-drift protection

---

## Install

```yaml
# pubspec.yaml
dependencies:
  wplm: ^0.1.0
  flutter_secure_storage: ^9.0.0   # recommended for OS secure cache
  device_info_plus: ^10.0.0        # recommended for hardware fingerprint
```

---

## Quick Start

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

---

## Offline Verification

`validate(offlineOk: true)` verifies the cached, Ed25519-signed payload locally
and checks it against the cached revocation list — so your app keeps working
without a network, and a revoked key is rejected within your CRL refresh window.

```dart
final result = await wplm.validate(offlineOk: true);
print(result.fromCache); // true when verified offline

// Verify an arbitrary signed token directly
final payload = await wplm.verifyOffline(signedPayloadString);
print(payload['expires']); // null = perpetual license

// Refresh and check the CRL
final crl = await wplm.checkCrl();
if (crl.isKeyRevoked('XXXX-XXXX-XXXX-XXXX')) {
  // block immediately
}
```

The SDK verifies `revoked_keys` offline (SHA-256 of the plaintext key). Device-level
revocation (`revoked_fingerprints`) is enforced by the server on the next online
`/validate` call.

---

## Flutter Integration (Hardware Fingerprint + Secure Storage)

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

See [`example/`](example/) for a complete Flutter wiring with `LicenseService`.

---

## Subscription Renewal

Renewals are handled through **WooCommerce My Account → Subscriptions → Renew**.
No SDK code is needed: after the customer pays, the server extends `expires_at`
and re-signs the offline payload. The next `validate()` call returns the updated
expiry and refreshes the local cache automatically.

---

## Error Handling

```dart
try {
  await wplm.activate();
} on WplmLimitExceeded {
  // no seats available
} on WplmRevoked {
  // license revoked
} on WplmExpired {
  // license expired — prompt renewal
} on WplmNetworkError {
  // offline / server unreachable — try offlineOk: true
}
```

---

## Development

```bash
dart pub get
dart analyze
dart test
dart format .
```

---

## Links

- [WP License Manager (server plugin)](https://github.com/thisisfaizi/wp-license-manager)
- [Python SDK](https://github.com/thisisfaizi/wplm-python)
- [PHP SDK](https://github.com/thisisfaizi/wplm-php)
- [JavaScript / TypeScript SDK](https://github.com/thisisfaizi/wplm-js)
- [OpenAPI 3.1 spec](https://github.com/thisisfaizi/wplm-openapi)

---

<div align="center">

MIT License · Part of the [WP License Manager](https://github.com/thisisfaizi/wp-license-manager) ecosystem

<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=2,9,17&height=80&section=footer" />

</div>
