import 'package:meta/meta.dart';

/// A WPLM license, as returned by the server's `/validate` endpoint.
@immutable
class License {
  const License({
    required this.id,
    required this.status,
    required this.statusLabel,
    required this.activationCount,
    required this.isFloating,
    required this.overageStrategy,
    required this.graceDays,
    required this.source,
    this.productId,
    this.orderId,
    this.userId,
    this.maxActivations,
    this.validForDays,
    this.activatedAt,
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Build a [License] from the server JSON object.
  factory License.fromJson(Map<String, dynamic> json) {
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    DateTime? asDate(Object? v) =>
        (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

    return License(
      id: asInt(json['id']) ?? 0,
      productId: asInt(json['product_id']),
      orderId: asInt(json['order_id']),
      userId: asInt(json['user_id']),
      status: asInt(json['status']) ?? 0,
      statusLabel: (json['status_label'] as String?) ?? '',
      maxActivations: asInt(json['max_activations']),
      activationCount: asInt(json['activation_count']) ?? 0,
      isFloating: json['is_floating'] == true || json['is_floating'] == 1,
      overageStrategy: (json['overage_strategy'] as String?) ?? 'deny',
      validForDays: asInt(json['valid_for_days']),
      activatedAt: asDate(json['activated_at']),
      expiresAt: asDate(json['expires_at']),
      graceDays: asInt(json['grace_days']) ?? 0,
      source: asInt(json['source']) ?? 0,
      createdAt: asDate(json['created_at']),
      updatedAt: asDate(json['updated_at']),
    );
  }

  /// Primary key.
  final int id;

  /// WooCommerce product id, if any.
  final int? productId;

  /// WooCommerce order id, if any.
  final int? orderId;

  /// Owning WordPress user id, if any.
  final int? userId;

  /// Numeric status: 0 pending, 1 active, 2 inactive, 3 expired, 4 suspended,
  /// 5 revoked, 6 terminated.
  final int status;

  /// Human-readable status label from the server.
  final String statusLabel;

  /// Allowed device seats (null = unlimited).
  final int? maxActivations;

  /// Current active device count.
  final int activationCount;

  /// Whether this is a floating / concurrent license.
  final bool isFloating;

  /// `deny` | `allow_1_25x` | `allow_2x`.
  final String overageStrategy;

  /// Relative expiry in days from first activation, if set.
  final int? validForDays;

  /// First activation timestamp.
  final DateTime? activatedAt;

  /// Absolute expiry (null = perpetual).
  final DateTime? expiresAt;

  /// Days of grace after expiry.
  final int graceDays;

  /// 0 import, 1 generator, 2 api, 3 woocommerce.
  final int source;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last-modified timestamp.
  final DateTime? updatedAt;

  /// Whether the status code is `1` (active).
  bool get isActive => status == 1;
}
