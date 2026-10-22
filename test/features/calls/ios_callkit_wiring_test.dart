import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// These tests check the checked-in iOS integration, not CallKit execution.
// AVAudioSession, signing and real device behavior require macOS/iPhone tests.
void main() {
  String source(String path) => File(path).readAsStringSync();

  test('iOS app registers the native call session instead of legacy PCM', () {
    final delegate = source('ios/Runner/AppDelegate.swift');
    expect(delegate, contains('CallKitCoordinator()'));
    expect(delegate, contains('CallSessionChannel('));
    expect(
      delegate,
      contains('callSessionChannel.register(messenger: messenger)'),
    );
    expect(delegate, isNot(contains('callAudioBridge.register(')));
  });

  test(
    'scene lifecycle informs native calls only at foreground/background',
    () {
      final scene = source('ios/Runner/SceneDelegate.swift');
      expect(scene, contains('sceneDidBecomeActive'));
      expect(scene, contains('sceneDidEnterBackground'));
      expect(scene, contains('setForeground(true)'));
      expect(scene, contains('setForeground(false)'));
      expect(scene, isNot(contains('sceneWillResignActive')));
    },
  );

  test('CallKit declares audio, voip and alert push without enabling all ATS', () {
    final plist = source('ios/Runner/Info.plist');
    expect(
      RegExp(
        r'<key>UIBackgroundModes</key>\s*<array>\s*<string>audio</string>\s*<string>voip</string>\s*<string>remote-notification</string>\s*</array>',
      ).hasMatch(plist),
      isTrue,
    );
    expect(plist, contains('<key>NSLocalNetworkUsageDescription</key>'));
    expect(plist, contains('<key>NSAllowsLocalNetworking</key>'));
    expect(plist, isNot(contains('NSAllowsArbitraryLoads')));
  });

  test('推送环境跟着签名描述文件：development 描述文件配 sandbox', () {
    final entitlements = source('ios/Runner/Runner.entitlements');
    // 现有描述文件只授予 development，写成 production 会直接签不过。
    expect(entitlements, contains('<key>aps-environment</key>'));
    expect(entitlements, contains('<string>development</string>'));
    final project = source('ios/Runner.xcodeproj/project.pbxproj');
    // 短信告警和通话推送共用这一个环境：漏改一处就会让令牌投到另一个环境。
    expect(
      RegExp('APNS_ENVIRONMENT = sandbox;').allMatches(project),
      hasLength(3),
    );
    expect(source('ios/Runner/Info.plist'), contains(r'$(APNS_ENVIRONMENT)'));
  });

  test('VoIP 推送在原生侧接线：registry 早于 Flutter，推送交给 coordinator', () {
    final delegate = source('ios/Runner/AppDelegate.swift');
    final start = delegate.indexOf('callPush.start()');
    expect(start, greaterThanOrEqualTo(0));
    // 被 VoIP 推送唤醒时，系统要求进程里已经存在 PKPushRegistry，晚于
    // super.application 就晚了。
    expect(start, lessThan(delegate.indexOf('super.application(')));
    expect(
      delegate,
      contains('CallPushRegistry(coordinator: callCoordinator)'),
    );
    expect(delegate, contains('callPush.register(messenger: messenger)'));

    final registry = source('ios/Runner/Calls/CallPushRegistry.swift');
    expect(registry, contains('PKPushRegistry(queue: .main)'));
    expect(registry, contains('desiredPushTypes = [.voIP]'));
    expect(registry, contains('"com.oneims.onewifi/call_push"'));
    expect(registry, contains('coordinator.receivePush('));

    final project = source('ios/Runner.xcodeproj/project.pbxproj');
    for (final name in const ['APNsBridge.swift', 'OtpNotifier.swift']) {
      expect(File('ios/Runner/$name').existsSync(), isTrue, reason: name);
      expect(project, contains('$name in Sources'), reason: name);
    }
  });

  test('native input tap is prepared before engine start and mute only gates data', () {
    final audio = source('ios/Runner/Calls/CallPCMTransport.swift')
        .split('private final class CallNativeAudioDevice').last;
    final start = audio.split('func start() throws {').last
        .split('func setCaptureEnabled').first;
    expect(start.indexOf('let input = engine.inputNode'), greaterThanOrEqualTo(0));
    expect(start.indexOf('input.installTap'), greaterThanOrEqualTo(0));
    expect(start.indexOf('input.installTap'), lessThan(start.indexOf('engine.start()')));
    final gate = audio.split('func setCaptureEnabled').last.split('func stop()').first;
    expect(gate, isNot(contains('installTap')));
    expect(gate, isNot(contains('removeTap')));
    expect(gate, contains('captureConverter?.reset()'));
    expect(audio, isNot(contains('setPreferredSampleRate(8000)')));
    expect(audio, isNot(contains('setActive(')));
  });

  test(
    'all native call sources and tests are members of the Xcode project',
    () {
      final project = source('ios/Runner.xcodeproj/project.pbxproj');
      const production = [
        'CallGatewayModels.swift',
        'CallGatewayClient.swift',
        'CallEventStream.swift',
        'CallPCMTransport.swift',
        'CallKitCoordinator.swift',
        'CallKitPlatform.swift',
        'CallSessionChannel.swift',
        'CallPushRegistry.swift',
      ];
      const tests = ['CallTransportTests.swift', 'CallCoordinatorTests.swift'];
      for (final name in production) {
        expect(
          File('ios/Runner/Calls/$name').existsSync(),
          isTrue,
          reason: name,
        );
        expect(project, contains('$name in Sources'), reason: name);
        expect(project, contains('path = $name;'), reason: name);
      }
      for (final name in tests) {
        expect(
          File('ios/RunnerTests/$name').existsSync(),
          isTrue,
          reason: name,
        );
        expect(project, contains('$name in Sources'), reason: name);
        expect(project, contains('path = $name;'), reason: name);
      }
    },
  );
}
