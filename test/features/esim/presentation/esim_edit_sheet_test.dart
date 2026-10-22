import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/console_layout.dart';
import 'package:onewifi_android/design/widgets/glass_dialog.dart';
import 'package:onewifi_android/design/widgets/one_status_hero.dart';
import 'package:onewifi_android/features/esim/data/esim_repository.dart';
import 'package:onewifi_android/features/esim/domain/card_policy.dart';
import 'package:onewifi_android/features/esim/domain/esim.dart';
import 'package:onewifi_android/features/esim/domain/euicc_hardware.dart';
import 'package:onewifi_android/features/esim/domain/lpa_smdp_preview.dart';
import 'package:onewifi_android/features/esim/presentation/esim_edit_sheet.dart';
import 'package:onewifi_android/features/esim/state/esim_controller.dart';

void main() {
  testWidgets('showEsimEditSheet opens the modal sheet and 关闭 dismisses it', (
    tester,
  ) async {
    final controller = _controller(_Repository());
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        darkTheme: OneTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showEsimEditSheet(
                context: context,
                controller: controller,
                imeiDisplay: '•••• 4321',
                deviceOnline: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(EsimEditSheet), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('编辑 eSIM'), findsOneWidget);
    expect(find.widgetWithText(SoftLabel, '•••• 4321'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(EsimEditSheet), findsNothing);
  });

  testWidgets(
    'profiles tab renders header labels, eUICC groups and card states',
    (tester) async {
      await _tall(tester);
      final controller = _controller(_Repository());
      addTearDown(controller.dispose);
      await _pumpSheet(tester, controller, imeiDisplay: '•••• 4321');

      expect(find.text('编辑 eSIM'), findsOneWidget);
      expect(find.text('卡片管理'), findsOneWidget);
      expect(find.text('下载 Profile'), findsOneWidget);
      expect(find.text('下载 eSIM'), findsNothing);
      expect(find.widgetWithText(SoftLabel, 'Desk line'), findsOneWidget);
      expect(find.widgetWithText(SoftLabel, 'Two Carrier'), findsOneWidget);
      expect(find.widgetWithText(SoftLabel, '•••• 5678'), findsOneWidget);
      expect(find.widgetWithText(SoftLabel, '•••• 4321'), findsOneWidget);
      expect(find.text('—'), findsNothing);

      expect(find.text('eUICC'), findsNWidgets(2));
      expect(find.text('EID · •••• 9012'), findsOneWidget);
      expect(find.text('ICCID · •••• 1234'), findsOneWidget);
      expect(find.text('ICCID · •••• 5678'), findsOneWidget);
      expect(find.text('ICCID · •••• 0001'), findsOneWidget);
      expect(find.text('当前'), findsOneWidget);
      expect(find.text('已禁用'), findsOneWidget);
      expect(find.text('物理卡'), findsOneWidget);
      expect(find.text('已启用'), findsNothing);

      final travel = _editor('ICCID · •••• 1234');
      expect(_nameField(tester, travel).enabled, isTrue);
      expect(_button<FilledButton>(tester, travel, '改名').enabled, isTrue);
      expect(_button<OutlinedButton>(tester, travel, '启用').enabled, isTrue);
      expect(_button<OutlinedButton>(tester, travel, '删除').enabled, isTrue);

      final desk = _editor('ICCID · •••• 5678');
      expect(_nameField(tester, desk).enabled, isTrue);
      expect(_button<FilledButton>(tester, desk, '改名').enabled, isTrue);
      expect(_button<OutlinedButton>(tester, desk, '禁用').enabled, isTrue);
      expect(
        _button<OutlinedButton>(tester, desk, '当前启用的卡不能删，先切到别的卡').enabled,
        isFalse,
      );

      final sim = _editor('ICCID · •••• 0001');
      expect(_nameField(tester, sim).enabled, isFalse);
      expect(_button<FilledButton>(tester, sim, '改名').enabled, isFalse);
      expect(_button<OutlinedButton>(tester, sim, '启用').enabled, isFalse);
      expect(
        _button<OutlinedButton>(tester, sim, '物理卡不能从芯片删除').enabled,
        isFalse,
      );
    },
  );

  testWidgets('eUICC groups take slot label and capacity from hardware', (
    tester,
  ) async {
    await _tall(tester);
    final controller = _controller(_Repository(), overviewLoader: _overview);
    addTearDown(controller.dispose);
    await _pumpSheet(tester, controller);

    expect(find.text('eSIM 1'), findsOneWidget);
    expect(
      find.text('Thales DIS France SAS · EID · •••• 9012 · 可用 634.55 KB'),
      findsOneWidget,
    );
    expect(find.text('eUICC'), findsOneWidget);
    expect(find.text('EID · •••• 9012'), findsNothing);
  });

  testWidgets('empty inventory shows the 没有 eSIM hero', (tester) async {
    await _tall(tester);
    final controller = _controller(
      _Repository(profiles: const <EsimProfile>[]),
    );
    addTearDown(controller.dispose);
    await _pumpSheet(tester, controller);

    expect(find.text('没有 eSIM'), findsOneWidget);
    expect(find.text('先读芯片，或到「下载 Profile」写入一张。'), findsOneWidget);
    expect(find.widgetWithText(SoftLabel, '—'), findsNWidgets(3));
    expect(find.text('保存卡策略'), findsNothing);
  });

  testWidgets('card policy loads per card, then shows controls or 暂不可用', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    // 控制器自己的 load() 也会读一次策略；只卡住随后由本表单发出的逐卡读取。
    await controller.load();
    repository.policyGate = Completer<CardPolicy>();
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(_policyProgress, findsNWidgets(3));
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    expect(find.text('保存卡策略'), findsNothing);
    expect(find.text('卡策略暂不可用'), findsNothing);

    repository.policyGate!.complete(
      const CardPolicy(apn: 'ims', ipVersion: CardIpVersion.ipv4v6),
    );
    await tester.pump();
    expect(_policyProgress, findsNothing);
    expect(find.text('开启网络'), findsNWidgets(3));
    expect(find.text('VoWiFi'), findsNWidgets(3));
    expect(find.text('飞行模式'), findsNWidgets(3));
    expect(find.text('IP 版本'), findsNWidgets(3));
    expect(find.text('IPv4v6'), findsNWidgets(3));
    expect(find.text('APN（可选）'), findsNWidgets(3));
    expect(find.widgetWithText(TextField, 'ims'), findsNWidgets(3));
    expect(find.text('保存卡策略'), findsNWidgets(3));
    for (final tile in tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    )) {
      expect(tile.value, isTrue);
    }

    final failing = _controller(_Repository()..policyFails = true);
    addTearDown(failing.dispose);
    await _pumpSheet(tester, failing);
    expect(find.text('卡策略暂不可用'), findsNWidgets(3));
    expect(find.text('保存卡策略'), findsNothing);
    expect(_policyProgress, findsNothing);
  });

  testWidgets('deviceOnline only changes the policy hint of the active card', (
    tester,
  ) async {
    await _tall(tester);
    final offline = _controller(_Repository());
    addTearDown(offline.dispose);
    await _pumpSheet(tester, offline, deviceOnline: false);

    expect(find.text('设备离线：改动已保存，上线后生效'), findsOneWidget);
    expect(find.text('未激活卡：改动将在此卡激活后生效'), findsNWidgets(2));
    expect(find.text('当前在线卡：改动立即生效'), findsNothing);
    final desk = _editor('ICCID · •••• 5678');
    expect(
      find.descendant(of: desk, matching: find.text('设备离线：改动已保存，上线后生效')),
      findsOneWidget,
    );
    expect(_button<FilledButton>(tester, desk, '改名').enabled, isTrue);
    expect(_button<OutlinedButton>(tester, desk, '禁用').enabled, isTrue);
    expect(_button<FilledButton>(tester, desk, '保存卡策略').enabled, isTrue);

    final online = _controller(_Repository());
    addTearDown(online.dispose);
    await _pumpSheet(tester, online, deviceOnline: true);
    expect(find.text('当前在线卡：改动立即生效'), findsOneWidget);
    expect(find.text('设备离线：改动已保存，上线后生效'), findsNothing);
    expect(find.text('未激活卡：改动将在此卡激活后生效'), findsNWidgets(2));
  });

  testWidgets('改名 rejects a blank draft and otherwise sends the trimmed name', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pumpSheet(tester, controller);
    final travel = _editor('ICCID · •••• 1234');
    final field = find.descendant(of: travel, matching: find.byType(TextField));

    await tester.enterText(field.first, '   ');
    await tester.tap(
      find.descendant(
        of: travel,
        matching: find.widgetWithText(FilledButton, '改名'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.renameCalls, 0);
    expect(find.text('操作失败'), findsOneWidget);
    expect(find.text('卡名字不能为空'), findsOneWidget);

    await tester.enterText(field.first, '  Beach line ');
    await tester.tap(
      find.descendant(
        of: travel,
        matching: find.widgetWithText(FilledButton, '改名'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.renameCalls, 1);
    expect(repository.renamedTo, 'Beach line');
    expect(repository.renamedTarget, same(_travelTarget));
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('操作失败'), findsNothing);
    expect(find.text('卡名字不能为空'), findsNothing);
  });

  testWidgets('a rejected mutation reports 网关没有确认这项改动。', (tester) async {
    await _tall(tester);
    final repository = _Repository()..renameFails = true;
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pumpSheet(tester, controller);
    final travel = _editor('ICCID · •••• 1234');

    await tester.tap(
      find.descendant(
        of: travel,
        matching: find.widgetWithText(FilledButton, '改名'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.renameCalls, 1);
    expect(find.text('操作失败'), findsOneWidget);
    expect(find.text('网关没有确认这项改动。'), findsOneWidget);
    expect(find.text('已完成'), findsNothing);
  });

  testWidgets(
    '启用 and 禁用 go through the controller; submitting locks the sheet',
    (tester) async {
      await _tall(tester);
      final repository = _Repository()
        ..switchGate = Completer<EsimSwitchResult>();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await _pumpSheet(tester, controller);
      final travel = _editor('ICCID · •••• 1234');
      final desk = _editor('ICCID · •••• 5678');

      await tester.tap(
        find.descendant(
          of: travel,
          matching: find.widgetWithText(OutlinedButton, '启用'),
        ),
      );
      await tester.pump();
      expect(repository.switchCalls, 1);
      expect(repository.switchedTarget, same(_travelTarget));
      expect(_closeButton(tester).onPressed, isNull);
      expect(_nameField(tester, travel).enabled, isFalse);
      expect(_button<FilledButton>(tester, travel, '改名').enabled, isFalse);
      expect(_button<OutlinedButton>(tester, travel, '启用').enabled, isFalse);
      expect(_button<OutlinedButton>(tester, travel, '删除').enabled, isFalse);
      expect(_button<OutlinedButton>(tester, desk, '禁用').enabled, isFalse);
      expect(_button<FilledButton>(tester, desk, '保存卡策略').enabled, isFalse);
      await tester.tap(find.text('下载 Profile'));
      await tester.pump();
      expect(find.text('下载 eSIM'), findsNothing);
      expect(find.text('ICCID · •••• 1234'), findsOneWidget);

      repository.switchGate!.complete(
        const EsimSwitchResult(
          status: EsimSwitchStatus.switched,
          verified: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已完成'), findsOneWidget);
      expect(_closeButton(tester).onPressed, isNotNull);
      expect(_button<OutlinedButton>(tester, travel, '启用').enabled, isTrue);

      await tester.tap(
        find.descendant(
          of: desk,
          matching: find.widgetWithText(OutlinedButton, '禁用'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.disableCalls, 1);
      expect(repository.disabledTarget, same(_deskTarget));
      expect(repository.switchCalls, 1);
      expect(find.text('已完成'), findsOneWidget);
    },
  );

  testWidgets('删除 asks for one glass confirmation before calling the gateway', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pumpSheet(tester, controller);
    final travel = _editor('ICCID · •••• 1234');
    final delete = find.descendant(
      of: travel,
      matching: find.widgetWithText(OutlinedButton, '删除'),
    );

    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.byType(OneGlassDialog), findsOneWidget);
    expect(find.text('删除 eSIM？'), findsOneWidget);
    expect(
      find.text('删除「Travel line」（尾号 •••• 1234）？芯片上的这张配置会清掉，本机无法恢复。'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(OneGlassDialog.cancelTargetKey));
    await tester.pumpAndSettle();
    expect(find.byType(OneGlassDialog), findsNothing);
    expect(repository.deleteCalls, 0);
    expect(find.text('已完成'), findsNothing);

    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
    await tester.pumpAndSettle();
    expect(find.byType(OneGlassDialog), findsNothing);
    expect(repository.deleteCalls, 1);
    expect(repository.deletedTarget, same(_travelTarget));
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('保存卡策略 sends the edited switches, IP version and APN', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pumpSheet(tester, controller);
    final desk = _editor('ICCID · •••• 5678');

    await tester.tap(
      find.descendant(
        of: desk,
        matching: find.widgetWithText(SwitchListTile, '开启网络'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.descendant(
              of: desk,
              matching: find.widgetWithText(SwitchListTile, '开启网络'),
            ),
          )
          .value,
      isFalse,
    );
    await tester.tap(
      find.descendant(
        of: desk,
        matching: find.byType(DropdownButtonFormField<CardIpVersion>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('IPv6').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: desk, matching: find.text('IPv6')),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(of: desk, matching: find.byType(TextField)).last,
      ' internet ',
    );
    await tester.tap(
      find.descendant(
        of: desk,
        matching: find.widgetWithText(FilledButton, '保存卡策略'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.policySaves, 1);
    expect(repository.savedTarget, same(_deskTarget));
    expect(repository.savedApn, 'internet');
    expect(repository.savedIpVersion, CardIpVersion.ipv6);
    expect(repository.savedNetwork, isFalse);
    expect(repository.savedVowifi, isTrue);
    expect(repository.savedAirplane, isTrue);
    expect(repository.savedMbn, '');
    expect(repository.savedVoicePath, CardVoicePath.vowifi);
    expect(find.text('MBN 配置'), findsWidgets);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('操作失败'), findsNothing);
  });

  testWidgets('download tab gates 下载 on the LPA field and fails bad codes', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pumpSheet(tester, controller);

    await tester.tap(find.text('下载 Profile'));
    await tester.pumpAndSettle();
    expect(find.text('下载 eSIM'), findsOneWidget);
    expect(find.text('粘贴 LPA 激活码。失败后不会自动重试。'), findsOneWidget);
    expect(find.byKey(EsimPanelLpaKey.value), findsOneWidget);
    expect(find.text(r'LPA:1$smdp$matching'), findsOneWidget);
    expect(find.text('ICCID · •••• 1234'), findsNothing);
    expect(find.text('取消'), findsNothing);
    expect(
      _button<FilledButton>(tester, find.byType(ListView), '下载').enabled,
      isFalse,
    );

    await tester.enterText(find.byKey(EsimPanelLpaKey.value), '   ');
    await tester.pump();
    expect(
      _button<FilledButton>(tester, find.byType(ListView), '下载').enabled,
      isFalse,
    );

    await tester.enterText(find.byKey(EsimPanelLpaKey.value), 'LPA:');
    await tester.pump();
    expect(
      _button<FilledButton>(tester, find.byType(ListView), '下载').enabled,
      isTrue,
    );
    await tester.tap(find.widgetWithText(FilledButton, '下载'));
    await tester.pumpAndSettle();
    expect(repository.downloadCalls, 0);
    expect(find.text('操作失败'), findsOneWidget);
    expect(find.text('下载失败'), findsNWidgets(2));
    expect(find.text('需要有效的 SM-DP+ 地址或 LPA 激活码'), findsOneWidget);

    await tester.tap(find.text('卡片管理'));
    await tester.pumpAndSettle();
    expect(find.text('下载 eSIM'), findsNothing);
    expect(find.text('ICCID · •••• 1234'), findsOneWidget);
    expect(find.text('操作失败'), findsOneWidget);
    expect(find.text('下载失败'), findsOneWidget);
  });

  testWidgets('download shows 下载中… with 取消 while the gateway is busy', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repository()..downloadGate = Completer<void>();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pumpSheet(tester, controller);
    await tester.tap(find.text('下载 Profile'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(EsimPanelLpaKey.value),
      r'LPA:1$smdp.example.com$MATCH',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '下载'));
    await tester.pump();
    expect(repository.downloadCalls, 1);
    expect(repository.downloadSmdp, 'smdp.example.com');
    expect(repository.downloadMatchingId, 'MATCH');
    expect(repository.downloadConfirmationCode, '');
    expect(find.text('下载中…'), findsOneWidget);
    expect(find.text('下载'), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('下载进度 0%'), findsOneWidget);
    expect(find.text('开始下载'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(EsimPanelLpaKey.value)).enabled,
      isFalse,
    );
    expect(_closeButton(tester).onPressed, isNull);

    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pump();
    expect(find.text('取消'), findsNothing);
    expect(find.text('下载中…'), findsNothing);
    expect(
      _button<FilledButton>(tester, find.byType(ListView), '下载').enabled,
      isTrue,
    );
    expect(find.text('下载进度 0%'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNotNull);
    expect(find.text('已完成'), findsNothing);
  });

  testWidgets(
    'a download that returns after 取消 leaves no completion feedback',
    (tester) async {
      await _tall(tester);
      final repository = _Repository()
        ..downloadGate = Completer<void>()
        ..reportDownloadDone = true;
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await _pumpSheet(tester, controller);
      await tester.tap(find.text('下载 Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(EsimPanelLpaKey.value),
        r'LPA:1$smdp.example.com$MATCH',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '下载'));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
      await tester.pump();
      expect(find.text('取消'), findsNothing);

      repository.downloadGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.downloadCalls, 1);
      expect(find.text('已完成'), findsNothing);
      expect(find.text('下载完成'), findsNothing);
      expect(find.text('操作失败'), findsNothing);
      expect(find.text('下载进度 0%'), findsOneWidget);
      expect(
        _button<FilledButton>(tester, find.byType(ListView), '下载').enabled,
        isTrue,
      );
    },
  );

  testWidgets('download preview shows country and size for a known SM-DP+', (
    tester,
  ) async {
    await _tall(tester);
    final controller = _controller(_Repository(), overviewLoader: _overview);
    addTearDown(controller.dispose);
    await _pumpSheet(tester, controller, previewCatalog: _nekokoCatalog());
    await tester.tap(find.text('下载 Profile'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(EsimPanelLpaKey.value),
      r'LPA:1$sm-v4-018-gra-gtm.pr.go-esim.com$abc',
    );
    await tester.pump();
    expect(find.byKey(EsimPanelLpaPreviewKey.value), findsOneWidget);
    expect(find.textContaining('希腊'), findsOneWidget);
    expect(find.textContaining('58.9 KB'), findsOneWidget);
  });

  testWidgets(
    'download preview marks an unknown SM-DP+ and hides on empty code',
    (tester) async {
      await _tall(tester);
      final controller = _controller(_Repository());
      addTearDown(controller.dispose);
      await _pumpSheet(tester, controller, previewCatalog: _nekokoCatalog());
      await tester.tap(find.text('下载 Profile'));
      await tester.pumpAndSettle();

      expect(find.byKey(EsimPanelLpaPreviewKey.value), findsNothing);

      await tester.enterText(
        find.byKey(EsimPanelLpaKey.value),
        r'1$no-such-smdp.invalid$abc',
      );
      await tester.pump();
      expect(find.text('未收录此 SM-DP+'), findsOneWidget);

      await tester.enterText(find.byKey(EsimPanelLpaKey.value), '');
      await tester.pump();
      expect(find.byKey(EsimPanelLpaPreviewKey.value), findsNothing);
      expect(find.text('未收录此 SM-DP+'), findsNothing);
    },
  );

  testWidgets('a finished download reports 下载完成 and re-reads the inventory', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repository()..reportDownloadDone = true;
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pumpSheet(tester, controller);
    await tester.tap(find.text('下载 Profile'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(EsimPanelLpaKey.value),
      r'1$smdp.example.com$MATCH$CODE',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '下载'));
    await tester.pumpAndSettle();
    expect(repository.downloadCalls, 1);
    expect(repository.downloadSmdp, 'smdp.example.com');
    expect(repository.downloadMatchingId, 'MATCH');
    expect(repository.downloadConfirmationCode, 'CODE');
    expect(repository.reads, <bool>[false, false]);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('下载完成'), findsOneWidget);
    expect(find.text('操作失败'), findsNothing);
    expect(find.text('取消'), findsNothing);
    expect(
      _button<FilledButton>(tester, find.byType(ListView), '下载').enabled,
      isTrue,
    );
  });

  testWidgets('sheet scrolls at 320dp and 200 percent text in both themes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final controller = _controller(_Repository());
      addTearDown(controller.dispose);
      await controller.load();
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
              body: EsimEditSheet(
                key: ObjectKey(controller),
                controller: controller,
                imeiDisplay: '•••• 4321',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('编辑 eSIM'), findsOneWidget);
      expect(find.widgetWithText(SoftLabel, '•••• 4321'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('ICCID · •••• 0001'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('ICCID · •••• 0001'), findsOneWidget);
      expect(find.text('物理卡'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

LpaSmdpCatalog _nekokoCatalog() => LpaSmdpCatalog.fromJson(
  jsonDecode(File('assets/esim/lpa_smdp_preview.db.json').readAsStringSync()),
);

Widget _app(
  EsimController controller, {
  String? imeiDisplay,
  bool deviceOnline = false,
  LpaSmdpCatalog? previewCatalog,
}) => MaterialApp(
  theme: OneTheme.light(),
  darkTheme: OneTheme.dark(),
  home: Scaffold(
    body: EsimEditSheet(
      // 同一用例里换控制器再 pump 时必须换 State，否则旧的策略缓存会留下来。
      key: ObjectKey(controller),
      controller: controller,
      imeiDisplay: imeiDisplay,
      deviceOnline: deviceOnline,
      previewCatalog: previewCatalog,
    ),
  ),
);

Future<void> _tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

EsimController _controller(
  EsimRepository repository, {
  EuiccOverviewLoader? overviewLoader,
}) => EsimController(
  deviceId: 'device',
  repository: repository,
  requestRegistry: RequestRegistry(),
  overviewLoader: overviewLoader,
);

Future<void> _pumpSheet(
  WidgetTester tester,
  EsimController controller, {
  String? imeiDisplay,
  bool deviceOnline = false,
  LpaSmdpCatalog? previewCatalog,
}) async {
  await controller.load();
  await tester.pumpWidget(
    _app(
      controller,
      imeiDisplay: imeiDisplay,
      deviceOnline: deviceOnline,
      previewCatalog: previewCatalog,
    ),
  );
  await tester.pump();
}

Finder _editor(String iccidLine) => find
    .ancestor(of: find.text(iccidLine), matching: find.byType(GlassTile))
    .first;

T _button<T extends ButtonStyleButton>(
  WidgetTester tester,
  Finder scope,
  String label,
) => tester.widget<T>(
  find.descendant(of: scope, matching: find.widgetWithText(T, label)),
);

TextField _nameField(WidgetTester tester, Finder editor) =>
    tester.widget<TextField>(
      find.descendant(of: editor, matching: find.byType(TextField)).first,
    );

IconButton _closeButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close));

/// 卡片瓷片的 Semantics 会把进度标签并进整块瓷片，故按控件而非语义标签找。
final Finder _policyProgress = find.byWidgetPredicate(
  (widget) => widget is OneStatusProgress && widget.label == '正在读取卡策略',
);

Future<EuiccOverview> _overview(
  String deviceId, {
  RequestCancellation? cancellation,
}) async => EuiccOverview(
  hardware: const <EuiccHardware>[
    EuiccHardware(
      index: 0,
      eidDisplay: '•••• 9012',
      chipMaker: 'Thales DIS France SAS',
      freeNvram: '634.55 KB',
      freeNvramBytes: 649780,
      nameplate: 'ESTK.me',
      eidPrefix: '89049032',
    ),
  ],
  profiles: _profiles,
);

final class _Target implements EsimSwitchTarget {
  const _Target(this.id);
  final String id;
  @override
  String toString() => 'target:$id';
}

const _Target _travelTarget = _Target('travel');
const _Target _deskTarget = _Target('desk');
const _Target _simTarget = _Target('sim');

const List<EsimProfile> _profiles = <EsimProfile>[
  EsimProfile(
    name: 'Travel line',
    provider: 'One Carrier',
    iccidDisplay: '•••• 1234',
    active: false,
    state: EsimProfileState.disabled,
    target: _travelTarget,
    eidDisplay: '•••• 9012',
  ),
  EsimProfile(
    name: 'Desk line',
    provider: 'Two Carrier',
    iccidDisplay: '•••• 5678',
    active: true,
    state: EsimProfileState.enabled,
    target: _deskTarget,
    eidDisplay: '•••• 9012',
  ),
  EsimProfile(
    name: 'Physical SIM',
    provider: 'Local',
    iccidDisplay: '•••• 0001',
    active: false,
    state: EsimProfileState.enabled,
    target: _simTarget,
    locked: true,
  ),
];

final class _Repository implements EsimRepository {
  _Repository({this.profiles = _profiles});

  final List<EsimProfile> profiles;
  Completer<CardPolicy>? policyGate;
  bool policyFails = false;
  Completer<EsimSwitchResult>? switchGate;
  Completer<void>? downloadGate;
  bool reportDownloadDone = false;
  bool renameFails = false;

  final List<bool> reads = <bool>[];
  int switchCalls = 0;
  int disableCalls = 0;
  int deleteCalls = 0;
  int renameCalls = 0;
  int downloadCalls = 0;
  int policySaves = 0;
  EsimSwitchTarget? switchedTarget;
  EsimSwitchTarget? disabledTarget;
  EsimSwitchTarget? deletedTarget;
  EsimSwitchTarget? renamedTarget;
  String? renamedTo;
  String? downloadSmdp;
  String? downloadMatchingId;
  String? downloadConfirmationCode;
  EsimSwitchTarget? savedTarget;
  String? savedApn;
  CardIpVersion? savedIpVersion;
  bool? savedNetwork;
  bool? savedVowifi;
  bool? savedAirplane;
  String? savedMbn;
  CardVoicePath? savedVoicePath;

  @override
  Future<EsimInventory> fetchProfiles(
    String deviceId, {
    required bool refresh,
    RequestCancellation? cancellation,
  }) async {
    reads.add(refresh);
    return EsimInventory(hint: EsimInventoryHint.none, profiles: profiles);
  }

  @override
  Future<EsimSwitchResult> switchProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) {
    switchCalls += 1;
    switchedTarget = target;
    final gate = switchGate;
    if (gate != null) return gate.future;
    return Future<EsimSwitchResult>.value(
      const EsimSwitchResult(status: EsimSwitchStatus.switched, verified: true),
    );
  }

  @override
  Future<CardPolicy> fetchPolicy(
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    if (policyFails) {
      throw const ApiFailure(
        ApiFailureKind.http,
        requestId: 'policy',
        statusCode: 503,
      );
    }
    final gate = policyGate;
    if (gate != null) return gate.future;
    return const CardPolicy(apn: 'ims', ipVersion: CardIpVersion.ipv4v6);
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
    policySaves += 1;
    savedTarget = target;
    savedApn = apn;
    savedIpVersion = ipVersion;
    savedNetwork = networkEnabled;
    savedVowifi = vowifiEnabled;
    savedAirplane = airplaneEnabled;
    savedMbn = mbnProfile;
    savedVoicePath = voicePath;
    return CardPolicy(
      apn: apn,
      ipVersion: ipVersion,
      networkEnabled: networkEnabled ?? true,
      vowifiEnabled: vowifiEnabled ?? true,
      airplaneEnabled: airplaneEnabled ?? true,
      mbnProfile: mbnProfile ?? '',
    );
  }

  @override
  Future<void> downloadProfile(
    String deviceId, {
    required String smdp,
    String matchingId = '',
    String confirmationCode = '',
    String aidHex = '',
    void Function(EsimDownloadProgress progress)? onProgress,
    RequestCancellation? cancellation,
  }) async {
    downloadCalls += 1;
    downloadSmdp = smdp;
    downloadMatchingId = matchingId;
    downloadConfirmationCode = confirmationCode;
    final gate = downloadGate;
    if (gate != null) await gate.future;
    if (reportDownloadDone) {
      onProgress?.call(
        const EsimDownloadProgress(step: 'done', message: '写入完成', percent: 100),
      );
    }
  }

  @override
  String aidHexOf(EsimSwitchTarget target) => '';

  @override
  Future<void> renameProfile(
    String deviceId,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  }) async {
    renameCalls += 1;
    renamedTarget = target;
    if (renameFails) {
      throw const ApiFailure(
        ApiFailureKind.http,
        requestId: 'rename',
        statusCode: 500,
      );
    }
    renamedTo = name;
  }

  @override
  Future<void> disableProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    disableCalls += 1;
    disabledTarget = target;
  }

  @override
  Future<void> deleteProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    deleteCalls += 1;
    deletedTarget = target;
  }
}
