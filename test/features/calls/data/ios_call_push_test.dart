import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/calls/data/ios_call_push.dart';

/// PushKit 令牌是 32 字节，也就是 64 个十六进制字符。
String _pairs(String pair) => List<String>.filled(32, pair).join();

const _channel = MethodChannel('com.oneims.onewifi/call_push');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final production = <String, Object>{
    'device_token': _pairs('AA'), // PushKit 给小写，这里故意给大写
    'environment': 'Production', // 环境大小写不该影响判断
  };
  final tokenA = CallPushToken(
    deviceToken: _pairs('aa'),
    environment: 'production',
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  test('只有十六进制令牌配已知环境才算可用', () {
    expect(CallPushToken.parse(production), tokenA);
    for (final rejected in <Object?>[
      null,
      'not-a-map',
      <String, Object>{'device_token': _pairs('zz'), 'environment': 'sandbox'},
      <String, Object>{'device_token': _pairs('aa'), 'environment': 'staging'},
      <String, Object>{'device_token': _pairs('aa')},
      <String, Object>{'environment': 'sandbox'},
    ]) {
      expect(CallPushToken.parse(rejected), isNull, reason: '$rejected');
    }
  });

  test('start 取回原生已就位的令牌，事件只在令牌真正变化时通知', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'start') return production;
      fail('unexpected platform call ${call.method}');
    });
    final tokens = IosCallPushTokens();
    final seen = <CallPushToken>[];
    tokens.changes.listen(seen.add);

    expect(await tokens.start(), tokenA);

    Future<void> deliver(Object? arguments) async {
      await messenger.handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('token', arguments),
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
    }

    await deliver(production);
    expect(seen, isEmpty, reason: '同一令牌重复上报没有意义');
    await deliver(<String, Object>{
      'device_token': _pairs('bb'),
      'environment': 'production',
    });
    expect(seen, hasLength(1));
    expect(seen.single.deviceToken, _pairs('bb'));
    await deliver(<String, Object>{
      'device_token': '',
      'environment': 'production',
    });
    expect(seen, hasLength(1), reason: '清空令牌不是一次可用的登记');
  });
}