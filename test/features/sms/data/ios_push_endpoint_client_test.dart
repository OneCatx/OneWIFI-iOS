import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onewifi_android/features/sms/data/ios_push_endpoint_client.dart';
import 'package:onewifi_android/features/sms/domain/remote_otp_pairing.dart';

void main() {
  final endpoint = RemoteOtpEndpoint(
    baseUrl: Uri.parse('https://gateway.test/mount'),
    token: 'test-only',
  );
  for (final body in [
    '',
    '{}',
    '{"data":{"live_activity_protocol":1,"live_activity_mode":"update_only","push_to_start_token":"old"}}',
  ]) {
    test('missing or unsafe capability receipt is refused: $body', () async {
      final client = IosPushEndpointClient(
        MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        client.register(
          endpoint: endpoint,
          deviceToken: 'aa' * 32,
          environment: 'sandbox',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  }
  test('handshake preserves mounted path and sends no start token', () async {
    late http.Request sent;
    final client = IosPushEndpointClient(
      MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'data': {
              'device_token': 'aa' * 32,
              'environment': 'sandbox',
              'live_activity_protocol': 1,
              'live_activity_mode': 'update_only',
              'push_to_start_token': '',
              'server_time': 1791648000,
              'live_activity': {
                'activity_id': '',
                'revision': 0,
                'state': 'none',
                'expires_at': 0,
              },
            },
          }),
          200,
        );
      }),
    );
    await client.register(
      endpoint: endpoint,
      deviceToken: 'aa' * 32,
      environment: 'sandbox',
    );
    expect(sent.url.path, '/mount/api/onetools/ios/push-endpoint');
    expect(jsonDecode(sent.body), {
      'device_token': 'aa' * 32,
      'environment': 'sandbox',
      'live_activity_mode': 'update_only',
    });
  });
}
