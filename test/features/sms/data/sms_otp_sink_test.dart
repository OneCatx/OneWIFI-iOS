import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/sms/data/sms_otp_sink.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';

const _hit = SmsOtpHit(
  code: '123456',
  senderDisplay: 'sender',
  deviceName: 'modem',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.oneims.onewifi/otp');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('refused notification reports failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(await NativeSmsOtpSink(channel: channel).deliver(_hit), isFalse);
  });

  test('accepted notification does not copy by itself', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    expect(await NativeSmsOtpSink(channel: channel).deliver(_hit), isTrue);
  });

  test('missing plugin does not claim delivery', () async {
    expect(await NativeSmsOtpSink(channel: channel).deliver(_hit), isFalse);
  });

  test(
    'activity request is separate from local notification delivery',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      expect(
        await NativeSmsOtpSink(channel: channel).showActivity(_hit),
        isTrue,
      );
      expect(calls.single.method, 'showActivity');
      expect(calls.single.arguments, <String, String>{
        'code': '123456',
        'sender': 'sender',
        'device': 'modem',
      });
    },
  );

  test('activity errors remain visible to the test action', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'activity_failed', message: 'disabled');
    });
    await expectLater(
      NativeSmsOtpSink(channel: channel).showActivity(_hit),
      throwsA(isA<PlatformException>()),
    );
  });
}
