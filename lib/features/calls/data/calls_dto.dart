part of 'calls_api.dart';

final class CallsDtoException implements DtoShapeException {
  const CallsDtoException();
}

const _shape = JsonShape(CallsDtoException.new);

List<VoiceCall> _parseCalls(Object? data, String deviceId) {
  final map = _shape.map(data);
  final list = map['calls'] ?? data;
  return List<VoiceCall>.unmodifiable(
    _shape.list(list).map((item) => _parseCall(item, deviceId)),
  );
}

VoiceCall _parseCall(Object? value, String deviceId) {
  final map = _shape.map(value);
  return VoiceCall(
    id: _shape.nonEmptyString(map['id']),
    deviceId: deviceId,
    number: _shape.optionalString(map['number']).isEmpty
        ? _shape.optionalString(map['peer'])
        : _shape.optionalString(map['number']),
    direction: _parseDirection(map['direction']),
    state: _parseState(map['state']),
    mediaReady: map['media_ready'] == true,
    startedAt: _parseTime(map['started_at'] ?? map['created_at']),
    endedAt: _parseTime(map['ended_at']),
  );
}

CallMediaMeta _parseMedia(Object? value) {
  final map = _shape.map(value);
  return CallMediaMeta(
    id: _shape.nonEmptyString(map['id']),
    codec: _shape.optionalString(map['codec']),
    format: _shape.optionalString(map['format']),
    stream: _shape.optionalString(map['stream']),
  );
}

CallMediaTicket _parseMediaTicket(Object? value) {
  final map = _shape.map(value);
  return CallMediaTicket(
    ticket: _shape.nonEmptyString(map['ticket']),
    expiresInSeconds: _shape.nonNegativeInt(map['expires_in']),
  );
}

List<CallHistoryEntry> _parseHistory(Object? data) {
  final list = data is Map<Object?, Object?> || data is Map
      ? (_shape.map(data)['calls'] ??
            _shape.map(data)['entries'] ??
            _shape.map(data)['history'] ??
            data)
      : data;
  return List<CallHistoryEntry>.unmodifiable(
    _shape.list(list).map((item) {
      final map = _shape.map(item);
      return CallHistoryEntry(
        id: _shape.nonNegativeInt(map['id']),
        callId: _shape.optionalString(map['call_id']),
        numberTail: _shape.optionalString(map['number_tail']),
        direction: _shape.optionalString(map['direction']),
        path: _shape.optionalString(map['path']),
        endedAt: _parseTime(map['ended_at']),
      );
    }),
  );
}

CallMediaCapabilities _parseMediaCapabilities(Object? value) {
  final map = _shape.map(value);
  final webrtc = map['webrtc'] is Map
      ? _shape.map(map['webrtc'])
      : const <String, Object?>{};
  final websocket = map['websocket'] is Map
      ? _shape.map(map['websocket'])
      : const <String, Object?>{};
  final codecsRaw = webrtc['codecs'];
  final codecs = codecsRaw == null
      ? const <String>[]
      : List<String>.unmodifiable(
          _shape.list(codecsRaw).map(_shape.optionalString),
        );
  return CallMediaCapabilities(
    preferred: _shape.optionalString(map['preferred']),
    webrtcEnabled: webrtc['enabled'] == true,
    websocketEnabled: websocket['enabled'] != false,
    webrtcUdpPort: _shape.nonNegativeInt(webrtc['udp_port']),
    webrtcIceTcp: webrtc['ice_tcp'] == true,
    webrtcCodecs: codecs,
    webrtcLastError: _shape.optionalString(webrtc['last_error']),
    websocketFormat: _shape.optionalString(websocket['format']),
  );
}

CallDirection _parseDirection(Object? value) {
  final raw = _shape.optionalString(value).toLowerCase();
  return switch (raw) {
    'incoming' => CallDirection.incoming,
    'outgoing' => CallDirection.outgoing,
    _ => CallDirection.unknown,
  };
}

CallLifecycle _parseState(Object? value) {
  final raw = _shape.optionalString(value).toLowerCase();
  return switch (raw) {
    'ringing' => CallLifecycle.ringing,
    'answering' => CallLifecycle.answering,
    'early_media' => CallLifecycle.earlyMedia,
    'dialing' => CallLifecycle.dialing,
    'active' => CallLifecycle.active,
    'ended' => CallLifecycle.ended,
    'failed' => CallLifecycle.failed,
    _ => CallLifecycle.unknown,
  };
}

DateTime? _parseTime(Object? value) {
  final raw = _shape.optionalString(value);
  if (raw.isEmpty || raw.startsWith('0001-')) return null;
  return DateTime.tryParse(raw)?.toLocal();
}
