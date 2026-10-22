import pathlib
root = pathlib.Path(r'E:\GQ\Ultra\ONEWIFI\android')

def write(rel, text):
    p = root/rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8', newline='\n')
    print('WROTE', rel)

write('lib/features/calls/domain/call.dart', r'''enum CallDirection { incoming, outgoing, unknown }

enum CallLifecycle {
  ringing,
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
''')

write('lib/features/calls/data/calls_api.dart', r'''import 'dart:convert';
import 'dart:io';

import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/call.dart';

part 'calls_dto.dart';

final class CallsApi {
  const CallsApi(this._transport);

  final HttpTransport _transport;

  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: '/api/devices/{id}/calls',
      pathParameters: <String, String>{'id': deviceId},
      cancellation: cancellation,
    );
    return _parseCalls(data, deviceId);
  }

  Future<VoiceCall> dial(
    String deviceId,
    String number, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: '/api/devices/{id}/calls/dial',
      pathParameters: <String, String>{'id': deviceId},
      body: <String, String>{'number': number},
      cancellation: cancellation,
    );
    return _parseCall(data, deviceId);
  }

  Future<VoiceCall> answer(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: '/api/devices/{id}/calls/answer',
      pathParameters: <String, String>{'id': deviceId},
      body: <String, String>{'id': callId},
      cancellation: cancellation,
    );
    return _parseCall(data, deviceId);
  }

  Future<void> hangup(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendJson(
      method: 'POST',
      routeTemplate: '/api/devices/{id}/calls/hangup',
      pathParameters: <String, String>{'id': deviceId},
      body: <String, String>{'id': callId},
      cancellation: cancellation,
    );
  }

  Future<CallMediaMeta> fetchMediaMeta(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: '/api/devices/{id}/calls/media',
      pathParameters: <String, String>{'id': deviceId},
      queryParameters: <String, String?>{'id': callId},
      cancellation: cancellation,
    );
    return _parseMedia(data);
  }

  /// Opens PCM media WebSocket. Prefer Bearer via access_token query
  /// (same as WEB) so the URL works with dart:io WebSocket.
  Future<WebSocket> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  }) async {
    final path =
        '/api/devices/${Uri.encodeComponent(deviceId)}/calls/media'
        '?id=${Uri.encodeComponent(callId)}';
    final wsScheme = origin.scheme == 'https' ? 'wss' : 'ws';
    final ws = origin.replace(scheme: wsScheme, path: '', query: '');
    final base = Uri.parse('$ws$path');
    final uri = accessToken == null || accessToken.isEmpty
        ? base
        : base.replace(
            queryParameters: <String, String>{
              ...base.queryParameters,
              'access_token': accessToken,
            },
          );
    return WebSocket.connect(uri.toString());
  }
}
''')

write('lib/features/calls/data/calls_dto.dart', r'''part of 'calls_api.dart';

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
''')

write('lib/features/calls/data/calls_repository.dart', r'''import 'dart:io';

import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/call.dart';
import 'calls_api.dart';

abstract interface class CallsRepository {
  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  });

  Future<VoiceCall> dial(
    String deviceId,
    String number, {
    RequestCancellation? cancellation,
  });

  Future<VoiceCall> answer(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  });

  Future<void> hangup(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  });

  Future<CallMediaMeta> fetchMediaMeta(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  });

  Future<WebSocket> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  });
}

final class DefaultCallsRepository implements CallsRepository {
  const DefaultCallsRepository(this._api);
  final CallsApi _api;

  @override
  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.fetchCalls(deviceId, cancellation: cancellation),
    );
  }

  @override
  Future<VoiceCall> dial(
    String deviceId,
    String number, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.dial(deviceId, number, cancellation: cancellation),
    );
  }

  @override
  Future<VoiceCall> answer(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.answer(deviceId, callId, cancellation: cancellation),
    );
  }

  @override
  Future<void> hangup(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.hangup(deviceId, callId, cancellation: cancellation),
    );
  }

  @override
  Future<CallMediaMeta> fetchMediaMeta(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.fetchMediaMeta(deviceId, callId, cancellation: cancellation),
    );
  }

  @override
  Future<WebSocket> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  }) {
    return _api.openMediaSocket(
      origin: origin,
      deviceId: deviceId,
      callId: callId,
      accessToken: accessToken,
    );
  }
}
''')

print('calls data ok')
