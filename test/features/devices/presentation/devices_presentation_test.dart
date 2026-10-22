import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/tokens/one_tokens.dart';
import 'package:onewifi_android/design/widgets/stage_row.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/presentation/device_detail_view.dart';
import 'package:onewifi_android/features/devices/presentation/devices_screen.dart';
import 'package:onewifi_android/features/devices/state/device_detail_controller.dart';
import 'package:onewifi_android/features/devices/state/device_list_controller.dart';

void main() {
  testWidgets('list shows safe card details and reports only its safe ID', (
    tester,
  ) async {
    String? selected;
    final controller = _listController(
      list: <_ListHandler>[(cancellation) async => _fleet('safe-id')],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        DevicesScreen(
          controller: controller,
          onDeviceSelected: (id) => selected = id,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Gateway'), findsOneWidget);
    expect(find.textContaining('PCIe EC20 / EC25'), findsNothing);
    // 走 VoWiFi 时只留 VoWiFi 牌，蜂窝驻留不再并排。
    expect(find.text('VoWiFi 在线'), findsOneWidget);
    expect(find.text('蜂窝驻留'), findsNothing);
    expect(find.text('在线'), findsNothing);
    expect(find.text('IMEI · •••• 1234'), findsNothing);
    expect(find.text('raw-imei-should-not-render'), findsNothing);
    expect(find.bySemanticsLabel('Gateway, VoWiFi 在线'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.text('Gateway'),
              matching: find.byType(InkWell),
            ),
          )
          .height,
      greaterThanOrEqualTo(OneSizes.minimumTarget),
    );
    await tester.tap(find.text('Gateway'));
    expect(selected, 'safe-id');
  });

  testWidgets(
    'list clearly presents empty, failure, stale, and refreshing data',
    (tester) async {
      final refresh = Completer<DeviceFleet>();
      final controller = _listController(
        list: <_ListHandler>[
          (_) async => DeviceFleet(deviceLimit: 4, devices: const []),
          (_) async => _fleet('stale-id'),
          (_) => refresh.future,
          (_) async => throw const ApiFailure(
            ApiFailureKind.network,
            requestId: 'private-request-id',
          ),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(DevicesScreen(controller: controller, onDeviceSelected: (_) {})),
      );
      await tester.pump();
      expect(find.text('没有设备'), findsOneWidget);
      // 刷新钮已去掉：空态 / 失败态也只靠下拉刷新。
      expect(find.text('Refresh'), findsNothing);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      await _pullToRefresh(tester);
      expect(find.text('Gateway'), findsOneWidget);
      await _pullToRefresh(tester);
      expect(find.bySemanticsLabel('正在刷新设备列表'), findsOneWidget);
      refresh.complete(_fleet('stale-id'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await _pullToRefresh(tester);
      expect(find.text('显示的是上次的设备数据'), findsOneWidget);
      expect(find.text('private-request-id'), findsNothing);
    },
  );

  testWidgets(
    'detail presents configured offline, zero traffic, back, and masked identity',
    (tester) async {
      var backed = false;
      final controller = _detailController(
        detail: <_DetailHandler>[(id, _) async => _detail(id, trafficBytes: 0)],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          DeviceDetailView(controller: controller, onBack: () => backed = true),
        ),
      );
      await tester.pump();

      expect(find.text('Gateway'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('IMEI'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('流量 · ↓ 0 B · ↑ 0 B'), findsOneWidget);
      expect(find.text('IMEI'), findsOneWidget);
      expect(find.text('•••• 1234'), findsOneWidget);
      expect(find.text('IMEI · •••• 1234'), findsNothing);
      expect(find.text('raw-imei-should-not-render'), findsNothing);
      expect(find.byKey(const Key('device-identities-reveal')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('开启网络'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('开启网络'), findsOneWidget);
      expect(find.text('VoWiFi'), findsOneWidget);
      expect(find.text('飞行模式'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      expect(backed, isTrue);

      final offline = _detailController(
        detail: <_DetailHandler>[
          (id, _) async => _detail(id, physicalPresent: false),
        ],
      );
      addTearDown(offline.dispose);
      await tester.pumpWidget(
        _app(DeviceDetailView(controller: offline, onBack: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('设备已配置但离线'), findsOneWidget);
      expect(find.text('流量不可用'), findsOneWidget);
    },
  );

  testWidgets('DJ-3 camped cell shows 蜂窝驻留 without lighting VoWiFi Access', (
    tester,
  ) async {
    final list = _listController(
      list: <_ListHandler>[
        (_) async =>
            DeviceFleet(deviceLimit: 4, devices: <DeviceSnapshot>[_dj3()]),
      ],
    );
    addTearDown(list.dispose);
    await tester.pumpWidget(
      _app(DevicesScreen(controller: list, onDeviceSelected: (_) {})),
    );
    await tester.pump();
    expect(find.text('DJ-3'), findsOneWidget);
    expect(find.text('蜂窝驻留'), findsOneWidget);
    expect(find.textContaining('China Mobile'), findsNothing);
    expect(find.textContaining('ASDA Mobile'), findsNothing);
    expect(find.text('无线路'), findsNothing);
    expect(find.text('VoWiFi 在线'), findsNothing);

    final detail = _detailController(
      detail: <_DetailHandler>[
        (id, _) async => DeviceDetail(
          device: _dj3(),
          traffic: const DeviceTraffic.unavailable(),
        ),
      ],
    );
    addTearDown(detail.dispose);
    await tester.pumpWidget(
      _app(DeviceDetailView(controller: detail, onBack: () {})),
    );
    await tester.pump();
    expect(find.text('数据'), findsOneWidget);
    expect(find.text('WiFi Call'), findsNothing);
    expect(find.text('驻网'), findsNothing);
    expect(find.text('漫游驻留'), findsOneWidget);
    expect(find.text('China Mobile · LTE B40 · -81 dBm'), findsOneWidget);
    expect(find.text('注网'), findsNothing);
    expect(find.text('服务小区'), findsNothing);
    expect(find.text('频段'), findsNothing);
    expect(find.text('信号'), findsNothing);
    expect(find.text('运行模式'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('原运营商'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('原运营商'), findsOneWidget);
    expect(find.text('ASDA Mobile'), findsWidgets);
    expect(
      tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byType(StageRow),
                  matching: find.text('Access'),
                )
                .first,
          )
          .style
          ?.fontWeight,
      FontWeight.w400,
    );
  });

  testWidgets('DJ-1 flight-mode VoWiFi does not paint 蜂窝驻留', (tester) async {
    final controller = _listController(
      list: <_ListHandler>[
        (_) async =>
            DeviceFleet(deviceLimit: 4, devices: <DeviceSnapshot>[_dj1()]),
      ],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(DevicesScreen(controller: controller, onDeviceSelected: (_) {})),
    );
    await tester.pump();
    expect(find.text('DJ-1'), findsOneWidget);
    expect(find.text('VoWiFi 在线'), findsOneWidget);
    expect(find.text('蜂窝驻留'), findsNothing);

    final detail = _detailController(
      detail: <_DetailHandler>[
        (id, _) async => DeviceDetail(
          device: _dj1(),
          traffic: const DeviceTraffic.unavailable(),
        ),
      ],
    );
    addTearDown(detail.dispose);
    await tester.pumpWidget(
      _app(DeviceDetailView(controller: detail, onBack: () {})),
    );
    await tester.pump();
    expect(find.text('WiFi Call'), findsOneWidget);
    expect(find.text('驻网'), findsNothing);
    expect(find.text('蜂窝驻留'), findsNothing);
    expect(find.text('漫游驻留'), findsNothing);
  });

  testWidgets('detail eye reveals and hides identity numbers', (tester) async {
    const fullImei = '490154203237518';
    final controller = _detailController(
      detail: <_DetailHandler>[
        (id, _) async =>
            _detail(id, imeiDisplay: '•••• 7518', imeiReveal: fullImei),
      ],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(DeviceDetailView(controller: controller, onBack: () {})),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('device-identities-reveal')),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('•••• 7518'), findsOneWidget);
    expect(find.text(fullImei), findsNothing);
    await tester.tap(find.byKey(const Key('device-identities-reveal')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text(fullImei),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text(fullImei), findsOneWidget);
    expect(find.text('•••• 7518'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('device-identities-reveal')),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.byKey(const Key('device-identities-reveal')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('•••• 7518'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('•••• 7518'), findsOneWidget);
    expect(find.text(fullImei), findsNothing);
  });

  testWidgets(
    'detail returns to list on 404 and keeps stale 403 data visible',
    (tester) async {
      var backs = 0;
      final controller = _detailController(
        detail: <_DetailHandler>[
          (id, _) async => _detail(id),
          (_, _) async => throw const ApiFailure(
            ApiFailureKind.http,
            requestId: 'forbidden-detail',
            statusCode: 403,
          ),
        ],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          DeviceDetailView(controller: controller, onBack: () => backs += 1),
        ),
      );
      await tester.pump();
      await _pullToRefresh(tester);
      await tester.pump();
      expect(find.text('显示的是上次的设备数据'), findsOneWidget);
      expect(find.text('forbidden-detail'), findsNothing);

      final missing = _detailController(
        detail: <_DetailHandler>[
          (_, _) async => throw const ApiFailure(
            ApiFailureKind.http,
            requestId: 'not-found-detail',
            statusCode: 404,
          ),
        ],
      );
      addTearDown(missing.dispose);
      await tester.pumpWidget(
        _app(DeviceDetailView(controller: missing, onBack: () => backs += 1)),
      );
      await tester.pump();
      expect(find.text('设备已不存在'), findsOneWidget);
      await tester.tap(find.text('返回设备列表'));
      expect(backs, 1);
    },
  );

  testWidgets(
    'list and detail scroll at 320 by 800 and 200 percent text in One themes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final listController = _listController(
        list: <_ListHandler>[
          (cancellation) async => _fleet(
            'narrow-id',
            name: 'An exceptionally long device name that must wrap safely',
          ),
        ],
      );
      addTearDown(listController.dispose);
      final detailController = _detailController(
        detail: <_DetailHandler>[
          (id, _) async => _detail(
            id,
            name: 'An exceptionally long device name that must wrap safely',
            imeiDisplay: '•••• •••• •••• 1234',
            trafficBytes: 999999999,
          ),
        ],
      );
      addTearDown(detailController.dispose);
      for (final brightness in <Brightness>[
        Brightness.light,
        Brightness.dark,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: OneTheme.light(),
            darkTheme: OneTheme.dark(),
            themeMode: brightness == Brightness.light
                ? ThemeMode.light
                : ThemeMode.dark,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: DevicesScreen(
                controller: listController,
                onDeviceSelected: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(RefreshIndicator), findsOneWidget);
        await tester.drag(find.byType(Scrollable), const Offset(0, -300));
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            theme: OneTheme.light(),
            darkTheme: OneTheme.dark(),
            themeMode: brightness == Brightness.light
                ? ThemeMode.light
                : ThemeMode.dark,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: DeviceDetailView(
                controller: detailController,
                onBack: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.text('An exceptionally long device name that must wrap safely'),
          findsOneWidget,
        );
        await tester.drag(find.byType(Scrollable), const Offset(0, -300));
        await tester.pump();
        await tester.scrollUntilVisible(
          find.text('IMEI'),
          300,
          scrollable: find.byType(Scrollable),
        );
        expect(find.text('IMEI'), findsOneWidget);
        expect(find.text('•••• •••• •••• 1234'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('流量 · ↓ 999999999 B · ↑ 999999999 B'),
          300,
          scrollable: find.byType(Scrollable),
        );
        expect(find.text('流量 · ↓ 999999999 B · ↑ 999999999 B'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'detail 404 replaces stale data and initial failures retain back and refresh',
    (tester) async {
      var backs = 0;
      final staleThenMissing = _detailController(
        detail: <_DetailHandler>[
          (id, _) async => _detail(id),
          (_, _) async => throw const ApiFailure(
            ApiFailureKind.http,
            requestId: 'missing-after-refresh',
            statusCode: 404,
          ),
        ],
      );
      addTearDown(staleThenMissing.dispose);
      await tester.pumpWidget(
        _app(
          DeviceDetailView(
            controller: staleThenMissing,
            onBack: () => backs += 1,
          ),
        ),
      );
      await tester.pump();
      await _pullToRefresh(tester);
      await tester.pump();
      expect(find.text('Gateway'), findsNothing);
      expect(find.text('设备已不存在'), findsOneWidget);
      await tester.tap(find.text('返回设备列表'));
      expect(backs, 1);

      for (final failure in <ApiFailure>[
        const ApiFailure(
          ApiFailureKind.http,
          requestId: 'initial-forbidden',
          statusCode: 403,
        ),
        const ApiFailure(ApiFailureKind.network, requestId: 'initial-network'),
      ]) {
        final controller = _detailController(
          detail: <_DetailHandler>[(id, _) async => throw failure],
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            DeviceDetailView(controller: controller, onBack: () => backs += 1),
          ),
        );
        await tester.pump();
        expect(find.text('Refresh'), findsNothing);
        expect(find.byType(RefreshIndicator), findsOneWidget);
        expect(find.byTooltip('返回'), findsOneWidget);
        await tester.tap(find.byTooltip('返回'));
      }
      expect(backs, 3);
    },
  );
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 真下拉一次：拖过 RefreshIndicator 的触发距离再放手，等它把 onRefresh 打出去。
Future<void> _pullToRefresh(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable), const Offset(0, 400));
  await tester.pump();
  // 指示器先动画到位再打 onRefresh；随后一帧画出 controller 的新状态；
  // 若 onRefresh 已经完成，再给指示器 200ms 的收回动画走完，否则它会一直
  // 留在 done 态、吞掉下一次下拉。
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

typedef _ListHandler =
    Future<DeviceFleet> Function(RequestCancellation? cancellation);
typedef _DetailHandler =
    Future<DeviceDetail> Function(String id, RequestCancellation? cancellation);

DeviceListController _listController({required List<_ListHandler> list}) =>
    DeviceListController(
      repository: _Repository(list: list, detail: const <_DetailHandler>[]),
      requestRegistry: RequestRegistry(),
    );

DeviceDetailController _detailController({
  required List<_DetailHandler> detail,
}) => DeviceDetailController(
  deviceId: 'safe-id',
  repository: _Repository(list: const <_ListHandler>[], detail: detail),
  requestRegistry: RequestRegistry(),
);

DeviceFleet _fleet(String id, {String name = 'Gateway'}) => DeviceFleet(
  deviceLimit: 4,
  devices: <DeviceSnapshot>[_snapshot(id, name: name)],
);

DeviceDetail _detail(
  String id, {
  bool physicalPresent = true,
  int trafficBytes = 1,
  String name = 'Gateway',
  String imeiDisplay = '•••• 1234',
  String? imeiReveal,
}) => DeviceDetail(
  device: _snapshot(
    id,
    name: name,
    physicalPresent: physicalPresent,
    imeiDisplay: imeiDisplay,
    imeiReveal: imeiReveal,
  ),
  traffic: physicalPresent
      ? DeviceTraffic.available(
          rxBytes: trafficBytes,
          txBytes: trafficBytes,
          rxRateBytesPerSecond: 0,
          txRateBytesPerSecond: 0,
          status: DeviceTrafficStatus.ready,
        )
      : const DeviceTraffic.unavailable(),
);

DeviceSnapshot _dj3() => _snapshot(
  'quectel-0125-2-1-2',
  name: 'DJ-3',
  physicalPresent: true,
  radioRegistered: true,
  flightMode: false,
  networkConnected: false,
  vowifiActive: false,
  accessReady: false,
  operatorName: 'ASDA Mobile',
  servingOperator: 'China Mobile',
  networkMode: 'LTE',
  radioBand: 'B40',
  regStatus: 5,
  regStatusText: 'registered (roaming)',
  signalRsrp: -81,
  signalDbm: -54,
);

DeviceSnapshot _dj1() => _snapshot(
  'quectel-0125-1',
  name: 'DJ-1',
  physicalPresent: true,
  radioRegistered: true,
  flightMode: true,
  networkConnected: false,
  vowifiActive: true,
  accessReady: true,
  operatorName: 'ASDA Mobile',
  servingOperator: 'China Mobile',
);

DeviceSnapshot _snapshot(
  String id, {
  String name = 'Gateway',
  bool physicalPresent = true,
  bool? radioRegistered,
  bool flightMode = false,
  bool? networkConnected,
  bool? vowifiActive,
  bool accessReady = true,
  String operatorName = 'Carrier',
  String servingOperator = '',
  String networkMode = 'LTE',
  String radioBand = 'B3',
  int regStatus = 1,
  String regStatusText = 'registered',
  int? signalRsrp,
  int signalDbm = -70,
  String imeiDisplay = '•••• 1234',
  String? imeiReveal,
}) {
  final present = physicalPresent;
  final wifi = vowifiActive ?? present;
  return DeviceSnapshot(
    id: id,
    name: name,
    type: DeviceType.pcieEc20Ec25,
    healthy: present,
    physicalPresent: present,
    controlOnline: present,
    radioLive: present,
    radioRegistered: radioRegistered ?? present,
    lifecyclePhase: present
        ? DeviceLifecyclePhase.ready
        : DeviceLifecyclePhase.missing,
    lifecycleReasonCategory: present
        ? DeviceReasonCategory.none
        : DeviceReasonCategory.reported,
    networkEnabled: true,
    networkConnected: networkConnected ?? present,
    vowifiEnabled: true,
    vowifiActive: wifi,
    smsEnabled: true,
    flightMode: flightMode,
    developerEnabled: false,
    modem: DeviceModem(
      operatorName: operatorName,
      servingOperator: servingOperator,
      model: 'EC25',
      firmware: 'safe-firmware',
      networkMode: networkMode,
      radioBand: radioBand,
      signalDbm: signalDbm,
      signalRsrp: signalRsrp,
      signalRsrq: null,
      signalSinr: 5,
      simPresent: present,
      serviceBlocked: false,
      blockedCategory: DeviceBlockedCategory.none,
      regStatus: regStatus,
      regStatusText: regStatusText,
    ),
    identities: DeviceIdentityDisplays(
      imeiDisplay: imeiDisplay,
      iccidDisplay: null,
      imsiDisplay: null,
      phoneDisplay: null,
      imeiReveal: imeiReveal,
    ),
    runtime: DeviceRuntime(
      phase: wifi ? DeviceRuntimePhase.imsReady : DeviceRuntimePhase.idle,
      simReady: wifi,
      accessReady: wifi && accessReady,
      tunnelReady: wifi,
      imsReady: wifi,
      smsReady: false,
    ),
  );
}

final class _Repository implements DeviceRepository {
  _Repository({required this.list, required this.detail});
  final List<_ListHandler> list;
  final List<_DetailHandler> detail;
  int _listIndex = 0;
  int _detailIndex = 0;
  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) =>
      list[_listIndex++](cancellation);
  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) => detail[_detailIndex++](deviceId, cancellation);

  @override
  Future<void> setCapability({
    required String deviceId,
    required DeviceCapability capability,
    required bool enabled,
    RequestCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<void> reconnectVowifi(
    String deviceId, {
    RequestCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<void> reboot(String deviceId, {RequestCancellation? cancellation}) =>
      throw UnimplementedError();
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
