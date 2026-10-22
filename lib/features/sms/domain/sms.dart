abstract interface class SmsContactTarget {}

abstract interface class SmsThreadCursor {}

enum SmsDirection { inbound, outbound }

enum SmsSendOutcome { delivered, acceptedUnconfirmed, partial, failed }

final class SmsContact {
  const SmsContact({
    required this.peerDisplay,
    required this.localPhoneDisplay,
    required this.iccidDisplay,
    required this.deviceName,
    required this.preview,
    required this.messageCount,
    required this.unreadCount,
    required this.lastTimestamp,
    required this.target,
    this.inboxKey = '',
    this.direction = SmsDirection.inbound,
    this.lastSmsId,
  });

  final String peerDisplay;
  final String localPhoneDisplay;
  final String iccidDisplay;
  final String deviceName;
  final String preview;
  final int messageCount;
  final int unreadCount;
  final DateTime? lastTimestamp;
  final SmsContactTarget target;
  final SmsDirection direction;

  /// Server message identity. Null only for older gateways/legacy fixtures.
  final int? lastSmsId;

  /// 监视用的不透明键；[toString] 不得带出号码。空时退回展示字段拼接。
  final String inboxKey;

  String get watchKey => inboxKey.isNotEmpty
      ? inboxKey
      : '$deviceName\u001f$peerDisplay\u001f$iccidDisplay\u001f$localPhoneDisplay';

  @override
  String toString() =>
      'SmsContact(deviceName: $deviceName, messageCount: $messageCount)';
}

final class SmsMessage {
  const SmsMessage({
    required this.stableId,
    required this.numericId,
    required this.senderDisplay,
    required this.body,
    required this.direction,
    required this.timestamp,
  });

  final String stableId;
  final int numericId;
  final String senderDisplay;
  final String body;
  final SmsDirection direction;
  final DateTime? timestamp;

  @override
  String toString() =>
      'SmsMessage(id: $numericId, direction: ${direction.name})';
}

final class SmsThreadPage {
  SmsThreadPage({
    required List<SmsMessage> messages,
    required this.hasMore,
    this.nextCursor,
  }) : messages = List<SmsMessage>.unmodifiable(messages);

  final List<SmsMessage> messages;
  final SmsThreadCursor? nextCursor;
  final bool hasMore;
}

final class SmsThread {
  SmsThread({
    required List<SmsMessage> messages,
    required this.hasMore,
    this.nextCursor,
  }) : messages = List<SmsMessage>.unmodifiable(messages);

  final List<SmsMessage> messages;
  final SmsThreadCursor? nextCursor;
  final bool hasMore;
}

final class SmsSendResult {
  const SmsSendResult({
    required this.outcome,
    required this.partsTotal,
    required this.partsAccepted,
    required this.retrySafe,
  });

  final SmsSendOutcome outcome;
  final int partsTotal;
  final int partsAccepted;
  final bool retrySafe;
}

final class SmsOtpHit {
  const SmsOtpHit({
    required this.code,
    required this.senderDisplay,
    required this.deviceName,
  });

  final String code;
  final String senderDisplay;
  final String deviceName;
}

final class SmsRemoteMessage {
  const SmsRemoteMessage({
    required this.content,
    required this.senderDisplay,
    required this.deviceName,
  });

  final String content;
  final String senderDisplay;
  final String deviceName;
}

abstract interface class SmsMessageDeliverySink {
  Future<bool> deliverMessage(SmsRemoteMessage message);
}

/// Live Activity presentation does not imply notification delivery.
abstract interface class SmsOtpActivitySink implements SmsOtpSink {
  Future<bool> showActivity(SmsOtpHit hit);
}

abstract interface class SmsOtpSink {
  Future<void> present(SmsOtpHit hit);
}

/// Optional delivery acknowledgement/cancellation, without breaking simple sinks.
abstract interface class SmsOtpDeliverySink implements SmsOtpSink {
  /// False is an explicit refusal, not a retryable transport failure.
  Future<bool> deliver(SmsOtpHit hit);
  Future<void> cancelPending();
}
