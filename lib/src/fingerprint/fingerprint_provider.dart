import 'dart:math';

import '../storage/token_store.dart';

/// Produces a stable per-device fingerprint.
///
/// The default ([PersistedUuidFingerprintProvider]) is pure Dart and works
/// everywhere. For a hardware-bound fingerprint on Flutter, implement this with
/// `device_info_plus` and pass it to the client.
abstract class FingerprintProvider {
  /// Return the device fingerprint (raw; the server hashes it server-side).
  Future<String> get();
}

/// Generates a cryptographically-random fingerprint once and persists it in the
/// [TokenStore], so it stays stable for the lifetime of the install.
class PersistedUuidFingerprintProvider implements FingerprintProvider {
  PersistedUuidFingerprintProvider(
    this._store, {
    this.storageKey = 'wplm.fingerprint',
  });

  final TokenStore _store;

  /// Storage key under which the fingerprint is persisted.
  final String storageKey;

  @override
  Future<String> get() async {
    final String? existing = await _store.read(storageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final String fingerprint = _generate();
    await _store.write(storageKey, fingerprint);
    return fingerprint;
  }

  String _generate() {
    final Random rnd = Random.secure();
    final List<int> bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// A provider that always returns a caller-supplied value — use when the host
/// app computes its own hardware fingerprint.
class StaticFingerprintProvider implements FingerprintProvider {
  const StaticFingerprintProvider(this.value);

  /// The fixed fingerprint value.
  final String value;

  @override
  Future<String> get() async => value;
}
