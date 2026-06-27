/// Pluggable persistent store for cached tokens (signed payload, CRL,
/// fingerprint). Inject a platform-backed implementation (e.g.
/// `flutter_secure_storage`) for at-rest protection on device.
abstract class TokenStore {
  /// Read a value, or null if absent.
  Future<String?> read(String key);

  /// Write a value.
  Future<void> write(String key, String value);

  /// Delete a value.
  Future<void> delete(String key);
}

/// Default in-memory store. Suitable for servers/CLIs and tests; for on-device
/// persistence inject a secure store implementation instead.
class InMemoryTokenStore implements TokenStore {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}
