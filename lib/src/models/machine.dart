import 'package:meta/meta.dart';

/// A device/machine bound to a license, as returned by `/activate` and
/// `/heartbeat`.
@immutable
class Machine {
  const Machine({
    required this.id,
    required this.licenseId,
    required this.fingerprint,
    required this.status,
    this.name,
    this.hostname,
    this.platform,
    this.appVersion,
    this.leaseExpiresAt,
    this.lastHeartbeatAt,
    this.activatedAt,
  });

  /// Build a [Machine] from the server JSON object.
  factory Machine.fromJson(Map<String, dynamic> json) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    DateTime? asDate(Object? v) =>
        (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

    return Machine(
      id: asInt(json['id']) ?? 0,
      licenseId: asInt(json['license_id']) ?? 0,
      fingerprint: (json['fingerprint'] as String?) ?? '',
      name: json['name'] as String?,
      hostname: json['hostname'] as String?,
      platform: json['platform'] as String?,
      appVersion: json['app_version'] as String?,
      leaseExpiresAt: asDate(json['lease_expires_at']),
      lastHeartbeatAt: asDate(json['last_heartbeat_at']),
      status: asInt(json['status']) ?? 1,
      activatedAt: asDate(json['activated_at']),
    );
  }

  /// Primary key.
  final int id;

  /// Owning license id.
  final int licenseId;

  /// The (server-hashed) device fingerprint.
  final String fingerprint;

  /// Friendly device name.
  final String? name;

  /// Reported hostname.
  final String? hostname;

  /// OS / platform string.
  final String? platform;

  /// Client app version at activation.
  final String? appVersion;

  /// Floating lease expiry, if any.
  final DateTime? leaseExpiresAt;

  /// Last successful heartbeat.
  final DateTime? lastHeartbeatAt;

  /// 1 active, 2 deactivated, 3 revoked.
  final int status;

  /// Activation timestamp.
  final DateTime? activatedAt;

  /// Whether the device is currently active.
  bool get isActive => status == 1;
}
