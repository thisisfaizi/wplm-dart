import 'package:meta/meta.dart';

import 'license.dart';

/// The outcome of [WplmClient.validate].
@immutable
class ValidationResult {
  const ValidationResult({
    required this.valid,
    this.code,
    this.license,
    this.signedPayload,
    this.needsActivation = false,
    this.fromCache = false,
  });

  /// Build a [ValidationResult] from the server `data` object.
  factory ValidationResult.fromJson(
    Map<String, dynamic> data, {
    bool fromCache = false,
  }) {
    final licenseJson = data['license'];
    return ValidationResult(
      valid: data['valid'] == true,
      code: data['code'] as String?,
      license: licenseJson is Map<String, dynamic>
          ? License.fromJson(licenseJson)
          : null,
      signedPayload: data['signed_payload'] as String?,
      needsActivation: data['needs_activation'] == true,
      fromCache: fromCache,
    );
  }

  /// Whether the license is currently valid and usable.
  final bool valid;

  /// The failure reason code when [valid] is false (e.g. `expired`).
  final String? code;

  /// The license details, when available.
  final License? license;

  /// The Ed25519-signed payload token, for offline verification + caching.
  final String? signedPayload;

  /// Whether the caller should activate a device next.
  final bool needsActivation;

  /// True when this result was produced offline from a cached signed payload.
  final bool fromCache;
}
