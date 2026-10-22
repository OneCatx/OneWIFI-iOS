import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/calls/data/call_push_registrar.dart';
import 'package:onewifi_android/features/calls/data/ios_call_push.dart';

import '../../../support/fakes.dart';

/// PushKit 令牌是 32 字节，也就是 64 个十六进制字符。
String _pairs(String pair) => List<String>.filled(32, pair).join();

void main() {
  test('VoIP 令牌带会话 Bearer 登记到 /api/calls/push', () async {
    final client = FakeClient(
      (_) async => http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'data': {
                'registered': true,
                'environment': 'production',
                'voipTopic': 'Wifi.call.one.voip',
              },
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final transport = HttpTransport(
      client: client,
      originProvider: () async => Uri.parse('https://gateway.example.test'),
      tokenProvider: (_) async => 'session-token',
    );
    final token = CallPushToken(
      deviceToken: _pairs('0f'),
      environment: 'production',
    );

    await GatewayCallPushRegistrar(transport).register(token);

    final request = client.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/calls/push');
    expect(request.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(utf8.decode(await request.finalize().toBytes())), {
      'device_token': token.deviceToken,
      'environment': 'production',
    });
  });

  test('网关拒绝登记时抛错，由绑定决定重试', () async {
    final client = FakeClient(
      (_) async => http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'error': {
                'code': 'invalid_environment',
                'message': 'environment must be sandbox or production',
              },
            }),
          ),
        ),
        400,
        headers: {'content-type': 'application/json'},
      ),
    );
    final transport = HttpTransport(
      client: client,
      originProvider: () async => Uri.parse('https://gateway.example.test'),
      tokenProvider: (_) async => 'session-token',
    );

    await expectLater(
      GatewayCallPushRegistrar(transport).register(
        CallPushToken(deviceToken: _pairs('0f'), environment: 'sandbox'),
      ),
      throwsA(isA<ApiFailure>()),
    );
  });
}