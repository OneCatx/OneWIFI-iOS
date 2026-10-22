import 'dart:io';

import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/call.dart';

part 'calls_dto.dart';

final class CallsApi {
  const CallsApi(this._transport, {this.socketConnector});

  final HttpTransport _transport;
  final Future<WebSocket> Function(Uri uri)? socketConnector;

  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.deviceCalls,
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
      routeTemplate: GatewayApi.deviceCallsDial,
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
      routeTemplate: GatewayApi.deviceCallsAnswer,
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
      routeTemplate: GatewayApi.deviceCallsHangup,
      pathParameters: <String, String>{'id': deviceId},
      body: <String, String>{'id': callId},
      cancellation: cancellation,
    );
  }

  /// WEB `POST �?calls/dtmf` �?prefers [digits]; single [digit] kept for legacy.
  Future<void> sendDtmf(
    String deviceId,
    String callId, {
    String? digit,
    String? digits,
    RequestCancellation? cancellation,
  }) async {
    final body = <String, String>{'id': callId};
    final multi = digits?.trim() ?? '';
    final single = digit?.trim() ?? '';
    if (multi.isNotEmpty) {
      body['digits'] = multi;
    } else if (single.isNotEmpty) {
      body['digit'] = single;
    }
    await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.deviceCallsDtmf,
      pathParameters: <String, String>{'id': deviceId},
      body: body,
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
      routeTemplate: GatewayApi.deviceCallsMedia,
      pathParameters: <String, String>{'id': deviceId},
      queryParameters: <String, String?>{'id': callId},
      cancellation: cancellation,
    );
    return _parseMedia(data);
  }

  Future<CallMediaTicket> createMediaTicket(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.deviceCallsMediaTicket,
      pathParameters: <String, String>{'id': deviceId},
      queryParameters: <String, String?>{'id': callId},
      cancellation: cancellation,
    );
    return _parseMediaTicket(data);
  }

  Future<List<CallHistoryEntry>> fetchHistory(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.deviceCallsHistory,
      pathParameters: <String, String>{'id': deviceId},
      cancellation: cancellation,
    );
    return _parseHistory(data);
  }

  Future<CallMediaCapabilities> fetchMediaCapabilities({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.callsMediaCapabilities,
      cancellation: cancellation,
    );
    return _parseMediaCapabilities(data);
  }

  /// Opens PCM media WebSocket. Prefer Bearer via access_token query
  /// (same as WEB) so the URL works with dart:io WebSocket.
  Future<WebSocket> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  }) async {
    final scheme = origin.scheme == 'https' ? 'wss' : 'ws';
    final query = <String, String>{'id': callId};
    if (accessToken != null && accessToken.isNotEmpty) {
      query['access_token'] = accessToken;
    }
    final uri = Uri(
      scheme: scheme,
      host: origin.host,
      port: origin.hasPort ? origin.port : null,
      path: '/api/devices/${Uri.encodeComponent(deviceId)}/calls/media',
      queryParameters: query,
    );
    final connector = socketConnector;
    return connector != null
        ? connector(uri)
        : WebSocket.connect(uri.toString());
  }
}
