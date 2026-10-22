import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/glass_dialog.dart';
import 'package:onewifi_android/features/esim/data/esim_repository.dart';
import 'package:onewifi_android/features/esim/domain/card_policy.dart';
import 'package:onewifi_android/features/esim/domain/esim.dart';
import 'package:onewifi_android/features/esim/presentation/esim_panel.dart';
import 'package:onewifi_android/features/esim/state/esim_controller.dart';

void main() {
  testWidgets('profiles are safe and switch requires one glass confirmation', (
    tester,
  ) async {
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(EsimPanel(controller: controller)));
    await tester.pump();

    expect(find.text('Travel line'), findsOneWidget);
    expect(find.text('ICCID · •••• 1234'), findsOneWidget);
    expect(find.text(repository.rawIccid), findsNothing);
    expect(find.text('已禁用'), findsOneWidget);
    // WEB 同款：点整块 eSIM 瓷片即发起切卡，没有单独的 Switch 按钮。
    await tester.tap(find.text('Travel line'));
    await tester.pumpAndSettle();
    expect(find.byType(OneGlassDialog), findsOneWidget);
    expect(find.text(repository.rawIccid), findsNothing);
    await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
    await tester.pump();

    expect(repository.switchCalls, 1);
    expect(find.bySemanticsLabel('正在切卡'), findsOneWidget);
    expect(find.text('切换中'), findsOneWidget);
    repository.switchResult.complete(
      const EsimSwitchResult(status: EsimSwitchStatus.switched, verified: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('已切换 eSIM'), findsOneWidget);
  });

  testWidgets('explicit chip read warns before using refresh=1', (
    tester,
  ) async {
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(EsimPanel(controller: controller)));
    await tester.pump();

    await tester.tap(find.text('读芯片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('短暂中断 VoWiFi'), findsOneWidget);
    await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
    await tester.pumpAndSettle();
    expect(repository.reads, <bool>[false, true]);
  });

  testWidgets('panel scrolls at 320dp and 200 percent text in both themes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final controller = _controller(_Repository());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          darkTheme: OneTheme.dark(),
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: EsimPanel(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -250),
      );
      await tester.pump();
      expect(find.text('ICCID · •••• 1234'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('edit eSIM opens the WEB card-management sheet', (tester) async {
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(EsimPanel(controller: controller)));
    await tester.pump();
    await tester.tap(find.text('编辑 eSIM'));
    await tester.pumpAndSettle();
    expect(find.text('卡片管理'), findsOneWidget);
    expect(find.text('下载 Profile'), findsOneWidget);
    expect(find.text('Travel line'), findsWidgets);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: OneTheme.light(),
  darkTheme: OneTheme.dark(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

EsimController _controller(EsimRepository repository) => EsimController(
  deviceId: 'device',
  repository: repository,
  requestRegistry: RequestRegistry(),
);

final class _Target implements EsimSwitchTarget {
  const _Target();
  @override
  String toString() => 'safe-target';
}

final class _Repository implements EsimRepository {
  final String rawIccid = List<String>.generate(
    20,
    (index) => ((index + 3) % 10).toString(),
  ).join();
  final Completer<EsimSwitchResult> switchResult =
      Completer<EsimSwitchResult>();
  final List<bool> reads = <bool>[];
  int switchCalls = 0;

  @override
  Future<EsimInventory> fetchProfiles(
    String deviceId, {
    required bool refresh,
    RequestCancellation? cancellation,
  }) async {
    reads.add(refresh);
    return EsimInventory(
      hint: EsimInventoryHint.none,
      profiles: const <EsimProfile>[
        EsimProfile(
          name: 'Travel line',
          provider: 'One Carrier',
          iccidDisplay: '•••• 1234',
          active: false,
          state: EsimProfileState.disabled,
          target: _Target(),
        ),
      ],
    );
  }

  @override
  Future<EsimSwitchResult> switchProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) {
    switchCalls += 1;
    return switchResult.future;
  }

  @override
  Future<CardPolicy> fetchPolicy(
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async => const CardPolicy(apn: 'ims', ipVersion: CardIpVersion.ipv4v6);

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
  }) async => CardPolicy(apn: apn, ipVersion: ipVersion);

  @override
  Future<void> downloadProfile(
    String deviceId, {
    required String smdp,
    String matchingId = '',
    String confirmationCode = '',
    String aidHex = '',
    void Function(EsimDownloadProgress progress)? onProgress,
    RequestCancellation? cancellation,
  }) async {}

  @override
  String aidHexOf(EsimSwitchTarget target) => '';

  @override
  Future<void> renameProfile(
    String deviceId,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<void> disableProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<void> deleteProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {}
}
