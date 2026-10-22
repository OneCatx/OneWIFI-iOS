import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/design/one/glass_chrome.dart';
import 'package:onewifi_android/design/one/glass_surface.dart';
import 'package:onewifi_android/features/calls/data/calls_repository.dart';
import 'package:onewifi_android/features/calls/data/native_call_session.dart';
import 'package:onewifi_android/features/calls/data/native_call_snapshot.dart';
import 'package:onewifi_android/features/calls/presentation/calls_screen.dart';
import 'package:onewifi_android/features/calls/state/calls_controller.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/state/device_list_controller.dart';

import '../data/native_call_snapshot_test.dart' show snapshotWire, localWire;

void main() {
  late _Native native;
  late CallsController calls;
  late DeviceListController devices;
  setUp(() {
    native = _Native();
    calls = CallsController(repository: _Repository(), originProvider: () async => Uri.parse('https://gateway.test'),
      tokenProvider: (_) async => 'test', requestRegistry: RequestRegistry(), nativeCalls: native);
    devices = DeviceListController(repository: _Devices(), requestRegistry: RequestRegistry());
    calls.selectDevice('A');
  });
  tearDown(() { calls.dispose(); devices.dispose(); native.dispose(); });

  for (final brightness in Brightness.values) {
    testWidgets('call surfaces inherit app colors in ${brightness.name} mode', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => GlassBackdrop(child: child!),
        home: Scaffold(body: CallsScreen(calls: calls, devices: devices)),
      ));
      expect(find.byType(GlassBackdrop), findsOneWidget);
      expect(tester.widget<ListView>(find.byKey(CallsScreen.rootKey)), isNotNull);
      final panels = tester.widgetList<GlassPanel>(find.byType(GlassPanel));
      expect(panels, isNotEmpty);
      expect(panels.every((panel) => panel.color == null), isTrue);
      expect(find.byType(GlassBackdrop), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('system failure diagnostic remains visible with connected events and no call', (tester) async {
    const detail = 'CK-D1\nstage=transaction action=start\n'
        'error domain=com.apple.CallKit.error.requesttransaction code=2';
    native.update(snapshotWire()
      ..['error'] = 'call_system_transaction'
      ..['systemDiagnostic'] = detail);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CallsScreen(calls: calls, devices: devices))));
    expect(find.byKey(const Key('native-system-diagnostic')), findsOneWidget);
    expect(find.text(detail), findsOneWidget);
    expect(find.byKey(const Key('native-tls-diagnostic')), findsNothing);
    expect(find.text('系统通话诊断（最近一次失败，请截图反馈）'), findsOneWidget);
    expect(tester.takeException(), isNull);
    native.update(snapshotWire(revision: 5));
    await tester.pump();
    expect(find.byKey(const Key('native-system-diagnostic')), findsNothing);
  });

  testWidgets('audio failure diagnostic remains visible after call ends', (tester) async {
    const detail = 'AUDIO-D1 txQueued=19 txDropped=4 rxQueued=0 rxDropped=0';
    native.update(snapshotWire()
      ..['error'] = 'call_audio_send_stalled'
      ..['audioDiagnostic'] = detail);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CallsScreen(calls: calls, devices: devices))));
    expect(find.byKey(const Key('native-audio-diagnostic')), findsOneWidget);
    expect(find.text(detail), findsOneWidget);
    expect(find.text('音频诊断（最近一次失败，请截图反馈）'), findsOneWidget);
    expect(tester.takeException(), isNull);
    native.update(snapshotWire(revision: 5));
    await tester.pump();
    expect(find.byKey(const Key('native-audio-diagnostic')), findsNothing);
  });

  testWidgets('Android dialpad supports plus and clearing without dialing', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CallsScreen(calls: calls, devices: devices))));
    await tester.ensureVisible(find.text('0'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('0'));
    await tester.pump();
    expect(calls.dialNumber, '+');
    await tester.ensureVisible(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(calls.dialNumber, '+1');
    await tester.ensureVisible(find.byTooltip('退格，长按清空'));
    await tester.pumpAndSettle();
    await tester.longPress(find.byTooltip('退格，长按清空'));
    await tester.pump();
    expect(calls.dialNumber, '');
    expect(native.commands, isEmpty);
  });

  testWidgets('history fills number and device without placing a call', (tester) async {
    final wire = snapshotWire();
    final rows = wire['devices'] as List;
    ((rows.first as Map)['calls'] as List).first['state'] = 'ended';
    native.update(wire);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CallsScreen(calls: calls, devices: devices))));
    await tester.tap(find.text('最近通话').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10086'));
    await tester.pumpAndSettle();
    expect(calls.dialNumber, '10086');
    expect(calls.deviceId, 'A');
    expect(find.byKey(const Key('calls-dial-field')), findsOneWidget);
    expect(native.commands, isEmpty);
  });

  testWidgets('settings and device picker are dialogs, not bottom sheets', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CallsScreen(calls: calls, devices: devices))));
    await tester.tap(find.byKey(const Key('calls-device-picker')));
    await tester.pumpAndSettle();
    expect(find.text('选择通话设备'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    Navigator.of(tester.element(find.text('选择通话设备'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('通话设置'));
    await tester.pumpAndSettle();
    expect(find.text('系统来电 · CallKit'), findsOneWidget);
    expect(find.text('后台接听'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('a live call stays with CallKit and does not render an in-app call screen', (tester) async {
    native.update(snapshotWire(local: localWire()));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CallsScreen(calls: calls, devices: devices))));
    expect(find.byKey(const Key('call-stage')), findsNothing);
    expect(find.text('接听'), findsNothing);
    expect(find.text('挂断'), findsNothing);
    expect(find.byKey(const Key('native-call-panel')), findsOneWidget);
    expect(native.commands, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen and large text keep the dialpad reachable', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    native.update(snapshotWire(local: localWire()));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
        child: child!,
      ),
      home: Scaffold(body: CallsScreen(calls: calls, devices: devices)),
    ));
    await tester.ensureVisible(find.byKey(const Key('calls-dial-button')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('calls-dial-button')), findsOneWidget);
  });
}

class _Native extends ChangeNotifier implements NativeCallView {
  NativeCallSnapshot _snapshot = NativeCallSnapshot.decode(snapshotWire());
  final List<String> commands = [];
  void update(Map<String, Object?> wire) { _snapshot = NativeCallSnapshot.decode(wire); notifyListeners(); }
  @override
  NativeCallSnapshot get snapshot => _snapshot;
  @override
  String get status => 'configured';
  @override
  Future<void> execute(String method, Map<String, Object?> values) async { commands.add(method); }
}
class _Repository implements CallsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Legacy calls must not run');
}
class _Devices implements DeviceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Legacy device loading must not run');
  @override
  Future<List<DiscoveredDevice>> fetchDiscoveredDevices({
    RequestCancellation? cancellation,
  }) async => const <DiscoveredDevice>[];

  @override
  Future<DeviceRescanResult> rescanDevices({
    RequestCancellation? cancellation,
  }) async => const DeviceRescanResult(status: 'ok', devicesCount: 0);

  @override
  Future<void> registerDevice({
    required String deviceId,
    required String discoveryKey,
    required String deviceType,
    String? name,
    String? simPin,
    Map<String, Object?>? additionalConfig,
    RequestCancellation? cancellation,
  }) async {}
}