import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
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
  for (final scenario in [0, 1, 2]) {
    final delayedAck = scenario == 1;
    final switchScope = scenario == 2;
    test(
      delayedAck
          ? 'ACK crossing effective expiry cannot become ready'
          : switchScope
          ? 'old expiry cannot revoke a replacement scope'
          : 'shortened expiry revokes readiness without ending or preparing',
      () {
        fakeAsync((async) {
          final origin = DateTime.now();
          final clock = async.getClock(origin);
          final started = origin.millisecondsSinceEpoch ~/ 1000;
          var deadline = started + 5;
          final endpoint = RemoteOtpEndpoint(
            baseUrl: Uri.parse('https://gateway.test'),
            token: 'test',
          );
          const channel = MethodChannel('test/expiry-only');
          final nativeCalls = <String>[];
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(channel, (call) async {
            nativeCalls.add(call.method);
            if (call.method == 'scopeIdentifier') return 'scope-expiry';
            if (call.method == 'pendingActivityEnds') return [];
            return {
              'scope_id': 'scope-expiry',
              'activity_id': 'activity-expiry',
              'update_token': 'aabb',
              'revision': 1,
              'started_at': started,
              'expires_at': started + 28800,
              'state': 'active',
            };
          });
          final receiptGate = Completer<http.Response>();
          http.Response receipt(Map<String, dynamic> body) => http.Response(
            jsonEncode({
              'data': {
                'live_activity_protocol': 1,
                'live_activity_mode': 'update_only',
                'push_to_start_token': '',
                'server_time': clock.now().millisecondsSinceEpoch ~/ 1000,
                'live_activity': {
                  'activity_id': body['activity_id'] ?? '',
                  'revision': body['revision'] ?? 0,
                  'state': body['state'] ?? 'none',
                  'expires_at': body['activity_id'] == null ? 0 : deadline,
                },
              },
            }),
            200,
          );
          Map<String, dynamic>? pending;
          final client = IosPushEndpointClient(
            MockClient((request) async {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              if (delayedAck && body['state'] == 'active') {
                pending = body;
                return receiptGate.future;
              }
              return receipt(body);
            }),
          );
          final binding = OtpActivityBinding(
            client: client,
            native: OtpActivityBridge(channel: channel),
            now: clock.now,
          );
          var notifications = 0;
          binding.addListener(() => notifications++);
          unawaited(binding.configure(endpoint, 'aa' * 32, 'sandbox'));
          async.flushMicrotasks();
          expect(
            nativeCalls.where((v) => v == 'prepareActivity'),
            hasLength(1),
          );
          if (delayedAck) {
            async.elapse(const Duration(seconds: 6));
            receiptGate.complete(receipt(pending!));
            async.flushMicrotasks();
            expect(binding.readiness, OtpActivityReadiness.unavailable);
          } else {
            expect(binding.readiness, OtpActivityReadiness.ready);
            if (switchScope) {
              deadline = started + 10;
              unawaited(
                binding.configure(
                  RemoteOtpEndpoint(
                    baseUrl: Uri.parse('https://other.test'),
                    token: 'next-test',
                  ),
                  'aa' * 32,
                  'sandbox',
                ),
              );
              async.flushMicrotasks();
              async.elapse(const Duration(seconds: 6));
              expect(binding.readiness, OtpActivityReadiness.ready);
            }
            final before = notifications;
            async.elapse(const Duration(seconds: 6));
            expect(binding.readiness, OtpActivityReadiness.unavailable);
            expect(notifications, greaterThan(before));
          }
          expect(
            nativeCalls.where((v) => v == 'prepareActivity'),
            hasLength(switchScope ? 2 : 1),
          );
          expect(
            nativeCalls.where((v) => v == 'endActivity'),
            hasLength(switchScope ? 1 : 0),
          );
          binding.dispose();
          async.flushMicrotasks();
          expect(async.pendingTimers, isEmpty);
          messenger.setMockMethodCallHandler(channel, null);
        });
      },
    );
  }
}
