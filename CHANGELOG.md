# Changelog

All notable changes to the WPLM Dart SDK are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and
this project adheres to [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-06-28

### Added
- **Product binding.** Set `productId` and the client rejects any license whose
  signed `pid` does not match — enforced both online and offline from the
  cryptographically signed payload (`WplmProductMismatch`). Omit `productId` to
  opt out (backward compatible).
- **Keypair-rotation self-heal.** If the cached public key fails verification
  during an online `validate`, the SDK drops it, re-fetches `/public-key` once,
  and retries — so a vendor rotating the signing keypair no longer bricks clients.

## [0.1.0] - 2026-06-16

### Added
- Initial release.
- `WplmClient` with `validate`, `activate`, `deactivate`, and `heartbeat`.
- Offline Ed25519 signature verification of the license payload using the
  server's public key.
- Offline-capable validation (`validate(offlineOk: true)`) backed by a cached
  signed payload with configurable max clock drift.
- Signed CRL fetch + verification + offline revoked-key check.
- Pluggable HTTP transport (timeouts + retries with exponential backoff),
  fingerprint provider, and secure token store.
- Typed error hierarchy mapping every server error code.
