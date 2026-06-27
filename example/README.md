# WPLM Dart SDK — examples

## Command-line demo

```bash
dart run example/wplm_example.dart https://license.vendor.com ABCD-EFGH-IJKL-MNOP
```

Runs the full flow: activate → validate (offline-capable) → heartbeat →
deactivate.

## Flutter integration (hardware fingerprint + secure storage)

The core SDK is pure Dart. On Flutter, plug in a hardware fingerprint and the OS
secure store by implementing the two provider interfaces. Add the deps to your
**app** (not the SDK):

```yaml
dependencies:
  wplm: ^0.1.0
  device_info_plus: ^10.0.0
  flutter_secure_storage: ^9.0.0
```

```dart
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wplm/wplm.dart';

/// Stores cached tokens in the OS keychain/keystore.
class SecureStore implements TokenStore {
  final _s = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// Derives a stable fingerprint from hardware identifiers.
class DeviceFingerprint implements FingerprintProvider {
  @override
  Future<String> get() async {
    final info = DeviceInfoPlugin();
    if (Theme.of(context).platform == TargetPlatform.android) {
      final a = await info.androidInfo;
      return 'android:${a.id}';
    }
    final i = await info.iosInfo;
    return 'ios:${i.identifierForVendor}';
  }
}

final wplm = WplmClient(
  baseUrl: 'https://license.vendor.com',
  licenseKey: userKey,
  productId: 42,
  publicKeyBase64: kWplmPublicKey, // bundle for offline verification
  store: SecureStore(),
  fingerprintProvider: DeviceFingerprint(),
);
```
