part of 'sms_api.dart';

SmsContactDto _parseContact(Object? value) {
  final map = _shape.map(value);
  final peer = _shape.trimmedNonEmptyString(map['peer']);
  final deviceId = _shape.trimmedNonEmptyString(map['device_id']);
  final localPhone = _shape.string(map['local_phone']).trim();
  final iccid = _shape.string(map['iccid']).trim();
  final imsi = _shape.string(map['imsi']).trim();
  final lastTimestamp = _parseTimestamp(map['last_timestamp']);
  return SmsContactDto(
    peerDisplay: Redaction.maskTail4(peer),
    localPhoneDisplay: localPhone.isEmpty
        ? ''
        : Redaction.maskTail4(localPhone),
    iccidDisplay: iccid.isEmpty ? '' : Redaction.maskTail4(iccid),
    deviceName: _shape.string(map['device_name']).trim(),
    preview: _displayBody(_shape.string(map['last_content'])),
    messageCount: _shape.nonNegativeInt(map['message_count']),
    unreadCount: _shape.nonNegativeInt(map['unread_count']),
    lastTimestamp: lastTimestamp,
    target: _SmsContactTarget(deviceId, peer, iccid, imsi),
    inboxKey: 'k${Object.hash(deviceId, peer, iccid, imsi)}',
    direction: map['direction'] == null
        ? SmsDirection.inbound
        : _parseDirection(map['direction']),
    lastSmsId: map['last_sms_id'] == null
        ? null
        : _shape.positiveInt(map['last_sms_id']),
  );
}

SmsMessage _parseMessage(Object? value) {
  final map = _shape.map(value);
  final numericId = _shape.positiveInt(map['id']);
  final peer = _shape.trimmedNonEmptyString(map['peer']);
  final direction = _parseDirection(map['direction']);
  return SmsMessage(
    stableId: _shape.trimmedNonEmptyString(map['message_id']),
    numericId: numericId,
    senderDisplay: direction == SmsDirection.outbound
        ? '我'
        : Redaction.maskTail4(peer),
    body: _displayBody(_shape.string(map['content'])),
    direction: direction,
    timestamp: _parseTimestamp(map['timestamp']),
  );
}

final class SmsContactDto {
  const SmsContactDto({
    required this.peerDisplay,
    required this.localPhoneDisplay,
    required this.iccidDisplay,
    required this.deviceName,
    required this.preview,
    required this.messageCount,
    required this.unreadCount,
    required this.lastTimestamp,
    required this.target,
    required this.inboxKey,
    required this.direction,
    required this.lastSmsId,
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
  final String inboxKey;
  final SmsDirection direction;
  final int? lastSmsId;

  @override
  String toString() =>
      'SmsContactDto(deviceName: $deviceName, messageCount: $messageCount)';
}

final class _SmsContactTarget implements SmsContactTarget {
  const _SmsContactTarget(this._deviceId, this._peer, this._iccid, this._imsi);

  final String _deviceId;
  final String _peer;
  final String _iccid;
  final String _imsi;

  @override
  String toString() => 'SmsContactTarget(redacted)';
}

final class _SmsThreadCursor implements SmsThreadCursor {
  const _SmsThreadCursor(this._beforeId);
  final int _beforeId;

  @override
  String toString() => 'SmsThreadCursor(redacted)';
}

final class SmsDtoException implements DtoShapeException {
  const SmsDtoException();
}

const _shape = JsonShape(SmsDtoException.new);

SmsDirection _parseDirection(Object? value) =>
    switch (_shape.string(value).toLowerCase()) {
      'outbound' || 'out' || 'sent' || 'send' => SmsDirection.outbound,
      'inbound' || 'in' || 'received' => SmsDirection.inbound,
      _ => throw const SmsDtoException(),
    };

DateTime? _parseTimestamp(Object? value) {
  if (value == null || value == '') return null;
  if (value is int && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch(
      value < 1000000000000 ? value * 1000 : value,
      isUtc: true,
    );
  }
  return _shape.dateTime(value).toLocal();
}

String _displayBody(String value) {
  final text = value.trim();
  final hexDump =
      text.length >= 16 &&
      text.length.isEven &&
      RegExp(r'^[0-9A-Fa-f]+$').hasMatch(text) &&
      RegExp(r'[A-Fa-f]').hasMatch(text);
  return hexDump ? '收到一条系统短信' : text;
}
