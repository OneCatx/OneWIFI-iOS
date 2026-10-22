import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/settings/data/activation_channel.dart';
import 'package:onewifi_android/features/settings/data/product_license_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('onewifi/activation');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('channel store maps native android seat onto ProductLicense', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getState') {
            return <String, Object?>{
              'activated': true,
              'code': 'AB12-CD34-EF56-GH78',
              'membershipBadge': 'Ultra',
              'encrypted': false,
            };
          }
          if (call.method == 'activate') {
            expect(call.arguments, {'code': 'AB12-CD34-EF56-GH78'});
            return <String, Object?>{
              'ok': true,
              'message': 'Activated successfully',
              'activated': true,
              'code': 'AB12-CD34-EF56-GH78',
            };
          }
          fail(call.method);
        });

    final store = ChannelProductLicenseStore();
    expect((await store.read()).isActive, isTrue);
    final next = await store.activate('AB12-CD34-EF56-GH78');
    expect(next.key, 'AB12-CD34-EF56-GH78');
    expect(next.isActive, isTrue);
  });

  test('channel store maps membership badge onto ProductLicense', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getState');
          return <String, Object?>{
            'activated': true,
            'code': 'AB12-CD34-EF56-GH78',
            'membershipBadge': 'Ultra',
          };
        });

    final license = await ChannelProductLicenseStore().read();
    expect(license.isActive, isTrue);
    expect(license.membershipBadge, 'Ultra');
  });

  test(
    'getState PlatformException is a read failure, not an empty seat',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'ACTIVATION', message: '无法读取激活库');
          });

      expect(
        ChannelProductLicenseStore().read(),
        throwsA(
          isA<LicenseReadException>().having(
            (e) => e.message,
            'message',
            contains('无法读取'),
          ),
        ),
      );
    },
  );

  test('getState MissingPlugin is a read failure, not an empty seat', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw MissingPluginException('onewifi/activation');
        });

    expect(
      ChannelProductLicenseStore().read(),
      throwsA(isA<LicenseReadException>()),
    );
  });

  test('successful inactive packet stays inactive', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{'activated': false, 'code': ''};
        });

    final license = await ChannelProductLicenseStore().read();
    expect(license.isActive, isFalse);
    expect(license.key, isEmpty);
  });

  test('channel store maps native deactivate onto an empty seat', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'deactivate') {
            return <String, Object?>{
              'ok': true,
              'message': '已清除本机激活',
              'activated': false,
              'code': null,
            };
          }
          fail(call.method);
        });

    final next = await ChannelProductLicenseStore().deactivate();
    expect(next.isActive, isFalse);
    expect(next.key, isEmpty);
  });

  test('channel store surfaces native rejection', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'ok': false,
            'message': '该激活码安卓席已绑定其它手机；换机请联系客服解绑后重试',
            'activated': false,
          };
        });
    expect(
      () => ChannelProductLicenseStore().activate('AB12-CD34-EF56-GH78'),
      throwsA(
        isA<LicenseActivateException>().having(
          (e) => e.message,
          'message',
          contains('安卓席'),
        ),
      ),
    );
  });
}
