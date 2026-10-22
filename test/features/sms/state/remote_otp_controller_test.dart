import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/features/sms/data/ios_apns_bridge.dart';
import 'package:onewifi_android/features/sms/data/ios_push_endpoint_client.dart';
import 'package:onewifi_android/features/sms/data/remote_otp_pairing_store.dart';
import 'package:onewifi_android/features/sms/data/remote_otp_stream_client.dart';
import 'package:onewifi_android/features/sms/domain/remote_otp_pairing.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/state/otp_activity_binding.dart';
import 'package:onewifi_android/features/sms/state/remote_otp_controller.dart';

const _channel = MethodChannel('test/remote-otp-apns');
const _activityChannel = MethodChannel('com.oneims.onewifi/otp');
// Live Activity start tokens live in their own token space, so this one is
// deliberately a different length from the alert device token.
const _startToken = 'aabbccddeeff00112233445566778899';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness harness;

  setUp(() async {
    harness = _Harness();
    await harness.start();
  });
  tearDown(() => harness.close());

  test(
    'capability ACK prepares once and registers the exact native tuple',
    () async {
      final ready = _Harness(compatible: true);
      await ready.start();
      await ready.controller.restore();
      await ready.settle();
      expect(ready.prepares, 1);
      expect(ready.client.activities.single['activity_id'], 'activity-test');
      expect(ready.client.activities.single['update_token'], 'aabb');
      expect(ready.client.activities.single['revision'], 1);
      await ready.close();
    },
  );

  test('legacy receipt never prepares an activity', () async {
    expect(harness.prepares, 0);
    expect(
      harness.controller.activity.readiness,
      OtpActivityReadiness.upgradeRequired,
    );
  });
  test(
    'lost registration reply retries the exact tuple without a new activity',
    () async {
      final ready = _Harness(compatible: true);
      ready.client.dropActivityReplyOnce = true;
      await ready.start();
      expect(ready.client.activities, hasLength(2));
      expect(ready.client.activities[1], ready.client.activities[0]);
      expect(ready.prepares, 1);
      expect(ready.controller.activity.readiness, OtpActivityReadiness.ready);
      await ready.close();
    },
  );
  test(
    'same SMS identifier on a new pairing has independent acknowledgement',
    () async {
      await harness.push(90);
      await harness.controller.pair(
        'https://other-gateway.test?token=other-test',
      );
      await harness.push(90);
      expect(harness.client.acks, [90, 90]);
      expect(harness.sink.hits, isEmpty);
    },
  );
  test(
    'server shortened deadline is accepted and reused for rotation and end',
    () async {
      final ready = _Harness(compatible: true);
      ready.startedOffset = 30;
      ready.client.shortenExpiry = 30;
      await ready.start();
      expect(ready.controller.activity.readiness, OtpActivityReadiness.ready);
      final effective =
          (ready.client.activities.first['expires_at'] as int) - 30;
      expect(ready.controller.activity.expiresAt, effective);
      await ready.activityEvent({'update_token': 'ccdd', 'revision': 2});
      expect(ready.client.activities.last['expires_at'], effective);
      ready.controller.setEnabled(false);
      await ready.settle();
      expect(ready.client.activities.last['state'], 'ended');
      expect(ready.client.activities.last['expires_at'], effective);
      await ready.close();
    },
  );
  test(
    'terminal snapshot clears readiness and late active token cannot revive',
    () async {
      final ready = _Harness(compatible: true);
      await ready.start();
      expect(ready.controller.activity.readiness, OtpActivityReadiness.ready);
      await ready.activityEvent({
        'state': 'dismissed',
        'update_token': '',
        'revision': 2,
      });
      expect(
        ready.controller.activity.readiness,
        OtpActivityReadiness.unavailable,
      );
      final count = ready.client.activities.length;
      await ready.activityEvent({
        'state': 'active',
        'update_token': 'ccdd',
        'revision': 3,
      });
      await ready.push(900);
      expect(
        ready.controller.activity.readiness,
        OtpActivityReadiness.unavailable,
      );
      expect(ready.client.activities.length, count);
      expect(ready.prepares, 1);
      await ready.close();
    },
  );
  test(
    'wrong scope cannot register or replace the acknowledged activity',
    () async {
      final ready = _Harness(compatible: true);
      await ready.start();
      final count = ready.client.activities.length;
      await ready.activityEvent({
        'scope_id': 'other-scope',
        'update_token': 'ccdd',
        'revision': 3,
      });
      expect(ready.client.activities.length, count);
      expect(ready.controller.activity.readiness, OtpActivityReadiness.ready);
      await ready.close();
    },
  );
  test(
    'empty native snapshot clears the previously acknowledged token',
    () async {
      final ready = _Harness(compatible: true);
      await ready.start();
      await ready.activityEvent({
        'scope_id': '',
        'activity_id': '',
        'state': 'none',
        'update_token': '',
        'revision': 0,
      });
      expect(
        ready.controller.activity.readiness,
        OtpActivityReadiness.unavailable,
      );
      await ready.close();
    },
  );

  test('background restore waits for a real foreground entry', () async {
    final ready = _Harness(compatible: true);
    ready.controller.activity.didChangeAppLifecycleState(
      AppLifecycleState.paused,
    );
    await ready.start();
    expect(ready.prepares, 0);
    ready.controller.activity.didChangeAppLifecycleState(
      AppLifecycleState.resumed,
    );
    await ready.settle();
    expect(ready.prepares, 1);
    ready.controller.activity.didChangeAppLifecycleState(
      AppLifecycleState.resumed,
    );
    await ready.settle();
    expect(ready.prepares, 1);
    await ready.close();
  });

  test('offline end is retried from the persisted native tombstone', () async {
    final ready = _Harness(compatible: true);
    await ready.start();
    ready.client.failActivity = true;
    ready.controller.setEnabled(false);
    await ready.settle();
    final before = ready.client.activities
        .where((v) => v['state'] == 'ended')
        .length;
    ready.client.failActivity = false;
    ready.controller.setEnabled(true);
    await ready.settle();
    expect(
      ready.client.activities.where((v) => v['state'] == 'ended').length,
      greaterThan(before),
    );
    await ready.close();
  });

  test('disable ends locally even when server revocation fails', () async {
    final ready = _Harness(compatible: true);
    await ready.start();
    ready.client.failActivity = true;
    ready.controller.setEnabled(false);
    await ready.settle();
    expect(ready.ends, 1);
    expect(ready.client.activities.last['state'], 'ended');
    await ready.close();
  });

  group('polling alert ownership', () {
    RemoteOtpController create(_Store store, Future<Uri> Function()? origin) {
      final client = http.Client();
      final controller = RemoteOtpController(
        store: store,
        streamClient: RemoteOtpStreamClient(client),
        pushClient: IosPushEndpointClient(client),
        apns: IosApnsBridge(
          channel: const MethodChannel('test/ownership-apns'),
        ),
        otpSink: null,
        pollingOriginProvider: origin,
      );
      addTearDown(() {
        controller.dispose();
        client.close();
      });
      return controller;
    }

    test('persisted same origin owns alerts without restore', () async {
      final controller = create(
        _Store(),
        () async => Uri.parse('https://gateway.test'),
      );
      expect(controller.state.paired, isFalse);
      expect(await controller.ownsPollingAlerts(), isTrue);
      expect(controller.state.paired, isFalse);
    });

    test(
      'no pairing or no polling provider preserves local ownership',
      () async {
        final unpaired = _Store()..endpoint = null;
        expect(
          await create(
            unpaired,
            () async => throw StateError('must not read'),
          ).ownsPollingAlerts(),
          isFalse,
        );
        expect(await create(_Store(), null).ownsPollingAlerts(), isFalse);
      },
    );

    for (final urls in [
      ('https://GATEWAY.test:443/', 'https://gateway.test'),
      ('http://GATEWAY.test:80/', 'http://gateway.test'),
      ('https://gateway.test', 'https://GATEWAY.test:443/'),
    ]) {
      test('normalized root origins match: $urls', () async {
        final store = _Store()
          ..endpoint = RemoteOtpEndpoint(
            baseUrl: Uri.parse(urls.$1),
            token: 'test-token',
          );
        expect(
          await create(
            store,
            () async => Uri.parse(urls.$2),
          ).ownsPollingAlerts(),
          isTrue,
        );
      });
    }

    for (final url in [
      'https://other-gateway.test',
      'http://gateway.test',
      'https://gateway.test:8443',
      'https://gateway.test/tenant-a',
    ]) {
      test('different paired source stays local: $url', () async {
        final store = _Store()
          ..endpoint = RemoteOtpEndpoint(
            baseUrl: Uri.parse(url),
            token: 'test-token',
          );
        expect(
          await create(
            store,
            () async => Uri.parse('https://gateway.test'),
          ).ownsPollingAlerts(),
          isFalse,
        );
      });
    }

    test('store read error propagates', () async {
      final error = StateError('storage unavailable');
      final controller = create(
        _Store()..readError = error,
        () async => Uri.parse('https://gateway.test'),
      );
      await expectLater(controller.ownsPollingAlerts(), throwsA(same(error)));
    });

    test('origin read error propagates', () async {
      final error = StateError('origin unavailable');
      final controller = create(_Store(), () async => throw error);
      await expectLater(controller.ownsPollingAlerts(), throwsA(same(error)));
    });
  });

  test(
    'foreground APNs only acknowledges without writing an activity',
    () async {
      await harness.push(10);
      expect(harness.sink.hits, isEmpty);
      expect(harness.sink.notifications, 0);
      expect(harness.client.acks, <int>[10]);
      expect(harness.store.lastEventId, 10);
    },
  );

  test('SSE only acknowledges without writing an activity', () async {
    await harness.sms(11);
    expect(harness.sink.hits, isEmpty);
    expect(harness.sink.notifications, 0);
    expect(harness.client.acks, <int>[11]);
  });

  test('ordinary SMS is acknowledged without starting an activity', () async {
    await harness.push(12, content: 'Meeting at 123456');
    await harness.sms(13, content: 'Meeting at 234567');
    expect(harness.sink.hits, isEmpty);
    expect(harness.client.acks, <int>[12, 13]);
  });

  test(
    'APNs and SSE duplicates acknowledge once without activity writes',
    () async {
      await harness.push(20);
      await harness.sms(20);
      await harness.push(20);
      await harness.sms(21);
      await harness.push(21);
      expect(harness.sink.hits, isEmpty);
      expect(harness.client.acks, <int>[20, 21]);
    },
  );

  test(
    'drained background alerts do not revive OTP on stream replay',
    () async {
      harness.pending.add(_event(30, systemPresented: true));
      await harness.apns.refresh();
      await harness.settle();
      await harness.sms(30);
      expect(harness.sink.hits, isEmpty);
      expect(harness.client.acks, <int>[30]);
    },
  );

  test(
    'activity failure never blocks acknowledgement or stream progress',
    () async {
      harness.sink.error = PlatformException(code: 'activity_failed');
      await harness.sms(40);
      expect(harness.store.lastEventId, 40);
      expect(harness.client.acks, <int>[40]);
      harness.sink.error = null;
      await harness.push(40);
      expect(harness.sink.hits, isEmpty);
      expect(harness.client.acks, <int>[40]);
    },
  );

  test('disabled controller ignores activity and acknowledgement', () async {
    harness.controller.setEnabled(false);
    await harness.push(50);
    expect(harness.sink.hits, isEmpty);
    expect(harness.client.acks, isEmpty);
  });

  test(
    'an undecided notification permission is requested on restore',
    () async {
      expect(harness.permissionRequests, 1);
      expect(harness.apns.status.value.canPresentAlerts, isTrue);
    },
  );

  test('an authorized permission is never asked again', () async {
    final granted = _Harness(authorization: 'authorized');
    await granted.start();
    expect(granted.permissionRequests, 0);
    await granted.close();
  });

  test(
    'registration requests update only and never uploads a start token',
    () async {
      final withToken = _Harness(pushToStartToken: _startToken);
      await withToken.start();
      expect(withToken.client.registrations, isNotEmpty);
      expect(
        withToken.client.registrations.first['live_activity_mode'],
        'update_only',
      );
      expect(
        withToken.client.registrations.last.keys,
        unorderedEquals(['device_token', 'environment']),
      );
      expect(
        withToken.client.registrations.any(
          (body) => body.containsKey('push_to_start_token'),
        ),
        isFalse,
      );
      await withToken.close();
    },
  );

  test('a start token that arrives after launch re-registers', () async {
    // A legacy start-token callback may trigger reconciliation, but its token
    // must never be uploaded or mistaken for an update-only activity binding.
    final before = harness.client.registrations.length;
    expect(
      harness.client.registrations.last.containsKey('push_to_start_token'),
      isFalse,
    );
    harness.pushToStartToken = _startToken;
    await harness.apns.refresh();
    await harness.settle();
    expect(harness.client.registrations, hasLength(before + 2));
    expect(
      harness.client.registrations[before]['live_activity_mode'],
      'update_only',
    );
    expect(
      harness.client.registrations.last.keys,
      unorderedEquals(['device_token', 'environment']),
    );
    expect(
      harness.client.registrations.any(
        (body) => body.containsKey('push_to_start_token'),
      ),
      isFalse,
    );
  });
}

