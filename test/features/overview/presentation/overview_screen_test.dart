import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/design/one/dot_matrix_face.dart';
import 'package:onewifi_android/design/one/one_status_hero.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/features/overview/data/overview_repository.dart';
import 'package:onewifi_android/features/overview/domain/overview.dart';
import 'package:onewifi_android/features/overview/presentation/overview_screen.dart';
import 'package:onewifi_android/features/overview/state/overview_controller.dart';

void main() {
  testWidgets('loading renders the Working hero without a stage row', (
    tester,
  ) async {
    final controller = _controller(
      host: <_HostHandler>[() => Completer<HostOverview>().future],
      devices: <_DevicesHandler>[
        () => Completer<List<DeviceOverview>>().future,
      ],
    );
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    final hero = find.byType(OneStatusHero);
    expect(hero, findsOneWidget);
    expect(_heroTexts(tester, hero), <String>['正在加载概览', '处理中', '正在检查主机与设备健康。']);
    expect(find.text('关闭'), findsNothing);
    expect(find.text('就绪'), findsNothing);
    expect(find.text('注意'), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(_face(tester).mood, DotMatrixMood.frown);
    expect(_face(tester).semanticLabel, '处理中');
    expect(tester.getSemantics(hero).label, '正在加载概览\n处理中\n正在检查主机与设备健康。');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('正在加载概览'), findsOneWidget);
    expect(find.text('主机'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty renders the Alert hero with subtitle and detail', (
    tester,
  ) async {
    final controller = _controller(
      host: <_HostHandler>[() async => _host(empty: true)],
      devices: <_DevicesHandler>[() async => const <DeviceOverview>[]],
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final hero = find.byType(OneStatusHero);
    expect(hero, findsOneWidget);
    expect(_heroTexts(tester, hero), <String>[
      '没有概览数据',
      '注意',
      '主机与设备都没有上报活动。',
      '下拉刷新。',
    ]);
    expect(find.text('关闭'), findsNothing);
    expect(find.text('处理中'), findsNothing);
    expect(find.text('就绪'), findsNothing);
    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(_face(tester).mood, DotMatrixMood.frown);
    expect(_face(tester).semanticLabel, '注意');
    expect(tester.getSemantics(hero).label, '没有概览数据\n注意\n主机与设备都没有上报活动。\n下拉刷新。');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('正在加载概览'), findsNothing);
    expect(find.text('主机'), findsNothing);
    expect(find.text('主机数据不可用。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both sides failing on first load renders the partial hero '
      'and the host section failure, never the unavailable hero', (
    tester,
  ) async {
    final controller = _controller(
      host: <_HostHandler>[
        () async => throw const ApiFailure(
          ApiFailureKind.network,
          requestId: 'host-failure',
        ),
      ],
      devices: <_DevicesHandler>[
        () async => throw const ApiFailure(
          ApiFailureKind.timeout,
          requestId: 'devices-failure',
        ),
      ],
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final hero = find.byType(OneStatusHero);
    expect(hero, findsOneWidget);
    expect(_heroTexts(tester, hero), <String>[
      '部分概览数据不可用',
      '注意',
      '失败的区块恢复期间，已显示的数据会保留。',
    ]);
    expect(find.text('概览不可用'), findsNothing);
    expect(find.text('服务无法提供主机或设备数据。'), findsNothing);
    expect(find.text('关闭'), findsNothing);
    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(_face(tester).mood, DotMatrixMood.frown);
    expect(_face(tester).semanticLabel, '注意');
    expect(
      tester.getSemantics(hero).label,
      '部分概览数据不可用\n注意\n失败的区块恢复期间，已显示的数据会保留。',
    );
    expect(find.text('主机数据不可用。'), findsOneWidget);
    expect(find.text('主机'), findsNothing);
    expect(find.bySemanticsLabel('正在刷新概览'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial failure renders the Alert hero and keeps host panels', (
    tester,
  ) async {
    final controller = _controller(
      host: <_HostHandler>[() async => _host()],
      devices: <_DevicesHandler>[
        () async => throw const ApiFailure(
          ApiFailureKind.http,
          requestId: 'forbidden',
          statusCode: 403,
        ),
      ],
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final hero = find.byType(OneStatusHero);
    expect(hero, findsOneWidget);
    expect(_heroTexts(tester, hero), <String>[
      '部分概览数据不可用',
      '注意',
      '失败的区块恢复期间，已显示的数据会保留。',
    ]);
    expect(find.text('关闭'), findsNothing);
    expect(find.text('处理中'), findsNothing);
    expect(find.text('就绪'), findsNothing);
    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(_face(tester).mood, DotMatrixMood.frown);
    expect(_face(tester).semanticLabel, '注意');
    expect(
      tester.getSemantics(hero).label,
      '部分概览数据不可用\n注意\n失败的区块恢复期间，已显示的数据会保留。',
    );
    expect(find.text('主机'), findsOneWidget);
    expect(find.text('主机数据不可用。'), findsNothing);
    expect(find.bySemanticsLabel('正在刷新概览'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all healthy renders the Ready hero with title and pill only', (
    tester,
  ) async {
    final controller = _controller(
      host: <_HostHandler>[() async => _host()],
      devices: <_DevicesHandler>[
        () async => <DeviceOverview>[_device('one'), _device('two')],
      ],
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final hero = find.byType(OneStatusHero);
    expect(hero, findsOneWidget);
    expect(_heroTexts(tester, hero), <String>['OneWIFI', '就绪']);
    expect(find.text('关闭'), findsNothing);
    expect(find.text('处理中'), findsNothing);
    expect(find.text('就绪'), findsOneWidget);
    expect(find.text('注意'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(_face(tester).mood, DotMatrixMood.smile);
    expect(_face(tester).semanticLabel, '就绪');
    expect(tester.getSemantics(hero).label, 'OneWIFI\n就绪');
    expect(find.text('主机'), findsOneWidget);
    expect(find.text('主机数据不可用。'), findsNothing);
    expect(find.bySemanticsLabel('正在刷新概览'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unhealthy devices render the Alert hero with the health count', (
    tester,
  ) async {
    final controller = _controller(
      host: <_HostHandler>[() async => _host()],
      devices: <_DevicesHandler>[
        () async => <DeviceOverview>[
          _device('one'),
          _device('two', healthy: false),
          _device('three'),
        ],
      ],
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final hero = find.byType(OneStatusHero);
    expect(hero, findsOneWidget);
    expect(_heroTexts(tester, hero), <String>[
      'OneWIFI 概览',
      '注意',
      '主机在线 · 3 台设备中 2 台健康',
    ]);
    expect(find.text('关闭'), findsNothing);
    expect(find.text('处理中'), findsNothing);
    expect(find.text('就绪'), findsNothing);
    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(_face(tester).mood, DotMatrixMood.frown);
    expect(_face(tester).semanticLabel, '注意');
    expect(
      tester.getSemantics(hero).label,
      'OneWIFI 概览\n注意\n主机在线 · 3 台设备中 2 台健康',
    );
    expect(find.text('主机'), findsOneWidget);
    expect(find.text('主机数据不可用。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshing keeps the Ready hero and adds the linear progress', (
    tester,
  ) async {
    final hostRefresh = Completer<HostOverview>();
    final devicesRefresh = Completer<List<DeviceOverview>>();
    final controller = _controller(
      host: <_HostHandler>[() async => _host(), () => hostRefresh.future],
      devices: <_DevicesHandler>[
        () async => <DeviceOverview>[_device('one')],
        () => devicesRefresh.future,
      ],
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('正在刷新概览'), findsNothing);

    unawaited(controller.refresh());
    await tester.pump();

    final hero = find.byType(OneStatusHero);
    expect(hero, findsOneWidget);
    expect(_heroTexts(tester, hero), <String>['OneWIFI', '就绪']);
    expect(find.text('关闭'), findsNothing);
    expect(find.text('处理中'), findsNothing);
    expect(_face(tester).mood, DotMatrixMood.smile);
    expect(_face(tester).semanticLabel, '就绪');
    expect(tester.getSemantics(hero).label, 'OneWIFI\n就绪');
    final progress = find.bySemanticsLabel('正在刷新概览');
    expect(progress, findsOneWidget);
    expect(
      find.descendant(
        of: progress,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.text('主机'), findsOneWidget);
    expect(tester.takeException(), isNull);

    hostRefresh.complete(_host());
    devicesRefresh.complete(<DeviceOverview>[_device('one')]);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('正在刷新概览'), findsNothing);
    expect(_heroTexts(tester, hero), <String>['OneWIFI', '就绪']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview scrolls on a 320dp surface at text scale 2', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() {
      FlutterError.onError = originalOnError;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;

    final heroTexts = <List<String?>>[];
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final controller = _controller(
        host: <_HostHandler>[() async => _host()],
        devices: <_DevicesHandler>[
          () async => <DeviceOverview>[
            _device('one'),
            _device('two', healthy: false),
          ],
        ],
      );
      await tester.pumpWidget(_app(controller, brightness: brightness));
      await tester.pumpAndSettle();
      heroTexts.add(_heroTexts(tester, find.byType(OneStatusHero)));
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    FlutterError.onError = originalOnError;

    expect(heroTexts, <List<String>>[
      <String>['OneWIFI 概览', '注意', '主机在线 · 2 台设备中 1 台健康'],
      <String>['OneWIFI 概览', '注意', '主机在线 · 2 台设备中 1 台健康'],
    ]);
    expect(find.text('关闭'), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      errors.where(
        (details) => details.exceptionAsString().contains('overflowed'),
      ),
      isEmpty,
    );
    expect(errors, isEmpty);
  });
}

typedef _HostHandler = Future<HostOverview> Function();
typedef _DevicesHandler = Future<List<DeviceOverview>> Function();

Widget _app(
  OverviewController controller, {
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: OneTheme.light(),
    darkTheme: OneTheme.dark(),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(body: OverviewScreen(controller: controller)),
  );
}

OverviewController _controller({
  required List<_HostHandler> host,
  required List<_DevicesHandler> devices,
}) {
  final controller = OverviewController(
    repository: _Repository(host: host, devices: devices),
    requestRegistry: RequestRegistry(),
  );
  addTearDown(controller.dispose);
  return controller;
}

List<String?> _heroTexts(WidgetTester tester, Finder hero) {
  return tester
      .widgetList<Text>(find.descendant(of: hero, matching: find.byType(Text)))
      .map((text) => text.data)
      .toList(growable: false);
}

DotMatrixFace _face(WidgetTester tester) =>
    tester.widget<DotMatrixFace>(find.byType(DotMatrixFace));

HostOverview _host({bool empty = false}) => empty
    ? const HostOverview(
        cpuModel: '',
        boardModel: '',
        cpuPercent: 0,
        memoryPercent: 0,
        memoryUsedBytes: 0,
        memoryTotalBytes: 0,
        diskPercent: 0,
        diskUsedBytes: 0,
        diskTotalBytes: 0,
        netRxBps: 0,
        netTxBps: 0,
      )
    : const HostOverview(
        cpuModel: 'Qualcomm X75',
        boardModel: 'One Board',
        cpuPercent: 12.5,
        memoryPercent: 31.25,
        memoryUsedBytes: 4294967296,
        memoryTotalBytes: 8589934592,
        diskPercent: 42.75,
        diskUsedBytes: 12884901888,
        diskTotalBytes: 34359738368,
        netRxBps: 1024.5,
        netTxBps: 512.25,
      );

DeviceOverview _device(String id, {bool healthy = true}) => DeviceOverview(
  id: id,
  name: 'Device $id',
  model: 'EC25',
  type: 'pcie_ec20_ec25',
  healthy: healthy,
  operatorName: 'One Carrier',
  signalDbm: -73,
  networkMode: 'LTE',
  vowifiActive: healthy,
  networkConnected: healthy,
  runtime: DeviceRuntimeOverview(
    phase: healthy ? DeviceRuntimePhase.imsReady : DeviceRuntimePhase.failed,
    simReady: true,
    accessReady: healthy,
    tunnelReady: healthy,
    imsReady: healthy,
    smsReady: false,
  ),
);

final class _Repository implements OverviewRepository {
  _Repository({required this.host, required this.devices});

  final List<_HostHandler> host;
  final List<_DevicesHandler> devices;
  int _hostIndex = 0;
  int _devicesIndex = 0;

  @override
  Future<HostOverview> fetchHost({RequestCancellation? cancellation}) {
    return host[_hostIndex++]();
  }

  @override
  Future<List<DeviceOverview>> fetchDevices({
    RequestCancellation? cancellation,
  }) {
    return devices[_devicesIndex++]();
  }
}
