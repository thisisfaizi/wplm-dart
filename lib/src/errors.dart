/// Typed error hierarchy for the WPLM SDK.
///
/// Every server error `code` maps to a concrete subtype via [WplmError.fromCode]
/// so callers can branch with `on WplmRevoked` / `on WplmLimitExceeded` etc.
library;

import 'package:meta/meta.dart';

/// Base class for all errors thrown by the SDK.
@immutable
sealed class WplmError implements Exception {
  const WplmError(this.message, {this.code, this.status});

  /// Human-readable description.
  final String message;

  /// The server error code, when the error originated from the API.
  final String? code;

  /// The HTTP status code, when applicable.
  final int? status;

  @override
  String toString() => 'WplmError(${code ?? runtimeType}): $message';

  /// Map a server error [code] + [message]/[status] to a concrete error type.
  static WplmError fromCode(String code, String message, {int? status}) {
    switch (code) {
      case 'license_not_found':
      case 'wplm_not_found':
        return WplmNotFound(message, code: code, status: status);
      case 'expired':
      case 'license_expired':
        return WplmExpired(message, code: code, status: status);
      case 'license_suspended':
        return WplmSuspended(message, code: code, status: status);
      case 'license_revoked':
        return WplmRevoked(message, code: code, status: status);
      case 'license_terminated':
        return WplmTerminated(message, code: code, status: status);
      case 'machine_limit_exceeded':
        return WplmLimitExceeded(message, code: code, status: status);
      case 'blacklisted':
        return WplmBlacklisted(message, code: code, status: status);
      case 'license_pending':
      case 'license_not_active':
        return WplmNotActive(message, code: code, status: status);
      case 'machine_not_found':
      case 'machine_inactive':
        return WplmMachineNotFound(message, code: code, status: status);
      default:
        return WplmApiError(message, code: code, status: status);
    }
  }
}

/// The license/key was not found.
class WplmNotFound extends WplmError {
  const WplmNotFound(super.message, {super.code, super.status});
}

/// The license is past its expiry (plus any grace period).
class WplmExpired extends WplmError {
  const WplmExpired(super.message, {super.code, super.status});
}

/// The license is temporarily suspended.
class WplmSuspended extends WplmError {
  const WplmSuspended(super.message, {super.code, super.status});
}

/// The license has been revoked.
class WplmRevoked extends WplmError {
  const WplmRevoked(super.message, {super.code, super.status});
}

/// The license has been permanently terminated.
class WplmTerminated extends WplmError {
  const WplmTerminated(super.message, {super.code, super.status});
}

/// No activation seats are available under the license's overage strategy.
class WplmLimitExceeded extends WplmError {
  const WplmLimitExceeded(super.message, {super.code, super.status});
}

/// The key, fingerprint, or IP is on a deny list.
class WplmBlacklisted extends WplmError {
  const WplmBlacklisted(super.message, {super.code, super.status});
}

/// The license is not yet active (pending first payment/delivery).
class WplmNotActive extends WplmError {
  const WplmNotActive(super.message, {super.code, super.status});
}

/// The device/machine was not found or is inactive.
class WplmMachineNotFound extends WplmError {
  const WplmMachineNotFound(super.message, {super.code, super.status});
}

/// A generic API error that did not map to a more specific type.
class WplmApiError extends WplmError {
  const WplmApiError(super.message, {super.code, super.status});
}

/// The network request failed (offline, timeout, DNS, TLS…).
class WplmNetworkError extends WplmError {
  const WplmNetworkError(super.message, {this.cause});

  /// The underlying error, when available.
  final Object? cause;
}

/// A signed payload or CRL failed Ed25519 verification (tampered or wrong key).
class WplmSignatureInvalid extends WplmError {
  const WplmSignatureInvalid(super.message);
}

/// The SDK was misconfigured (e.g. missing license key or base URL).
class WplmConfigError extends WplmError {
  const WplmConfigError(super.message);
}