Map<String, Object> _event(
  int id, {
  bool systemPresented = false,
  String content = 'Verification code: 123456',
}) => <String, Object>{
  'sms_id': id,
  'content': content,
  'number': 'sender',
  'device_label': 'modem',
  'system_presented': systemPresented,
};

final class _Harness {
  _Harness({
    this.authorization = 'notDetermined',
    this.pushToStartToken = '',
    this.compatible = false,
  });
  final bool compatible;
  int prepares = 0, ends = 0;
  int startedOffset = 0;
  String scope = '';
  final pendingEnds = <Map<String, Object>>[];

  final String authorization;

  /// 启动令牌由系统在 App 启动之后异步给出，所以这里可变，用来模拟迟到。
  String pushToStartToken;
  final store = _Store();
  final client = _Client();
  final sink = _Sink();
  final pending = <Map<String, Object>>[];
  int permissionRequests = 0;
  Map<String, Object> lastActivity = {};
  late final apns = IosApnsBridge(channel: _channel);
  late final controller = RemoteOtpController(
    store: store,
    streamClient: RemoteOtpStreamClient(client),
    pushClient: IosPushEndpointClient(client),
    apns: apns,
    otpSink: sink,
  );

  Map<String, Object> _tokenState(String authorization) => <String, Object>{
    'device_token': List<String>.filled(32, 'aa').join(),
    'environment': 'sandbox',
    'registration_error': '',
    'push_to_start_token': pushToStartToken,
    'authorization': authorization,
    'alerts_enabled': authorization == 'authorized',
  };

