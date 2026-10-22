import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/glass_dialog.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/presentation/device_detail_view.dart';
import 'package:onewifi_android/features/devices/state/device_detail_controller.dart';
import 'package:onewifi_android/features/esim/data/esim_repository.dart';
import 'package:onewifi_android/features/esim/domain/card_policy.dart';
import 'package:onewifi_android/features/esim/domain/esim.dart';
import 'package:onewifi_android/features/esim/presentation/esim_edit_sheet.dart';
import 'package:onewifi_android/features/esim/state/esim_controller.dart';

void main() {
  testWidgets('final overview supersedes a pre-switch manual refresh', (
    t,
  ) async {
    final repo = _ControlledDevices()..initialActive = false;
    final c = DeviceDetailController(
      deviceId: 'd',
      repository: repo,
      requestRegistry: RequestRegistry(),
    );
    final esimRepo = _Esim()
      ..switchFails = false
      ..switchGate = Completer<EsimSwitchResult>();
    final esim = _esimController(esimRepo);
    addTearDown(c.dispose);
    addTearDown(esim.dispose);
    await esim.load();
    await t.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: Scaffold(
          body: DeviceDetailView(
            controller: c,
            esimController: esim,
            onBack: () {},
          ),
        ),
      ),
    );
    await t.pump();
    final switching = esim.switchProfile(_profile);
    final refreshing = c.refresh();
    expect(repo.pending.length, 1);
    esimRepo.switchGate!.complete(
      const EsimSwitchResult(status: EsimSwitchStatus.switched, verified: true),
    );
    await t.pump();
    await switching;
    final count = repo.pending.length;
    if (count > 1) {
      repo.pending[1].complete(_detail(false));
      await t.pump();
    }
    repo.pending[0].complete(_detail(false));
    await t.pump();
    await refreshing;
    await t.pumpWidget(const SizedBox());
    expect(
      count,
      2,
      reason:
          'Terminal reconciliation is an explicit read, not a skippable timer tick',
    );
    expect(repo.tokens[0].isCancelled, isTrue);
  });
  for (final replace in [false, true]) {
    testWidgets(
      'queued final overview is dropped after ${replace ? 'replacement' : 'exit'}',
      (t) async {
        final repo = _ControlledDevices()..initialActive = false;
        final c = DeviceDetailController(
          deviceId: 'd',
          repository: repo,
          requestRegistry: RequestRegistry(),
        );
        final nextRepo = _Devices(500)..initialActive = false;
        final next = DeviceDetailController(
          deviceId: 'next',
          repository: nextRepo,
          requestRegistry: RequestRegistry(),
        );
        final esimRepo = _Esim()
          ..switchFails = false
          ..switchGate = Completer<EsimSwitchResult>();
        final esim = _esimController(esimRepo);
        addTearDown(c.dispose);
        addTearDown(next.dispose);
        addTearDown(esim.dispose);
        await esim.load();
        await t.pumpWidget(
          MaterialApp(
            theme: OneTheme.light(),
            home: Scaffold(
              body: DeviceDetailView(
                controller: c,
                esimController: esim,
                onBack: () {},
              ),
            ),
          ),
        );
        await t.pump();
        final switching = esim.switchProfile(_profile);
        await t.pump(const Duration(seconds: 1));
        esimRepo.switchGate!.complete(
          const EsimSwitchResult(
            status: EsimSwitchStatus.switched,
            verified: true,
          ),
        );
        await t.pump();
        await switching;
        await t.pumpWidget(replace ? _deviceApp(next) : const SizedBox());
        await t.pump();
        repo.pending.single.complete(_detail(false));
        await t.pump();
        await t.pump(const Duration(seconds: 5));
        expect(repo.pending.length, 1);
        expect(nextRepo.calls, replace ? 1 : 0);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'switch completion waits for old inactive poll before final overview',
    (t) async {
      final repo = _ControlledDevices()..initialActive = false;
      final c = DeviceDetailController(
        deviceId: 'd',
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      final esimRepo = _Esim()
        ..switchFails = false
        ..switchGate = Completer<EsimSwitchResult>();
      final esim = _esimController(esimRepo);
      addTearDown(c.dispose);
      addTearDown(esim.dispose);
      await esim.load();
      await t.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          home: Scaffold(
            body: DeviceDetailView(
              controller: c,
              esimController: esim,
              onBack: () {},
            ),
          ),
        ),
      );
      await t.pump();
      final switching = esim.switchProfile(_profile);
      await t.pump(const Duration(seconds: 1));
      expect(repo.pending.length, 1);
      esimRepo.switchGate!.complete(
        const EsimSwitchResult(
          status: EsimSwitchStatus.switched,
          verified: true,
        ),
      );
      await t.pump();
      await switching;
      expect(
        repo.pending.length,
        1,
        reason: 'Do not overlap the old automatic read',
      );
      repo.pending[0].complete(_detail(false));
      await t.pump();
      expect(
        repo.pending.length,
        2,
        reason: 'Switch completion requires a new post-switch overview',
      );
      expect(repo.tokens[0].isCancelled, isFalse);
      repo.pending[1].complete(_detail(false));
      await t.pump();
      await t.pump(const Duration(seconds: 5));
      expect(repo.pending.length, 2, reason: 'Exactly one final overview');
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('download timeout uses unknown outcome title and body', (
    t,
  ) async {
    final repo = _Esim();
    final c = _esimController(repo);
    addTearDown(c.dispose);
    await c.load();
    await _sheet(t, c);
    await t.tap(find.text('下载 Profile'));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(EsimPanelLpaKey.value),
      r'LPA:1$smdp.example$code',
    );
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, '下载'));
    await t.pumpAndSettle();
    expect(c.downloadAction.isUnknownOutcome, isTrue);
    expect(find.text('操作结果未知'), findsOneWidget);
    expect(find.text('下载失败'), findsNothing);
    expect(find.textContaining('请核对卡片状态'), findsOneWidget);
  });
  test(
    'cancelled slow automatic read stays single-flight until it settles',
    () async {
      final repo = _ControlledDevices();
      final c = DeviceDetailController(
        deviceId: 'd',
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(c.dispose);
      await c.load();
      final automatic = c.poll(automatic: true);
      final refresh = c.refresh();
      repo.pending[1].complete(_detail(false));
      await refresh;
      final skipped = c.poll(automatic: true);
      final calls = repo.pending.length;
      for (final gate in repo.pending) {
        if (!gate.isCompleted) gate.complete(_detail(true));
      }
      await Future.wait([automatic, skipped]);
      expect(
        calls,
        2,
        reason:
            'Ignored transport cancellation must not overlap two automatic reads',
      );
      expect(c.state.lastGoodData!.device.esimSwitch.active, isFalse);
    },
  );
  for (final delay in [500, 1500, 3000]) {
    testWidgets('polling finishes with ${delay}ms overview latency', (t) async {
      final repo = _Devices(delay);
      final c = DeviceDetailController(
        deviceId: 'd',
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          home: Scaffold(
            body: DeviceDetailView(controller: c, onBack: () {}),
          ),
        ),
      );
      await t.pump();
      for (var i = 0; i < 16; i++) {
        await t.pump(const Duration(milliseconds: 500));
      }
      final active = c.state.lastGoodData!.device.esimSwitch.active;
      final cancelled = repo.tokens.where((x) => x.isCancelled).length;
      final calls = repo.calls;
      expect(repo.maxInFlight, 1);
      await t.pump(const Duration(seconds: 4));
      expect(repo.calls, calls, reason: 'Completed switching stops the timer');
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.pump(const Duration(seconds: 2));
      // ignore: avoid_print
      print('delay=$delay calls=$calls cancelled=$cancelled active=$active');
      expect(
        active,
        isFalse,
        reason:
            'Completed gateway snapshot must reach the UI even when slower than polling interval',
      );
    });
  }
  testWidgets('successful rename is not poisoned by prior failed switch', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(600, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = _Esim();
    final c = EsimController(
      deviceId: 'd',
      repository: repo,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(c.dispose);
    await c.load();
    await t.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: Scaffold(body: EsimEditSheet(controller: c)),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(OutlinedButton, '启用'));
    await t.pumpAndSettle();
    expect(c.switchAction.status, ActionStatus.failed);
    await t.tap(find.widgetWithText(FilledButton, '改名'));
    await t.pumpAndSettle();
    expect(repo.renames, 1);
    expect(c.mutateAction.status, ActionStatus.succeeded);
    expect(
      find.text('操作失败'),
      findsNothing,
      reason: 'Successful rename should report its own result',
    );
    expect(find.text('eSIM 名称已更新'), findsOneWidget);
  });
  testWidgets('automatic polling recovers after a transient failure', (
    t,
  ) async {
    final repo = _Devices(1500)..failNext = true;
    final c = DeviceDetailController(
      deviceId: 'd',
      repository: repo,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(c.dispose);
    await t.pumpWidget(_deviceApp(c));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 500));
    }
    expect(c.state.lastGoodData!.device.esimSwitch.active, isFalse);
    expect(repo.maxInFlight, 1);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'manual refresh supersedes a poll and timer cannot cancel refresh',
    (t) async {
      final repo = _ControlledDevices();
      final c = DeviceDetailController(
        deviceId: 'd',
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(_deviceApp(c));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(repo.pending.length, 1);
      final refreshing = c.refresh();
      expect(repo.tokens[0].isCancelled, isTrue);
      await t.pump(const Duration(seconds: 3));
      expect(repo.pending.length, 2);
      expect(repo.tokens[1].isCancelled, isFalse);
      repo.pending[1].complete(_detail(false));
      await t.pump();
      await refreshing;
      repo.pending[0].complete(_detail(true));
      await t.pump();
      expect(c.state.lastGoodData!.device.esimSwitch.active, isFalse);
      if (repo.pending.length > 2) {
        repo.pending[2].complete(_detail(false));
        await t.pump();
      }
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'local switch completion keeps polling an active gateway snapshot',
    (t) async {
      final repo = _Devices(3000);
      final c = DeviceDetailController(
        deviceId: 'd',
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      final esimRepo = _Esim()
        ..switchFails = false
        ..switchGate = Completer<EsimSwitchResult>();
      final esim = _esimController(esimRepo);
      addTearDown(c.dispose);
      addTearDown(esim.dispose);
      await esim.load();
      await t.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          home: Scaffold(
            body: DeviceDetailView(
              controller: c,
              esimController: esim,
              onBack: () {},
            ),
          ),
        ),
      );
      await t.pump();
      final switching = esim.switchProfile(_profile);
      await t.pump(const Duration(seconds: 1));
      esimRepo.switchGate!.complete(
        const EsimSwitchResult(
          status: EsimSwitchStatus.switched,
          verified: true,
        ),
      );
      await t.pump();
      await switching;
      for (var i = 0; i < 16; i++) {
        await t.pump(const Duration(milliseconds: 500));
      }
      expect(c.state.lastGoodData!.device.esimSwitch.active, isFalse);
      expect(repo.maxInFlight, 1);
      expect(repo.tokens.any((token) => token.isCancelled), isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('replacement and exit stop automatic polling', (t) async {
    final oldRepo = _Devices(3000);
    final old = DeviceDetailController(
      deviceId: 'old',
      repository: oldRepo,
      requestRegistry: RequestRegistry(),
    );
    final newRepo = _Devices(500)..initialActive = false;
    final next = DeviceDetailController(
      deviceId: 'new',
      repository: newRepo,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(old.dispose);
    addTearDown(next.dispose);
    await t.pumpWidget(_deviceApp(old));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(oldRepo.calls, 2);
    await t.pumpWidget(_deviceApp(next));
    await t.pump();
    await t.pump(const Duration(seconds: 5));
    expect(oldRepo.calls, 2);
    expect(newRepo.calls, 1);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
    expect(oldRepo.calls, 2);
    expect(newRepo.calls, 1);
  });

  for (final prior in ['rename', 'policy']) {
    testWidgets('successful switch ignores prior $prior failure', (t) async {
      final repo = _Esim()..switchFails = false;
      final c = _esimController(repo);
      addTearDown(c.dispose);
      await c.load();
      if (prior == 'rename') {
        repo.renameError = const ApiFailure(
          ApiFailureKind.http,
          requestId: 'rename',
          statusCode: 503,
        );
        await c.renameProfile(_profile, 'New');
        repo.renameError = null;
      } else {
        repo.policyFails = true;
        await c.savePolicy(apn: 'ims', ipVersion: CardIpVersion.ipv4v6);
      }
      await _sheet(t, c);
      await t.tap(find.widgetWithText(OutlinedButton, '启用'));
      await t.pumpAndSettle();
      expect(c.switchAction.status, ActionStatus.succeeded);
      expect(find.text('eSIM 已启用'), findsOneWidget);
      expect(find.text('操作失败'), findsNothing);
    });
  }
  testWidgets('delete success ignores prior policy failure', (t) async {
    final repo = _Esim()..policyFails = true;
    final c = _esimController(repo);
    addTearDown(c.dispose);
    await c.load();
    await c.savePolicy(apn: 'ims', ipVersion: CardIpVersion.ipv4v6);
    await _sheet(t, c);
    await t.tap(find.widgetWithText(OutlinedButton, '删除'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(OneGlassDialog.confirmTargetKey));
    await t.pumpAndSettle();
    expect(repo.deletes, 1);
    expect(c.policyAction.status, ActionStatus.failed);
    expect(find.text('已删除「Travel」'), findsOneWidget);
    expect(find.text('操作失败'), findsNothing);
  });
  testWidgets('rename success keeps historical policy failure untouched', (
    t,
  ) async {
    final repo = _Esim()..policyFails = true;
    final c = _esimController(repo);
    addTearDown(c.dispose);
    await c.load();
    await c.savePolicy(apn: 'ims', ipVersion: CardIpVersion.ipv4v6);
    await _sheet(t, c);
    await t.tap(find.widgetWithText(FilledButton, '改名'));
    await t.pumpAndSettle();
    expect(c.policyAction.status, ActionStatus.failed);
    expect(find.text('eSIM 名称已更新'), findsOneWidget);
  });
  testWidgets('unverified switch is not presented as success', (t) async {
    final repo = _Esim()
      ..switchFails = false
      ..verified = false;
    final c = _esimController(repo);
    addTearDown(c.dispose);
    await c.load();
    await _sheet(t, c);
    await t.tap(find.widgetWithText(OutlinedButton, '启用'));
    await t.pumpAndSettle();
    expect(c.switchAction.status, ActionStatus.failed);
    expect(find.text('操作失败'), findsOneWidget);
    expect(find.text('已完成'), findsNothing);
  });
  testWidgets(
    'delete confirmation cannot apply old profile to replacement controller',
    (t) async {
      final repo = _Esim();
      final nextRepo = _Esim();
      final c = _esimController(repo);
      final next = _esimController(nextRepo);
      addTearDown(c.dispose);
      addTearDown(next.dispose);
      await c.load();
      await next.load();
      await _sheet(t, c);
      await t.tap(find.widgetWithText(OutlinedButton, '删除'));
      await t.pumpAndSettle();
      await t.pumpWidget(_sheetApp(next));
      await t.pumpAndSettle();
      await t.tap(find.byKey(OneGlassDialog.confirmTargetKey));
      await t.pumpAndSettle();
      expect(repo.deletes, 0);
      expect(nextRepo.deletes, 0);
      expect(find.text('已完成'), findsNothing);
    },
  );
  testWidgets('unknown rename outcome is not a confirmed failure or success', (
    t,
  ) async {
    final repo = _Esim()
      ..renameError = const ApiFailure(
        ApiFailureKind.timeout,
        requestId: 'rename',
      );
    final c = _esimController(repo);
    addTearDown(c.dispose);
    await c.load();
    await _sheet(t, c);
    await t.tap(find.widgetWithText(FilledButton, '改名'));
    await t.pumpAndSettle();
    expect(c.mutateAction.isUnknownOutcome, isTrue);
    expect(find.text('操作结果未知'), findsOneWidget);
    expect(find.text('已完成'), findsNothing);
  });
  testWidgets('same-frame duplicate rename does not invent success', (t) async {
    final repo = _Esim()..renameGate = Completer<void>();
    final c = _esimController(repo);
    addTearDown(c.dispose);
    await c.load();
    await _sheet(t, c);
    final callback = t
        .widget<FilledButton>(find.widgetWithText(FilledButton, '改名'))
        .onPressed!;
    callback();
    callback();
    await t.pump();
    expect(repo.renames, 1);
    expect(find.text('已完成'), findsNothing);
    repo.renameGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('eSIM 名称已更新'), findsOneWidget);
  });
  for (final replace in [false, true]) {
    testWidgets(
      'late rename after ${replace ? 'replacement' : 'exit'} has no feedback',
      (t) async {
        final repo = _Esim()..renameGate = Completer<void>();
        final c = _esimController(repo);
        final next = _esimController(_Esim());
        addTearDown(c.dispose);
        addTearDown(next.dispose);
        await c.load();
        await next.load();
        await _sheet(t, c);
        await t.tap(find.widgetWithText(FilledButton, '改名'));
        await t.pump();
        await t.pumpWidget(replace ? _sheetApp(next) : const SizedBox());
        await t.pump();
        repo.renameGate!.complete();
        await t.pumpAndSettle();
        expect(find.text('已完成'), findsNothing);
        expect(find.text('操作失败'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
}

final class _ControlledDevices implements DeviceRepository {
  bool loaded = false;
  bool initialActive = true;
  final pending = <Completer<DeviceDetail>>[];
  final tokens = <RequestCancellation>[];
  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String id, {
    RequestCancellation? cancellation,
  }) {
    if (!loaded) {
      loaded = true;
      return Future.value(_detail(initialActive));
    }
    final gate = Completer<DeviceDetail>();
    pending.add(gate);
    tokens.add(cancellation!);
    return gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

EsimController _esimController(_Esim repo) => EsimController(
  deviceId: 'd',
  repository: repo,
  requestRegistry: RequestRegistry(),
);
Widget _sheetApp(EsimController c) => MaterialApp(
  theme: OneTheme.light(),
  home: Scaffold(body: EsimEditSheet(controller: c)),
);
Future<void> _sheet(WidgetTester t, EsimController c) async {
  await t.binding.setSurfaceSize(const Size(600, 3000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(_sheetApp(c));
  await t.pumpAndSettle();
}

Widget _deviceApp(DeviceDetailController controller) => MaterialApp(
  theme: OneTheme.light(),
  home: Scaffold(
    body: DeviceDetailView(controller: controller, onBack: () {}),
  ),
);

final class _Devices implements DeviceRepository {
  _Devices(this.delay);
  final int delay;
  int calls = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  bool failNext = false;
  bool initialActive = true;
  final tokens = <RequestCancellation>[];
  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String id, {
    RequestCancellation? cancellation,
  }) async {
    calls++;
    if (calls == 1) return _detail(initialActive);
    tokens.add(cancellation!);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (failNext) {
        failNext = false;
        throw const ApiFailure(ApiFailureKind.network, requestId: 'poll');
      }
      return _detail(false);
    } finally {
      inFlight--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

DeviceDetail _detail(bool active) => DeviceDetail(
  device: DeviceSnapshot(
    id: 'd',
    name: 'Device',
    type: DeviceType.pcieEc20Ec25,
    healthy: true,
    physicalPresent: true,
    controlOnline: true,
    radioLive: true,
    radioRegistered: true,
    lifecyclePhase: DeviceLifecyclePhase.ready,
    lifecycleReasonCategory: DeviceReasonCategory.none,
    networkEnabled: true,
    networkConnected: true,
    vowifiEnabled: true,
    vowifiActive: true,
    smsEnabled: true,
    flightMode: false,
    developerEnabled: false,
    modem: const DeviceModem(
      operatorName: 'Carrier',
      model: 'EC25',
      firmware: null,
      networkMode: 'LTE',
      radioBand: 'B3',
      signalDbm: -70,
      signalRsrp: null,
      signalRsrq: null,
      signalSinr: 0,
      simPresent: true,
      serviceBlocked: false,
      blockedCategory: DeviceBlockedCategory.none,
    ),
    identities: const DeviceIdentityDisplays(
      imeiDisplay: null,
      iccidDisplay: null,
      imsiDisplay: null,
      phoneDisplay: null,
    ),
    runtime: const DeviceRuntime(
      phase: DeviceRuntimePhase.imsReady,
      simReady: true,
      accessReady: true,
      tunnelReady: true,
      imsReady: true,
      smsReady: true,
    ),
    esimSwitch: DeviceEsimSwitch(
      active: active,
      stages: List.filled(5, DeviceSwitchStageState.ready),
    ),
  ),
  traffic: const DeviceTraffic.unavailable(),
);

final class _Target implements EsimSwitchTarget {
  const _Target();
}

const _profile = EsimProfile(
  name: 'Travel',
  provider: 'Carrier',
  iccidDisplay: '1234',
  active: false,
  state: EsimProfileState.disabled,
  target: _Target(),
);

final class _Esim implements EsimRepository {
  int renames = 0;
  int deletes = 0;
  bool switchFails = true;
  bool verified = true;
  Completer<EsimSwitchResult>? switchGate;
  bool policyFails = false;
  Object? renameError;
  Completer<void>? renameGate;
  @override
  String aidHexOf(EsimSwitchTarget target) => '';
  @override
  Future<void> downloadProfile(
    String deviceId, {
    required String smdp,
    String matchingId = '',
    String confirmationCode = '',
    String aidHex = '',
    void Function(EsimDownloadProgress)? onProgress,
    RequestCancellation? cancellation,
  }) async {
    throw const ApiFailure(ApiFailureKind.timeout, requestId: 'download');
  }

  @override
  Future<EsimInventory> fetchProfiles(
    String deviceId, {
    required bool refresh,
    RequestCancellation? cancellation,
  }) async =>
      EsimInventory(hint: EsimInventoryHint.none, profiles: const [_profile]);
  @override
  Future<CardPolicy> fetchPolicy(
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async => const CardPolicy(apn: 'ims', ipVersion: CardIpVersion.ipv4v6);
  @override
  Future<EsimSwitchResult> switchProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    if (switchFails) {
      throw const ApiFailure(
        ApiFailureKind.http,
        requestId: 'switch',
        statusCode: 503,
      );
    }
    if (switchGate != null) return switchGate!.future;
    return EsimSwitchResult(
      status: EsimSwitchStatus.switched,
      verified: verified,
    );
  }

  @override
  Future<void> renameProfile(
    String deviceId,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  }) async {
    renames++;
    await renameGate?.future;
    if (renameError != null) throw renameError!;
  }

  @override
  Future<void> deleteProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    deletes++;
  }

  @override
  Future<CardPolicy> savePolicy(
    EsimSwitchTarget target, {
    required String apn,
    required CardIpVersion ipVersion,
    bool? networkEnabled,
    bool? vowifiEnabled,
    bool? airplaneEnabled,
    String? mbnProfile,
    CardVoicePath? voicePath,
    RequestCancellation? cancellation,
  }) async {
    if (policyFails) {
      throw const ApiFailure(
        ApiFailureKind.http,
        requestId: 'policy',
        statusCode: 503,
      );
    }
    return CardPolicy(apn: apn, ipVersion: ipVersion);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
