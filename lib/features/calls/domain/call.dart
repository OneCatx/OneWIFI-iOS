enum CallDirection { incoming, outgoing, unknown }

enum CallLifecycle {
  ringing,
  answering,
  earlyMedia,
  dialing,
  active,
  ended,
  failed,
  unknown,
}

final class VoiceCall {
  const VoiceCall({
    required this.id,
    required this.deviceId,
    required this.number,
    required this.direction,
    required this.state,
    this.mediaReady = false,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String deviceId;
  final String number;
  final CallDirection direction;
  final CallLifecycle state;
  final bool mediaReady;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isLive =>
      state != CallLifecycle.ended && state != CallLifecycle.failed;

  bool get isRingingIncoming =>
      direction == CallDirection.incoming && state == CallLifecycle.ringing;

  String get stateLabel => switch (state) {
    CallLifecycle.ringing => '振铃',
    CallLifecycle.answering => '接听中',
    CallLifecycle.earlyMedia => '回铃',
    CallLifecycle.dialing => '拨号中',
    CallLifecycle.active => '通话中',
    CallLifecycle.ended => '已结束',
    CallLifecycle.failed => '失败',
    CallLifecycle.unknown => state.name,
  };

  String get directionLabel => switch (direction) {
    CallDirection.incoming => '来电',
    CallDirection.outgoing => '去电',
    CallDirection.unknown => '',
  };
}

final class CallMediaMeta {
  const CallMediaMeta({
    required this.id,
    required this.codec,
    required this.format,
    required this.stream,
  });

  final String id;
  final String codec;
  final String format;
  final String stream;
}

final class CallMediaTicket {
  const CallMediaTicket({
    required this.ticket,
    required this.expiresInSeconds,
  });

  final String ticket;
  final int expiresInSeconds;
}

final class CallHistoryEntry {
  const CallHistoryEntry({
    required this.id,
    required this.callId,
    required this.numberTail,
    required this.direction,
    required this.path,
    this.endedAt,
  });

  final int id;
  final String callId;
  final String numberTail;
  final String direction;
  final String path;
  final DateTime? endedAt;
}

final class CallMediaCapabilities {
  const CallMediaCapabilities({
    required this.preferred,
    required this.webrtcEnabled,
    required this.websocketEnabled,
    this.webrtcUdpPort = 0,
    this.webrtcIceTcp = false,
    this.webrtcCodecs = const <String>[],
    this.webrtcLastError = '',
    this.websocketFormat = '',
  });

  final String preferred;
  final bool webrtcEnabled;
  final bool websocketEnabled;
  final int webrtcUdpPort;
  final bool webrtcIceTcp;
  final List<String> webrtcCodecs;
  final String webrtcLastError;
  final String websocketFormat;
}

String normalizeDialNumber(String value) => value.trim();

bool validDialNumber(String value) {
  final number = normalizeDialNumber(value);
  if (number.length < 2 || number.length > 32) return false;
  return RegExp(r'^\+?[0-9*#]+$').hasMatch(number);
}

String appendDialKey(String current, String key) {
  if (!RegExp(r'^[0-9*#+]$').hasMatch(key)) {
    return normalizeDialNumber(current);
  }
  final number = normalizeDialNumber(current);
  if (key == '+' && number.isNotEmpty) return number;
  final next = '$number$key';
  if (next.length > 32) return number;
  if (!RegExp(r'^\+?[0-9*#]*$').hasMatch(next)) return number;
  return next;
}

String backspaceDial(String current) {
  final number = normalizeDialNumber(current);
  if (number.isEmpty) return '';
  return number.substring(0, number.length - 1);
}