  Future<void> start() async {
    client.compatible = compatible;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_activityChannel, (call) async {
          if (call.method == 'pendingActivityEnds') return pendingEnds;
          if (call.method == 'acknowledgeActivityEnd') {
            pendingEnds.clear();
            return null;
          }
          if (call.method == 'scopeIdentifier') return 'scope-test';
          if (call.method == 'prepareActivity') {
            prepares++;
            scope = (call.arguments as Map)['scope_id'] as String;
          }
          if (call.method == 'endActivity') ends++;
          final result = <String, Object>{
            'scope_id': scope,
            'activity_id': scope.isEmpty ? '' : 'activity-test',
            'update_token': call.method == 'endActivity' ? '' : 'aabb',
            'revision': call.method == 'endActivity' ? 2 : 1,
            'started_at':
                DateTime.now().millisecondsSinceEpoch ~/ 1000 + startedOffset,
            'expires_at':
                DateTime.now().millisecondsSinceEpoch ~/ 1000 +
                28800 +
                startedOffset,
            'state': call.method == 'endActivity' ? 'ended' : 'active',
          };
          lastActivity = result;
          if (call.method == 'endActivity') pendingEnds.add(result);
          return result;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'drain':
              final drained = List<Map<String, Object>>.of(pending);
              pending.clear();
              return drained;
            case 'requestNotificationAuthorization':
              permissionRequests += 1;
              return _tokenState('authorized');
            default:
              return _tokenState(authorization);
          }
        });
    await controller.restore();
    await settle();
  }

  Future<void> push(
    int id, {
    String content = 'Verification code: 123456',
  }) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('notification', _event(id, content: content)),
          ),
          (_) {},
        );
    await settle();
  }

  Future<void> activityEvent(Map<String, Object> changes) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _activityChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('activityState', {...lastActivity, ...changes}),
          ),
          (_) {},
        );
    await settle();
  }

  Future<void> sms(
    int id, {
    String content = 'Verification code: 123456',
  }) async {
    final data = jsonEncode(<String, Object>{
      'content': content,
      'number': 'sender',
      'device_label': 'modem',
    });
    client.events.add(utf8.encode('event: sms\nid: $id\ndata: $data\n\n'));
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> close() async {
    controller.dispose();
    await client.events.close();
    await settle();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_activityChannel, null);
  }
}

