import '../domain/esim_notification.dart';

final class EsimNotificationDto {
  const EsimNotificationDto({
    required this.id,
    required this.deviceId,
    required this.type,
    this.threshold,
    this.daysBeforeExpiry,
    required this.enabled,
    this.createdAt,
  });

  final String id;
  final String deviceId;
  final String type;
  final double? threshold;
  final int? daysBeforeExpiry;
  final bool enabled;
  final DateTime? createdAt;

  factory EsimNotificationDto.fromDomain(
    EsimNotification notification,
    String deviceId,
  ) {
    return EsimNotificationDto(
      id: notification.id,
      deviceId: deviceId,
      type: notification.type.value,
      threshold: notification.threshold?.value,
      daysBeforeExpiry: notification.daysBeforeExpiry?.value,
      enabled: notification.enabled,
      createdAt: null,
    );
  }

  /// 从后端 JSON 解析（snake_case 字段名）
  factory EsimNotificationDto.fromBackendJson(Map<String, Object?> json) {
    return EsimNotificationDto(
      id: json['id'] as String,
      deviceId: json['device_id'] as String,
      type: json['type'] as String,
      threshold: (json['threshold'] as num?)?.toDouble(),
      daysBeforeExpiry: json['days_before_expiry'] as int?,
      enabled: json['enabled'] as bool,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  /// 从本地存储 JSON 解析（camelCase 字段名，兼容旧数据）
  factory EsimNotificationDto.fromLocalJson(Map<String, Object?> json) {
    return EsimNotificationDto(
      id: json['id'] as String,
      deviceId: json['deviceId'] as String? ?? '',
      type: json['type'] as String,
      threshold: (json['threshold'] as num?)?.toDouble(),
      daysBeforeExpiry: json['daysBeforeExpiry'] as int?,
      enabled: json['enabled'] as bool,
      createdAt: null,
    );
  }

  Map<String, Object?> toLocalJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'type': type,
      'threshold': threshold,
      'daysBeforeExpiry': daysBeforeExpiry,
      'enabled': enabled,
    };
  }

  EsimNotification toDomain() {
    final parsedType = EsimNotificationType.parse(type);
    TrafficThreshold? parsedThreshold;
    ExpiryDays? parsedDays;

    if (parsedType == EsimNotificationType.trafficThreshold && threshold != null) {
      parsedThreshold = TrafficThreshold.fromValue(threshold!);
    }
    if (parsedType == EsimNotificationType.expiryReminder && daysBeforeExpiry != null) {
      parsedDays = ExpiryDays.fromValue(daysBeforeExpiry!);
    }

    return EsimNotification(
      id: id,
      type: parsedType,
      threshold: parsedThreshold,
      daysBeforeExpiry: parsedDays,
      enabled: enabled,
    );
  }
}
