import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/sms/data/ios_apns_bridge.dart';

const _channel = MethodChannel('test/apns-bridge');
const _token =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
// Live Activity start tokens are a separate token space from alert tokens.
const _startToken = 'aabbccddeeff00112233445566778899';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Map<String, Object?> replies;
  late IosApnsBridge bridge;

  Map<String, Object?> tokenState({
    String authorization = '',
    bool? alertsEnabled,
    String pushToStartToken = '',
  }) => <String, Object?>{
    'device_token': _token,
    'environment': 'sandbox',
    'registration_error': '',
    'push_to_start_token': pushToStartToken,
    if (authorization.isNotEmpty) 'authorization': authorization,
    'alerts_enabled': ?alertsEnabled,
  };

  setUp(() {
    calls = <MethodCall>[];
    replies = <String, Object?>{};
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return replies[call.method] ?? tokenState();
    });
    bridge = IosApnsBridge(channel: _channel);
  });

  tearDown(() async {
    await bridge.dispose();
    messenger.setMockMethodCallHandler(_channel, null);
  });

  test('native address and system switch merge into one status', () {
    final status = IosApnsStatus.empty.merge(
      tokenState(authorization: 'denied', alertsEnabled: false),
    );
    expect(status.registered, isTrue);
    expect(status.environment, 'sandbox');
    expect(status.authorization, IosPushAuthorization.denied);
    expect(status.canPresentAlerts, isFalse);
  });

  test('a malformed token never overwrites a registered address', () {
    final status = IosApnsStatus.empty.merge(tokenState()).merge(
      <String, Object?>{'device_token': 'not-a-token'},
    );
    expect(status.deviceToken, _token);
  });

  test('a live activity start token merges beside the alert address', () {
    final status = IosApnsStatus.empty.merge(
      tokenState(pushToStartToken: _startToken),
    );
    expect(status.pushToStartToken, _startToken);
    expect(status.deviceToken, _token);
  });

  test('a client without the field keeps the registered start token', () {
    final status = IosApnsStatus.empty
        .merge(tokenState(pushToStartToken: _startToken))
        .merge(tokenState());
    expect(status.pushToStartToken, _startToken);
  });

  test('a malformed start token never overwrites a registered one', () {
    final status = IosApnsStatus.empty
        .merge(tokenState(pushToStartToken: _startToken))
        .merge(tokenState(pushToStartToken: 'zz'));
    expect(status.pushToStartToken, _startToken);
  });

  test('a start token that arrives late re-registers the endpoint', () async {
    final seen = <String>[];
    final subscription = bridge.tokenChanges.listen(
      (_) => seen.add(bridge.status.value.pushToStartToken),
    );
    addTearDown(subscription.cancel);
    await bridge.start();
    expect(seen, <String>['']);

    replies['state'] = tokenState(pushToStartToken: _startToken);
    await bridge.refresh();
    expect(seen, <String>['', _startToken]);
  });

  test('alerts need both a registered address and a presenting switch', () {
    for (final authorization in IosPushAuthorization.values) {
      final status = IosApnsStatus.empty.merge(
        tokenState(authorization: authorization.name),
      );
      expect(
        status.canPresentAlerts,
        authorization.canPresent,
        reason: '$authorization',
      );
    }
    expect(IosApnsStatus.empty.canPresentAlerts, isFalse);
  });

  test('refreshAuthorization reads the current system switch', () async {
    replies['notificationState'] = tokenState(
      authorization: 'authorized',
      alertsEnabled: true,
    );
    await bridge.refreshAuthorization();
    expect(calls.map((call) => call.method), contains('notificationState'));
    expect(bridge.status.value.authorization, IosPushAuthorization.authorized);
    expect(bridge.status.value.alertsEnabled, isTrue);
  });

  test('requestAuthorization asks the system and reports the result', () async {
    replies['requestNotificationAuthorization'] = tokenState(
      authorization: 'authorized',
      alertsEnabled: true,
    );
    await bridge.requestAuthorization();
    expect(
      calls.map((call) => call.method),
      contains('requestNotificationAuthorization'),
    );
    expect(bridge.status.value.canPresentAlerts, isTrue);
  });

  test('openNotificationSettings forwards to the host', () async {
    await bridge.openNotificationSettings();
    expect(calls.single.method, 'openNotificationSettings');
  });

  test('a failing permission query keeps the registered address', () async {
    await bridge.start();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'notificationState') {
        throw PlatformException(code: 'unavailable');
      }
      return tokenState();
    });
    await bridge.refreshAuthorization();
    expect(bridge.deviceToken, _token);
    expect(
      bridge.status.value.authorization,
      IosPushAuthorization.notDetermined,
    );
  });

  test('registration failure is surfaced with its reason', () async {
    await messenger.handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('registrationError', <String, Object?>{
          'device_token': '',
          'environment': 'sandbox',
          'registration_error': 'no network',
        }),
      ),
      (_) {},
    );
    expect(bridge.status.value.registrationError, 'no network');
  });

  test('token changes notify listeners once per new address', () async {
    final seen = <String>[];
    final subscription = bridge.tokenChanges.listen(
      (_) => seen.add(bridge.deviceToken),
    );
    addTearDown(subscription.cancel);
    await bridge.start();
    await bridge.refresh();
    expect(seen, <String>[_token]);
  });
}