final class _Client extends http.BaseClient {
  final events = StreamController<List<int>>.broadcast();
  final acks = <int>[];
  final registrations = <Map<String, dynamic>>[];
  final activities = <Map<String, dynamic>>[];
  bool compatible = false, failActivity = false;
  bool dropActivityReplyOnce = false;
  int shortenExpiry = 0;
  int? effectiveExpiry;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET') {
      return http.StreamedResponse(events.stream, 200);
    }
    final body =
        jsonDecode((request as http.Request).body) as Map<String, dynamic>;
    if (request.url.path.endsWith('/ack')) {
      acks.add(body['sms_id'] as int);
    } else if (request.url.path.endsWith('/live-activity')) {
      activities.add(body);
      effectiveExpiry ??= (body['expires_at'] as int) - shortenExpiry;
      if (dropActivityReplyOnce) {
        dropActivityReplyOnce = false;
        throw http.ClientException('test lost response');
      }
      if (failActivity) {
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
      }
    } else {
      registrations.add(body);
    }
    if (compatible) {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'data': {
                'live_activity_protocol': 1,
                'live_activity_mode': 'update_only',
                'push_to_start_token': '',
                'server_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                'live_activity': {
                  'activity_id': body['activity_id'] ?? '',
                  'revision': body['revision'] ?? 0,
                  'state': body['state'] ?? 'none',
                  'expires_at': body['activity_id'] == null
                      ? 0
                      : effectiveExpiry,
                },
              },
            }),
          ),
        ),
        200,
      );
    }
    return http.StreamedResponse(Stream<List<int>>.empty(), 204);
  }
}

