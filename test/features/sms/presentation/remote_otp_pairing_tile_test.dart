import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/features/sms/data/ios_apns_bridge.dart';
import 'package:onewifi_android/features/sms/data/ios_push_endpoint_client.dart';
import 'package:onewifi_android/features/sms/data/remote_otp_pairing_store.dart';
import 'package:onewifi_android/features/sms/data/remote_otp_stream_client.dart';
import 'package:onewifi_android/features/sms/data/sms_repository.dart';
import 'package:onewifi_android/features/sms/domain/remote_otp_pairing.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/presentation/widgets/remote_otp_pairing_tile.dart';
import 'package:onewifi_android/features/sms/state/remote_otp_controller.dart';
import 'package:onewifi_android/features/sms/state/sms_controller.dart';

const _channel = MethodChannel('test/pairing-tile-apns');
const _token =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

/// push-to-start 令牌与横幅令牌是两个空间，长度是 160 位十六进制。
const _startToken =
    '802a51a15c0de1f2ab34cd56ef78a901b2c3d4e5f60718293a4b5c6d7e8f90'
    '802a51a15c0de1f2ab34cd56ef78a901b2c3d4e5f60718293a4b5c6d7e8f90'
    '1234567890abcdef1234567890abcdef';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Map<String, Object?> replies;

  Map<String, Object?> tokenState({
    String? authorization,
    bool? alertsEnabled,
    String pushToStartToken = '',
  }) => <String, Object?>{
    'device_token': _token,
    'environment': 'sandbox',
    'registration_error': '',
    'push_to_start_token': pushToStartToken,
    'authorization': ?authorization,
    'alerts_enabled': ?alertsEnabled,
  };

  setUp(() {
    calls = <MethodCall>[];
    replies = <String, Object?>{};
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return replies[call.method] ?? tokenState();
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
  });

  Future<SmsController> pumpTile(
    WidgetTester tester, {
    bool paired = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _MemoryPairingStore();
    if (paired) {
      await store.write(
        RemoteOtpEndpoint(
          baseUrl: Uri.parse('http://gateway.test/onetools'),
          token: 'test-token',
        ),
      );
    }
    final remote = RemoteOtpController(
      store: store,
      streamClient: RemoteOtpStreamClient(_SilentClient()),
      pushClient: IosPushEndpointClient(_SilentClient()),
      apns: IosApnsBridge(channel: _channel),
      otpSink: null,
    );
    final sms = SmsController(
      repository: _UnusedSmsRepository(),
      requestRegistry: RequestRegistry(),
      remoteOtp: remote,
    );
    addTearDown(sms.dispose);
    if (paired) await remote.restore();
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemoteOtpPairingTile(controller: sms),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sms;
  }

  testWidgets('unasked notification permission is reported with one action', (
    tester,
  ) async {
    replies['notificationState'] = tokenState(
      authorization: 'notDetermined',
      alertsEnabled: false,
    );
    await pumpTile(tester);
    expect(find.textContaining('系统通知权限未开启'), findsOneWidget);
    expect(find.text('开启通知权限'), findsOneWidget);

    replies['requestNotificationAuthorization'] = tokenState(
      authorization: 'authorized',
      alertsEnabled: true,
    );
    await tester.tap(find.byKey(RemoteOtpPairingTile.pushActionKey));
    await tester.pumpAndSettle();
    expect(
      calls.map((call) => call.method),
      contains('requestNotificationAuthorization'),
    );
    expect(find.text('后台推送已就绪。'), findsOneWidget);
    expect(find.byKey(RemoteOtpPairingTile.pushActionKey), findsNothing);
  });

  testWidgets('denied permission points at the system settings', (
    tester,
  ) async {
    replies['notificationState'] = tokenState(
      authorization: 'denied',
      alertsEnabled: false,
    );
    await pumpTile(tester);
    expect(find.textContaining('通知权限已被拒绝'), findsOneWidget);
    await tester.tap(find.byKey(RemoteOtpPairingTile.pushActionKey));
    await tester.pumpAndSettle();
    expect(
      calls.map((call) => call.method),
      contains('openNotificationSettings'),
    );
  });

  testWidgets('a missing push address is reported before permission', (
    tester,
  ) async {
    replies['notificationState'] = <String, Object?>{
      'device_token': '',
      'environment': 'sandbox',
      'registration_error': '',
      'authorization': 'authorized',
      'alerts_enabled': true,
    };
    await pumpTile(tester);
    expect(find.textContaining('推送地址尚未登记'), findsOneWidget);
  });

  testWidgets('a silent banner setting is reported without blocking alerts', (
    tester,
  ) async {
    replies['notificationState'] = tokenState(
      authorization: 'authorized',
      alertsEnabled: false,
    );
    await pumpTile(tester);
    expect(find.textContaining('横幅被关闭'), findsOneWidget);
    expect(find.text('去系统设置'), findsOneWidget);
  });

  testWidgets('a start token cannot claim receive activity readiness', (
    tester,
  ) async {
    replies['notificationState'] = tokenState(
      authorization: 'authorized',
      alertsEnabled: true,
      pushToStartToken: _startToken,
    );
    await pumpTile(tester);
    expect(find.textContaining('接收活动'), findsNothing);
    expect(find.textContaining('启动令牌'), findsNothing);
  });

  testWidgets('a missing island start token explains the lock screen gap', (
    tester,
  ) async {
    replies['notificationState'] = tokenState(
      authorization: 'authorized',
      alertsEnabled: true,
    );
    await pumpTile(tester);
    expect(find.textContaining('接收活动'), findsNothing);
  });

  testWidgets('paired disconnect stays in the card header', (tester) async {
    final sms = await pumpTile(tester, paired: true);

    final card = tester.getRect(find.byKey(RemoteOtpPairingTile.cardKey));
    final disconnect = tester.getRect(
      find.byKey(RemoteOtpPairingTile.disconnectKey),
    );
    expect(disconnect.left, greaterThan(card.center.dx));
    expect(disconnect.top, lessThan(card.top + 64));
    expect(disconnect.height, greaterThanOrEqualTo(44));
    await sms.remoteOtpController!.disconnect();
  });
}

final class _SilentClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream<List<int>>.empty(), 204);
}

final class _MemoryPairingStore implements RemoteOtpPairingStore {
  RemoteOtpEndpoint? _endpoint;

  @override
  Future<RemoteOtpEndpoint?> read() async => _endpoint;

  @override
  Future<void> write(RemoteOtpEndpoint value) async => _endpoint = value;

  @override
  Future<void> clear() async => _endpoint = null;

  @override
  Future<int> readLastEventId() async => 0;

  @override
  Future<void> writeLastEventId(int value) async {}

  @override
  Future<int> readLastAcknowledgedPushId() async => 0;

  @override
  Future<void> writeLastAcknowledgedPushId(int value) async {}
}

final class _UnusedSmsRepository implements SmsRepository {
  @override
  Future<List<SmsContact>> fetchContacts({RequestCancellation? cancellation}) =>
      throw UnimplementedError();

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<int> deleteThread(
    SmsContactTarget target, {
    RequestCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<bool> deleteMessage(
    int messageId, {
    RequestCancellation? cancellation,
  }) async => true;
}
