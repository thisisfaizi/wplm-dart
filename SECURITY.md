# Security Policy

## Reporting a vulnerability

Please report security issues privately to **security@wplm.dev** (or open a
[GitHub security advisory](https://github.com/wplm/wplm-dart/security/advisories/new)).
Do not open a public issue for security reports. We aim to acknowledge within
72 hours.

## Design guarantees

- This SDK ships **only the Ed25519 public key, product id, and server URL**.
  It never contains the signing private key or any API consumer secret.
- License payloads are verified with **Ed25519 detached signatures**; tampered
  tokens are rejected.
- Replay protection rejects signed payloads whose issue time drifts beyond a
  configurable window (default 5 minutes).
- TLS verification is enabled by default; certificate pinning is supported via a
  custom HTTP transport.
- Cached tokens are written through a pluggable secure store; secrets and
  fingerprints are never logged.