final class _Sink implements SmsOtpSink, SmsOtpActivitySink {
  final hits = <SmsOtpHit>[];
  int notifications = 0;
  Object? error;

  @override
  Future<void> present(SmsOtpHit hit) async {
    notifications++;
  }

  @override
  Future<bool> showActivity(SmsOtpHit hit) async {
    hits.add(hit);
    if (error != null) throw error!;
    return true;
  }
}

final class _Store implements RemoteOtpPairingStore {
  Object? readError;
  RemoteOtpEndpoint? endpoint = RemoteOtpEndpoint(
    baseUrl: Uri.parse('https://gateway.test'),
    token: 'test-token',
  );
  int lastEventId = 0;
  int lastPushId = 0;

  @override
  Future<RemoteOtpEndpoint?> read() async {
    if (readError != null) throw readError!;
    return endpoint;
  }

  @override
  Future<void> write(RemoteOtpEndpoint value) async => endpoint = value;
  @override
  Future<void> clear() async => endpoint = null;
  @override
  Future<int> readLastEventId() async => lastEventId;
  @override
  Future<void> writeLastEventId(int value) async => lastEventId = value;
  @override
  Future<int> readLastAcknowledgedPushId() async => lastPushId;
  @override
  Future<void> writeLastAcknowledgedPushId(int value) async =>
      lastPushId = value;
}
