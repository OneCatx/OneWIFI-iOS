import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/features/proxy/data/proxy_repository.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_call_connection.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_call_group.dart';
import 'package:onewifi_android/features/proxy/presentation/proxy_screen.dart';
import 'package:onewifi_android/features/proxy/presentation/wifi_connection_sheet.dart';
import 'package:onewifi_android/features/proxy/presentation/wifi_country_sheet.dart';
import 'package:onewifi_android/features/proxy/presentation/wifi_node_sheet.dart';
import 'package:onewifi_android/features/proxy/state/proxy_controller.dart';

import '../../../support/centered_popup.dart';

void main() {
  testWidgets(
    'pins five countries, hides the rest behind plus, opens pickers',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ProxyController(
        repository: _Repo(),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(ProxyScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('香港'), findsOneWidget);
      expect(find.text('美国'), findsOneWidget);
      expect(find.text('日本'), findsNothing);
      expect(find.text('连接'), findsOneWidget);
      expect(find.text('120.53.53.53:443'), findsNothing);
      expect(find.text('jp.example.test:443'), findsOneWidget);
      expect(find.text('ePDG 234/030'), findsOneWidget);
      expect(find.text('epdg.epc.att.net:500'), findsNothing);
      expect(find.textContaining('英国 1.5×'), findsOneWidget);
      expect(find.textContaining('node-jp'), findsOneWidget);
      expect(find.textContaining('UK-WIFI →'), findsNothing);
      expect(find.textContaining('Cyber |'), findsNothing);
      expect(find.text('80ms'), findsOneWidget);
      expect(find.text('测速'), findsOneWidget);

      final hk = tester.getTopLeft(
        find.byKey(ProxyScreen.countryKey('HK-WIFI Selector')),
      );
      final us = tester.getTopLeft(
        find.byKey(ProxyScreen.countryKey('US-WIFI Selector')),
      );
      expect(hk.dy, us.dy);
      expect(hk.dx, lessThan(us.dx));
      expect(
        tester
            .getSize(find.byKey(ProxyScreen.countryKey('HK-WIFI Selector')))
            .height,
        82,
      );

      await tester.tap(find.byKey(ProxyScreen.plusKey));
      await tester.pumpAndSettle();
      expect(find.byKey(WifiCountrySheet.rootKey), findsOneWidget);
      expect(find.text('加到一级菜单'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('proxy-more-country-JP-WIFI Selector')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(WifiCountrySheet.rootKey), findsNothing);
      expect(find.text('日本'), findsOneWidget);

      await tester.tap(find.byKey(ProxyScreen.countryKey('HK-WIFI Selector')));
      await tester.pumpAndSettle();
      expect(find.byKey(WifiNodeSheet.rootKey), findsOneWidget);
      expectCenteredPopup(tester, find.byKey(WifiNodeSheet.rootKey));
      expect(find.byKey(WifiNodeSheet.probeKey), findsOneWidget);
      expect(find.text('TAG | 香港 家宽 02'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(WifiNodeSheet.rootKey),
          matching: find.text('80ms'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(WifiNodeSheet.rootKey),
          matching: find.text('超时'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(WifiNodeSheet.rootKey),
          matching: find.text('—'),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(WifiNodeSheet.nodeKey('TAG | 香港 家宽 02')));
      await tester.pumpAndSettle();
      expect(find.byKey(WifiNodeSheet.rootKey), findsNothing);

      await tester.tap(find.byKey(ProxyScreen.moreConnectionsKey));
      await tester.pumpAndSettle();
      expect(find.byKey(WifiConnectionSheet.rootKey), findsOneWidget);
      expectCenteredPopup(tester, find.byKey(WifiConnectionSheet.rootKey));
      expect(
        find.descendant(
          of: find.byKey(WifiConnectionSheet.rootKey),
          matching: find.text('jp.example.test:443'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(WifiConnectionSheet.rootKey),
          matching: find.text('ePDG 234/030'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(WifiConnectionSheet.rootKey),
          matching: find.text('120.53.53.53:443'),
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('proxy-unpin-HK')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ProxyScreen.countryKey('HK-WIFI Selector')),
        findsNothing,
      );
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: OneTheme.light(),
  darkTheme: OneTheme.dark(),
  home: Scaffold(body: child),
);

final class _Repo implements ProxyRepository {
  @override
  Future<List<WifiCallGroup>> fetchWifiCallGroups({
    RequestCancellation? cancellation,
  }) async {
    return const <WifiCallGroup>[
      WifiCallGroup(
        groupName: 'HK-WIFI Selector',
        countryCode: 'HK',
        countryName: '香港',
        flagEmoji: '🇭🇰',
        now: 'TAG | 香港 家宽 01',
        aliveCount: 1,
        totalCount: 2,
        nodes: <WifiCallNode>[
          WifiCallNode(name: 'TAG | 香港 家宽 01', alive: true, delayMs: 80),
          WifiCallNode(name: 'TAG | 香港 家宽 02', alive: false),
        ],
      ),
      WifiCallGroup(
        groupName: 'US-WIFI Selector',
        countryCode: 'US',
        countryName: '美国',
        flagEmoji: '🇺🇸',
        now: 'us-now',
        aliveCount: 1,
        totalCount: 1,
        nodes: <WifiCallNode>[WifiCallNode(name: 'us-now', alive: true)],
      ),
      WifiCallGroup(
        groupName: 'JP-WIFI Selector',
        countryCode: 'JP',
        countryName: '日本',
        flagEmoji: '🇯🇵',
        now: 'jp-now',
        aliveCount: 1,
        totalCount: 1,
        nodes: <WifiCallNode>[WifiCallNode(name: 'jp-now', alive: true)],
      ),
    ];
  }

  @override
  Future<List<WifiCallConnection>> fetchConnections({
    RequestCancellation? cancellation,
    List<WifiCallConnection>? previous,
    DateTime? previousAt,
    DateTime? now,
  }) async {
    return const <WifiCallConnection>[
      WifiCallConnection(
        id: 'direct',
        host: '120.53.53.53:443',
        chainLabel: 'DIRECT',
        direct: true,
      ),
      WifiCallConnection(
        id: 'jp',
        host: 'jp.example.test:443',
        chainLabel: 'JP-WIFI → node-jp',
        countryCode: 'JP',
      ),
      WifiCallConnection(
        id: 'uk',
        host: 'epdg.epc.mnc030.mcc234.pub.3gppnetwork.org:500',
        chainLabel: 'UK-WIFI → Cyber | 英国 1.5×',
        countryCode: 'UK',
      ),
    ];
  }

  @override
  Future<void> selectNode({
    required String group,
    required String name,
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<WifiDelay> probeDelay({
    required String name,
    String? altName,
    RequestCancellation? cancellation,
  }) async {
    return _lookup(name, altName);
  }

  @override
  Future<Map<String, WifiDelay>?> probeGroupDelay({
    required String name,
    RequestCancellation? cancellation,
  }) async {
    if (name != 'HK-WIFI Selector') return const <String, WifiDelay>{};
    return const <String, WifiDelay>{
      'TAG | 香港 家宽 01': WifiDelay.measured(80),
      'TAG | 香港 家宽 02': WifiDelay.timedOut(),
    };
  }

  static WifiDelay _lookup(String name, String? altName) {
    WifiDelay of(String value) => switch (value) {
      'TAG | 香港 家宽 01' => const WifiDelay.measured(80),
      'TAG | 香港 家宽 02' => const WifiDelay.timedOut(),
      'us-now' => const WifiDelay.measured(40),
      'jp-now' => const WifiDelay.measured(30),
      _ => const WifiDelay.unknown(),
    };
    final primary = of(name);
    if (primary.kind != WifiDelayKind.unknown) return primary;
    final alt = altName?.trim();
    if (alt == null || alt.isEmpty) return primary;
    return of(alt);
  }
}
