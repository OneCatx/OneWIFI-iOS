import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/remote_otp_pairing.dart';
import 'otp_activity_bridge.dart';
import 'remote_otp_stream_client.dart';

final class IosPushEndpointClient {
  IosPushEndpointClient(this._client);

  final http.Client _client;

  Future<void> registerOrdinary({
    required RemoteOtpEndpoint endpoint,
    required String deviceToken,
    required String environment,
  }) async {
    await _send(
      method: 'PUT',
      uri: endpoint.pushEndpointUrl,
      token: endpoint.token,
      body: {'device_token': deviceToken, 'environment': environment},
    );
  }

  Future<IosActivityReceipt> registerActivity({
    required RemoteOtpEndpoint endpoint,
    required String deviceToken,
    required String environment,
    required String expectedActivityId,
    required OtpActivitySnapshot activity,
  }) async {
    final data = await _send(
      method: 'PUT',
      uri: endpoint.pushEndpointUrl.replace(
        path: '${endpoint.pushEndpointUrl.path}/live-activity',
      ),
      token: endpoint.token,
      body: {
        'device_token': deviceToken,
        'environment': environment,
        'expected_activity_id': expectedActivityId,
        ...activity.payload,
      },
    );
    return IosActivityReceipt.parse(data);
  }

  Future<IosActivityReceipt> register({
    required RemoteOtpEndpoint endpoint,
    required String deviceToken,
    required String environment,
  }) async {
    final data = await _send(
      method: 'PUT',
      uri: endpoint.pushEndpointUrl,
      token: endpoint.token,
      body: <String, Object>{
        'device_token': deviceToken,
        'environment': environment,
        'live_activity_mode': 'update_only',
      },
    );
    return IosActivityReceipt.parse(data, requireClearedStart: true);
  }

  Future<void> acknowledge({
    required RemoteOtpEndpoint endpoint,
    required String deviceToken,
    required int smsId,
  }) async {
    await _send(
      method: 'POST',
      uri: endpoint.pushAckUrl,
      token: endpoint.token,
      body: <String, Object>{'device_token': deviceToken, 'sms_id': smsId},
    );
  }

  Future<Map<String, dynamic>> _send({
    required String method,
    required Uri uri,
    required String token,
    required Map<String, Object> body,
  }) async {
    final response = await _client
        .send(
          http.Request(method, uri)
            ..headers.addAll(<String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            })
            ..body = jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    final text = await response.stream.bytesToString().timeout(
      const Duration(seconds: 10),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const RemoteOtpUnauthorized();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var modeUnsupported = false;
      try {
        final decoded = jsonDecode(text);
        final error = decoded is Map ? decoded['error'] : null;
        modeUnsupported =
            response.statusCode == 400 &&
            error is Map &&
            error['code'] == 'invalid_request' &&
            error['message'] == 'json: unknown field "live_activity_mode"';
      } on FormatException {
        /* Unknown failure responses never select fallback. */
      }
      throw IosPushRequestException(
        response.statusCode,
        modeUnsupported: modeUnsupported,
      );
    }
    if (text.isEmpty) return {};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> &&
            decoded['data'] is Map<String, dynamic>
        ? decoded['data'] as Map<String, dynamic>
        : {};
  }
}

final class IosPushRequestException implements Exception {
  const IosPushRequestException(
    this.statusCode, {
    this.modeUnsupported = false,
  });
  final int statusCode;
  final bool modeUnsupported;
  @override
  String toString() => 'iOS 推送端点请求失败 HTTP $statusCode。';
}

final class IosActivityReceipt {
  const IosActivityReceipt({
    required this.activityId,
    required this.revision,
    required this.state,
    required this.expiresAt,
    required this.serverTime,
  });
  final String activityId, state;
  final int revision, expiresAt, serverTime;

  static IosActivityReceipt parse(
    Map<String, dynamic> data, {
    bool requireClearedStart = false,
  }) {
    final slot = data['live_activity'];
    if (data['live_activity_protocol'] != 1 ||
        data['live_activity_mode'] != 'update_only' ||
        (requireClearedStart && data['push_to_start_token'] != '') ||
        data['server_time'] is! int ||
        slot is! Map ||
        slot['activity_id'] is! String ||
        slot['revision'] is! int ||
        slot['expires_at'] is! int ||
        !{
          'none',
          'active',
          'ended',
          'dismissed',
          'expired',
          'invalid_token',
        }.contains(slot['state'])) {
      throw const FormatException('网关需升级，接收活动未就绪。');
    }
    return IosActivityReceipt(
      activityId: slot['activity_id'] as String,
      revision: slot['revision'] as int,
      state: slot['state'] as String,
      expiresAt: slot['expires_at'] as int,
      serverTime: data['server_time'] as int,
    );
  }
}
