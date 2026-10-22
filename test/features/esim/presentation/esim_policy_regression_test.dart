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
import 'package:onewifi_android/features/esim/presentation/widgets/esim_profile_editor.dart';
import 'package:onewifi_android/features/esim/state/esim_controller.dart';

void main() {
  for (final switchCard in [false, true]) {
    testWidgets('E1 current-card APN save switch=$switchCard', (t) async {
      await tall(t);
      final repo = ER();
      final e = ctrl(repo);
      final d = DeviceDetailController(
        deviceId: 'device',
        repository: DR(repo),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(e.dispose);
      addTearDown(d.dispose);
      await e.load();
      await d.load();
      await t.pumpWidget(
        app(DeviceDetailView(controller: d, esimController: e, onBack: () {})),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(DeviceDetailView.apnFieldKey))
            .controller!
            .text,
        'apn-A',
      );
      if (switchCard) {
        final b = e.inventory.lastGoodData!.profiles.singleWhere(
          (p) => p.target == bTarget,
        );
        await e.switchProfile(b);
        await t.pumpAndSettle();
        expect(e.policy.lastGoodData!.apn, 'apn-B');
      }
      await t.ensureVisible(find.text('保存 APN / IP'));
      await t.tap(find.text('保存 APN / IP'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(OneGlassDialog.confirmTargetKey));
      await t.pumpAndSettle();
      final id = switchCard ? 'B' : 'A';
      expect(repo.saves.single, (
        id,
        'apn-$id',
        switchCard ? CardIpVersion.ipv6 : CardIpVersion.ip,
      ));
    });
  }

  for (final collision in [false, true]) {
    testWidgets('E2 card drafts independent collision=$collision', (t) async {
      await tall(t);
      final repo = ER()..collision = collision;
      final e = ctrl(repo);
      addTearDown(e.dispose);
      await e.load();
      await t.pumpWidget(app(EsimEditSheet(controller: e)));
      await t.pumpAndSettle();
      final editors = find.byType(EsimProfileEditor);
      expect(editors, findsNWidgets(2));
      final aName = find
          .descendant(of: editors.at(0), matching: find.byType(TextField))
          .first;
      await t.enterText(aName, 'changed-A');
      final renameB = find.descendant(
        of: editors.at(1),
        matching: find.widgetWithText(FilledButton, '改名'),
      );
      await t.ensureVisible(renameB);
      await t.tap(renameB);
      await t.pumpAndSettle();
      expect(repo.renames.single, ('B', 'Line-B'));
    });
  }

  testWidgets('E3 ignored overlapping policy save must not show success', (
    t,
  ) async {
    await tall(t);
    final repo = ER()..saveGate = Completer<CardPolicy>();
    final e = ctrl(repo);
    addTearDown(e.dispose);
    await e.load();
    await t.pumpWidget(app(EsimEditSheet(controller: e)));
    await t.pumpAndSettle();
    final editors = find.byType(EsimProfileEditor);
    final saveA = find.descendant(
      of: editors.at(0),
      matching: find.widgetWithText(FilledButton, '保存卡策略'),
    );
    final saveB = find.descendant(
      of: editors.at(1),
      matching: find.widgetWithText(FilledButton, '保存卡策略'),
    );
    await t.ensureVisible(saveA);
    await t.tap(saveA);
    await t.pump();
    expect(repo.saves.length, 1);
    await t.ensureVisible(saveB);
    await t.tap(saveB);
    await t.pump();
    expect(
      repo.saves.length,
      1,
    ); // Guard ignored the B operation; no request was sent.
    final falselyCompleted = find.text('已完成').evaluate().isNotEmpty;
    repo.saveGate!.complete(
      const CardPolicy(apn: 'apn-A', ipVersion: CardIpVersion.ip),
    );
    await t.pumpAndSettle();
    expect(falselyCompleted, isFalse);
  });

  testWidgets('same-card refresh preserves an unsaved APN draft', (t) async {
    final (repo, e, _) = await devicePage(t);
    await t.enterText(find.byKey(DeviceDetailView.apnFieldKey), 'draft-A');
    await e.load();
    await t.pumpAndSettle();
    expect(apnText(t), 'draft-A');
    await t.tap(find.text('保存 APN / IP'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(OneGlassDialog.confirmTargetKey));
    await t.pumpAndSettle();
    expect(repo.saves.single, ('A', 'draft-A', CardIpVersion.ip));
  });

  testWidgets('card change while confirming cancels the stale submission', (
    t,
  ) async {
    final (repo, e, _) = await devicePage(t);
    await t.enterText(find.byKey(DeviceDetailView.apnFieldKey), 'draft-A');
    await t.tap(find.text('保存 APN / IP'));
    await t.pumpAndSettle();
    await e.switchProfile(e.inventory.lastGoodData!.profiles.last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(OneGlassDialog.confirmTargetKey));
    await t.pumpAndSettle();
    expect(repo.saves, isEmpty);
    expect(apnText(t), 'apn-B');
  });

  test('late save for A cannot replace current B policy', () async {
    final repo = ER()..saveGate = Completer<CardPolicy>();
    final e = ctrl(repo);
    addTearDown(e.dispose);
    await e.load();
    final pending = e.savePolicy(apn: 'saved-A', ipVersion: CardIpVersion.ip);
    await e.switchProfile(e.inventory.lastGoodData!.profiles.last);
    expect(e.policy.lastGoodData!.apn, 'apn-B');
    repo.saveGate!.complete(
      const CardPolicy(apn: 'saved-A', ipVersion: CardIpVersion.ip),
    );
    await pending;
    expect(e.policy.lastGoodData!.apn, 'apn-B');
  });

  test('saving inactive B does not replace active A policy', () async {
    final e = ctrl(ER());
    addTearDown(e.dispose);
    await e.load();
    await e.savePolicy(
      target: bTarget,
      apn: 'saved-B',
      ipVersion: CardIpVersion.ipv6,
    );
    expect(e.policy.lastGoodData!.apn, 'apn-A');
  });

  testWidgets(
    'unknown save retains confirmed cache and shows unknown outcome',
    (t) async {
      await tall(t);
      final repo = ER()..saveGate = Completer<CardPolicy>();
      final e = ctrl(repo);
      addTearDown(e.dispose);
      await e.load();
      await t.pumpWidget(app(EsimEditSheet(controller: e)));
      await t.pumpAndSettle();
      final editor = find.byType(EsimProfileEditor).first;
      final apn = find
          .descendant(of: editor, matching: find.byType(TextField))
          .last;
      await t.enterText(apn, 'failed-draft');
      await t.tap(
        find.descendant(
          of: editor,
          matching: find.widgetWithText(FilledButton, '保存卡策略'),
        ),
      );
      await t.pump();
      repo.saveGate!.completeError(
        const ApiFailure(ApiFailureKind.timeout, requestId: 'policy-failure'),
      );
      await t.pumpAndSettle();
      expect(e.policyAction.status, ActionStatus.failed);
      expect(t.widget<EsimProfileEditor>(editor).policy!.apn, 'apn-A');
      expect(find.text('已完成'), findsNothing);
      expect(e.policyAction.isUnknownOutcome, isTrue);
      expect(find.text('操作结果未知'), findsOneWidget);
      expect(t.widget<TextField>(apn).controller!.text, 'failed-draft');
    },
  );

  test(
    'a new card has no previous-card policy while its read is pending',
    () async {
      final repo = ER();
      final e = ctrl(repo);
      addTearDown(e.dispose);
      await e.load();
      final gate = repo.policyGates[bTarget] = Completer<CardPolicy>();
      final switching = e.switchProfile(
        e.inventory.lastGoodData!.profiles.last,
      );
      await pumpEventQueue();
      expect(e.policyTarget, bTarget);
      expect(e.policy.lastGoodData, isNull);
      gate.complete(
        const CardPolicy(apn: 'apn-B', ipVersion: CardIpVersion.ipv6),
      );
      await switching;
      expect(e.policy.lastGoodData!.apn, 'apn-B');
    },
  );

  test(
    'save returns this invocation result and keeps the first target',
    () async {
      final repo = ER()..saveGate = Completer<CardPolicy>();
      final e = ctrl(repo);
      addTearDown(e.dispose);
      await e.load();
      final first = e.savePolicy(apn: 'new-A', ipVersion: CardIpVersion.ip);
      expect(
        await e.savePolicy(
          target: bTarget,
          apn: 'new-B',
          ipVersion: CardIpVersion.ipv6,
        ),
        isFalse,
      );
      expect(repo.saves, [('A', 'new-A', CardIpVersion.ip)]);
      expect(e.policyActionTarget, aTarget);
      repo.saveGate!.complete(
        const CardPolicy(apn: 'new-A', ipVersion: CardIpVersion.ip),
      );
      expect(await first, isTrue);
      repo.saveGate = null;
      expect(
        await e.savePolicy(
          target: bTarget,
          apn: 'new-B',
          ipVersion: CardIpVersion.ipv6,
        ),
        isTrue,
      );
      expect(repo.saves.last, ('B', 'new-B', CardIpVersion.ipv6));
    },
  );

  test(
    'failed and disposed saves return false without a confirmed cache write',
    () async {
      final repo = ER()..saveGate = Completer<CardPolicy>();
      final e = ctrl(repo);
      addTearDown(e.dispose);
      await e.load();
      final saving = e.savePolicy(apn: 'new-A', ipVersion: CardIpVersion.ip);
      repo.saveGate!.completeError(
        const ApiFailure(
          ApiFailureKind.http,
          requestId: 'failed-policy',
          statusCode: 503,
        ),
      );
      expect(await saving, isFalse);
      expect(e.policy.lastGoodData!.apn, 'apn-A');
      repo.saveGate = Completer<CardPolicy>();
      final disposed = e.savePolicy(apn: 'late-A', ipVersion: CardIpVersion.ip);
      e.dispose();
      repo.saveGate!.complete(
        const CardPolicy(apn: 'late-A', ipVersion: CardIpVersion.ip),
      );
      expect(await disposed, isFalse);
      expect(e.policy.lastGoodData!.apn, 'apn-A');
    },
  );

  test('a stale policy read cannot undo a confirmed save', () async {
    final repo = ER();
    final e = ctrl(repo);
    addTearDown(e.dispose);
    await e.load();
    final gate = repo.policyGates[aTarget] = Completer<CardPolicy>();
    final loading = e.load();
    await pumpEventQueue();
    expect(
      await e.savePolicy(apn: 'confirmed-A', ipVersion: CardIpVersion.ip),
      isTrue,
    );
    gate.complete(const CardPolicy(apn: 'apn-A', ipVersion: CardIpVersion.ip));
    await loading;
    expect(e.policy.lastGoodData!.apn, 'confirmed-A');
  });
}

String apnText(WidgetTester t) => t
    .widget<TextField>(find.byKey(DeviceDetailView.apnFieldKey))
    .controller!
    .text;

Future<(ER, EsimController, DeviceDetailController)> devicePage(
  WidgetTester t,
) async {
  await tall(t);
  final repo = ER();
  final e = ctrl(repo);
  final d = DeviceDetailController(
    deviceId: 'device',
    repository: DR(repo),
    requestRegistry: RequestRegistry(),
  );
  addTearDown(e.dispose);
  addTearDown(d.dispose);
  await e.load();
  await d.load();
  await t.pumpWidget(
    app(DeviceDetailView(controller: d, esimController: e, onBack: () {})),
  );
  await t.pumpAndSettle();
  return (repo, e, d);
}

Future<void> tall(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(800, 5000));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

Widget app(Widget child) => MaterialApp(
  theme: OneTheme.light(),
  home: Scaffold(body: child),
);
EsimController ctrl(ER r) => EsimController(
  deviceId: 'device',
  repository: r,
  requestRegistry: RequestRegistry(),
);

class Target implements EsimSwitchTarget {
  const Target(this.id);
  final String id;
}

const aTarget = Target('A'), bTarget = Target('B');

class ER implements EsimRepository {
  String active = 'A';
  bool collision = false;
  Completer<CardPolicy>? saveGate;
  final policyGates = <EsimSwitchTarget, Completer<CardPolicy>>{};
  final saves = <(String, String, CardIpVersion)>[];
  final renames = <(String, String)>[];
  @override
  Future<EsimInventory> fetchProfiles(
    String id, {
    required bool refresh,
    RequestCancellation? cancellation,
  }) async => EsimInventory(
    hint: EsimInventoryHint.none,
    profiles: [
      for (final target in [aTarget, bTarget])
        EsimProfile(
          name: 'Line-${target.id}',
          provider: 'Carrier',
          eidDisplay: '•••• 9000',
          iccidDisplay: target == aTarget || collision
              ? '•••• 1234'
              : '•••• 5678',
          active: active == target.id,
          state: active == target.id
              ? EsimProfileState.enabled
              : EsimProfileState.disabled,
          target: target,
        ),
    ],
  );
  @override
  Future<EsimSwitchResult> switchProfile(
    String id,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    active = (target as Target).id;
    return const EsimSwitchResult(
      status: EsimSwitchStatus.switched,
      verified: true,
    );
  }

  @override
  Future<CardPolicy> fetchPolicy(
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async =>
      policyGates[target]?.future ??
      CardPolicy(
        apn: 'apn-${(target as Target).id}',
        ipVersion: target == aTarget ? CardIpVersion.ip : CardIpVersion.ipv6,
      );
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
  }) {
    saves.add(((target as Target).id, apn, ipVersion));
    return saveGate?.future ??
        Future.value(CardPolicy(apn: apn, ipVersion: ipVersion));
  }

  @override
  Future<void> renameProfile(
    String id,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  }) async {
    renames.add(((target as Target).id, name));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DR implements DeviceRepository {
  DR(this.repo);
  final ER repo;
  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String id, {
    RequestCancellation? cancellation,
  }) async => DeviceDetail(
    traffic: const DeviceTraffic.unavailable(),
    device: DeviceSnapshot(
      id: id,
      name: 'Gateway',
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
      vowifiEnabled: false,
      vowifiActive: false,
      smsEnabled: true,
      flightMode: false,
      developerEnabled: false,
      modem: const DeviceModem(
        operatorName: 'Carrier',
        model: 'EC25',
        firmware: '',
        networkMode: 'LTE',
        radioBand: 'B3',
        signalDbm: -70,
        signalRsrp: null,
        signalRsrq: null,
        signalSinr: 5,
        simPresent: true,
        serviceBlocked: false,
        blockedCategory: DeviceBlockedCategory.none,
      ),
      identities: DeviceIdentityDisplays(
        imeiDisplay: null,
        iccidDisplay: repo.active == 'A' ? '•••• 1234' : '•••• 5678',
        imsiDisplay: null,
        phoneDisplay: null,
      ),
      runtime: const DeviceRuntime(
        phase: DeviceRuntimePhase.idle,
        simReady: true,
        accessReady: false,
        tunnelReady: false,
        imsReady: false,
        smsReady: false,
      ),
    ),
  );
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
