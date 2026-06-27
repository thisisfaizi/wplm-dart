# Contributing

Thanks for your interest in improving the WPLM Dart SDK.

## Development

```bash
dart pub get
dart format --set-exit-if-changed .
dart analyze
dart test
```

All four must pass before a PR is merged; CI enforces them across the supported
Dart versions.

## Guidelines

- Keep the public API small, strongly typed, and documented.
- The core package is **pure Dart** — do not add a Flutter dependency to `lib/`.
  Platform integrations (e.g. `device_info_plus`, `flutter_secure_storage`) are
  wired by the consumer via the `FingerprintProvider` / `TokenStore` interfaces.
- Never log license keys, fingerprints, or tokens.
- Add tests for every behaviour, including offline / revoked / failure paths.
- Update `CHANGELOG.md` under "Unreleased".
