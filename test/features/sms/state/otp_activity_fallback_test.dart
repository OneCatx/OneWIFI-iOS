import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onewifi_android/features/sms/data/ios_push_endpoint_client.dart';
import 'package:onewifi_android/features/sms/data/otp_activity_bridge.dart';
import 'package:onewifi_android/features/sms/domain/remote_otp_pairing.dart';
import 'package:onewifi_android/features/sms/state/otp_activity_binding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final endpoint = RemoteOtpEndpoint(
    baseUrl: Uri.parse('https://gateway.test/mount'),
    token: 'test-token',
  );
  const channel = MethodChannel('test/ordinary-fallback');
  final unsupported = jsonEncode({
    'error': {
      'code': 'invalid_request',
      'message': 'json: unknown field "live_activity_mode"',
    },
  });
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<Map<String, dynamic>> requests;
  late List<String> nativeCalls;
  late OtpActivityBinding binding;
  setUp(() {
    requests = [];
    nativeCalls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      return null;
    });
  });
  tearDown(() {
    binding.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  void create(
    Future<http.Response> Function(http.Request, Map<String, dynamic>) handler,
  ) {
    binding = OtpActivityBinding(
      client: IosPushEndpointClient(
        MockClient((request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          return handler(request, body);
        }),
      ),
      native: OtpActivityBridge(channel: channel),
    );
  }

  for (final missingAck in [false, true]) {
    test(
      'ordinary registration survives ${missingAck ? 'missing ACK' : 'unsupported mode 400'} and token rotation',
      () async {
        create(
          (request, body) async => body.containsKey('live_activity_mode')
              ? http.Response(
                  missingAck ? '{}' : unsupported,
                  missingAck ? 200 : 400,
                )
              : http.Response('', 204),
        );
        await binding.configure(endpoint, 'aa' * 32, 'sandbox');
        await binding.configure(endpoint, 'bb' * 32, 'sandbox');
        final ordinary = requests
            .where((body) => !body.containsKey('live_activity_mode'))
            .toList();
        expect(ordinary, [
          {'device_token': 'aa' * 32, 'environment': 'sandbox'},
          {'device_token': 'bb' * 32, 'environment': 'sandbox'},
        ]);
        expect(
          requests.every((body) => !body.containsKey('push_to_start_token')),
          isTrue,
        );
        expect(nativeCalls, isEmpty);
        expect(binding.readiness, OtpActivityReadiness.upgradeRequired);
      },
    );
  }
  for (final status in [401, 403, 500, 400]) {
    test(
      'HTTP $status unrelated to mode does not attempt ordinary fallback',
      () async {
        create(
          (_, _) async =>
              http.Response('{"error":"invalid_device_token"}', status),
        );
        await binding.configure(endpoint, 'aa' * 32, 'sandbox');
        expect(requests, hasLength(1));
        expect(nativeCalls, isEmpty);
        expect(binding.readiness, isNot(OtpActivityReadiness.ready));
      },
    );
  }
  for (final status in [401, 503]) {
    test(
      'ordinary fallback HTTP $status cannot claim compact readiness',
      () async {
        create(
          (_, body) async => http.Response(
            body.containsKey('live_activity_mode') ? unsupported : '{}',
            body.containsKey('live_activity_mode') ? 400 : status,
          ),
        );
        await binding.configure(endpoint, 'aa' * 32, 'sandbox');
        expect(requests, hasLength(2));
        expect(nativeCalls, isEmpty);
        expect(binding.readiness, isNot(OtpActivityReadiness.ready));
      },
    );
  }
  test(
    'late unsupported result cannot fallback with replacement device identity',
    () async {
      final gate = Completer<http.Response>();
      create((_, body) async {
        if (requests.length == 1) return gate.future;
        return http.Response(
          body.containsKey('live_activity_mode') ? unsupported : '',
          body.containsKey('live_activity_mode') ? 400 : 204,
        );
      });
      final old = binding.configure(endpoint, 'aa' * 32, 'sandbox');
      await Future<void>.delayed(Duration.zero);
      final next = binding.configure(endpoint, 'bb' * 32, 'sandbox');
      gate.complete(http.Response(unsupported, 400));
      await Future.wait([old, next]);
      final ordinary = requests
          .where((body) => !body.containsKey('live_activity_mode'))
          .toList();
      expect(ordinary, [
        {'device_token': 'bb' * 32, 'environment': 'sandbox'},
      ]);
      expect(nativeCalls, isEmpty);
    },
  );
}
