import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/remote_otp_pairing.dart';

enum RemoteOtpEventType { connected, sms }

final class RemoteOtpEvent {
  const RemoteOtpEvent._({
    required this.type,
    this.id = 0,
    this.content = '',
    this.sender = '',
    this.device = '',
  });

  const RemoteOtpEvent.connected() : this._(type: RemoteOtpEventType.connected);

  const RemoteOtpEvent.sms({
    required int id,
    required String content,
    required String sender,
    required String device,
  }) : this._(
         type: RemoteOtpEventType.sms,
         id: id,
         content: content,
         sender: sender,
         device: device,
       );

  final RemoteOtpEventType type;
  final int id;
  final String content;
  final String sender;
  final String device;

  static RemoteOtpEvent? parseSMS(String data, {required int id}) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return null;
      final content = _value(decoded, const ['content', 'body', 'text']);
      final eventID = id > 0 ? id : _eventID(decoded);
      if (content.isEmpty || eventID <= 0) return null;
      return RemoteOtpEvent.sms(
        id: eventID,
        content: content,
        sender: _value(decoded, const ['number', 'peer', 'from']),
        device: _value(decoded, const ['deviceLabel', 'device_label']),
      );
    } on FormatException {
      return null;
    }
  }

  static int _eventID(Map<Object?, Object?> values) {
    final value = values['id'];
    if (value is int && value > 0) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _value(Map<Object?, Object?> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}

final class RemoteOtpUnauthorized implements Exception {
  const RemoteOtpUnauthorized();
}

final class RemoteOtpStreamClient {
  RemoteOtpStreamClient(this._client);

  final http.Client _client;

  Stream<RemoteOtpEvent> open(
    RemoteOtpEndpoint endpoint, {
    int lastEventId = 0,
  }) async* {
    final response = await _client.send(
      http.Request('GET', endpoint.streamUrl)
        ..headers.addAll(<String, String>{
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
          if (lastEventId > 0) 'Last-Event-ID': '$lastEventId',
          'Authorization': 'Bearer ${endpoint.token}',
        }),
    );
    if (response.statusCode == 401) {
      await response.stream.drain<void>();
      throw const RemoteOtpUnauthorized();
    }
    if (response.statusCode == 403) {
      await response.stream.drain<void>();
      throw StateError('远程短信渠道已关闭。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw StateError('远程短信连接失败 HTTP ${response.statusCode}。');
    }

    var eventName = '';
    var eventID = 0;
    final data = <String>[];
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.startsWith(':')) continue;
      if (line.isEmpty) {
        final event = _dispatch(eventName, eventID, data);
        if (event != null) yield event;
        eventName = '';
        eventID = 0;
        data.clear();
      } else if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('id:')) {
        eventID = int.tryParse(line.substring(3).trim()) ?? 0;
      } else if (line.startsWith('data:')) {
        data.add(line.substring(5).trimLeft());
      }
    }
    final event = _dispatch(eventName, eventID, data);
    if (event != null) yield event;
  }

  static RemoteOtpEvent? _dispatch(String eventName, int id, List<String> data) {
    final name = eventName.isEmpty ? 'sms' : eventName;
    if (name == 'connected') return const RemoteOtpEvent.connected();
    if (name != 'sms' && name != 'message' || data.isEmpty) return null;
    return RemoteOtpEvent.parseSMS(data.join('\n'), id: id);
  }
}