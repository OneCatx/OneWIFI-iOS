/// eSIM 用户告警规则（流量告警 / 到期提醒）。
/// WEB：`/api/devices/{id}/esim/user-notifications`。
enum EsimNotificationType {
  trafficThreshold('traffic_threshold'),
  expiryReminder('expiry_reminder');

  const EsimNotificationType(this.value);
  final String value;

  static EsimNotificationType parse(String value) {
    return switch (value) {
      'traffic_threshold' => trafficThreshold,
      'expiry_reminder' => expiryReminder,
      _ => throw FormatException('Unknown notification type: $value'),
    };
  }

  String get displayName => switch (this) {
    trafficThreshold => '流量阈值告警',
    expiryReminder => '到期提醒',
  };
}

/// 流量阈值（80% / 90% / 100%）
enum TrafficThreshold {
  percent80(0.8, '80%'),
  percent90(0.9, '90%'),
  percent100(1.0, '100%');

  const TrafficThreshold(this.value, this.displayName);
  final double value;
  final String displayName;

  static TrafficThreshold fromValue(double value) {
    return switch (value) {
      0.8 => percent80,
      0.9 => percent90,
      1.0 => percent100,
      _ => throw FormatException('Invalid threshold: $value'),
    };
  }
}

/// 到期提前天数（7天 / 3天 / 1天）
enum ExpiryDays {
  days7(7, '7天前'),
  days3(3, '3天前'),
  days1(1, '1天前');

  const ExpiryDays(this.value, this.displayName);
  final int value;
  final String displayName;

  static ExpiryDays fromValue(int value) {
    return switch (value) {
      7 => days7,
      3 => days3,
      1 => days1,
      _ => throw FormatException('Invalid expiry days: $value'),
    };
  }
}

final class EsimNotification {
  const EsimNotification({
    required this.id,
    required this.type,
    this.threshold,
    this.daysBeforeExpiry,
    this.enabled = true,
  });

  final String id;
  final EsimNotificationType type;
  final TrafficThreshold? threshold;
  final ExpiryDays? daysBeforeExpiry;
  final bool enabled;

  String get displayTitle => switch (type) {
    EsimNotificationType.trafficThreshold =>
      '流量达到 ${threshold?.displayName ?? "?"}',
    EsimNotificationType.expiryReminder =>
      '到期前 ${daysBeforeExpiry?.displayName ?? "?"}',
  };

  String get displaySubtitle => type.displayName;

  EsimNotification copyWith({
    String? id,
    EsimNotificationType? type,
    TrafficThreshold? threshold,
    ExpiryDays? daysBeforeExpiry,
    bool? enabled,
  }) {
    return EsimNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      threshold: threshold ?? this.threshold,
      daysBeforeExpiry: daysBeforeExpiry ?? this.daysBeforeExpiry,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  String toString() =>
    'EsimNotification(id: $id, type: ${type.value}, enabled: $enabled)';
}
