import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/state/device_detail_controller.dart';
import 'package:onewifi_android/features/devices/state/device_list_controller.dart';

/// P3 设备域回归：列表 / 详情 / 动作（capability · reconnectVowifi · reboot）。
void main() {
  group('list', () {
    test('loads fleet under the stable devices.list key', () async {
      final controller = DeviceListController(
        repository: _Repo(list: <_ListFn>[(_) async => _fleet('rack/a')]),
        requestRegistry: RequestRegistry(),
      );

      await controller.load();

      expect(controller.state.status, QueryStatus.data);
      expect(controller.state.key, 'devices.list');
      expect(controller.state.lastGoodData?.devices.single.id, 'rack/a');
      controller.dispose();
    });

    test('maps list 401 as unauthorized without fabricating empty', () async {
      final controller = DeviceListController(
        repository: _Repo(
          list: <_ListFn>[
            (_) async => throw const ApiFailure(
              ApiFailureKind.http,
              requestId: 'list-401',
              statusCode: 401,
              backendCode: 'unauthorized',
            ),
          ],
        ),
        requestRegistry: RequestRegistry(),
      );

      await controller.load();

      expect(controller.state.status, QueryStatus.failed);
      expect(controller.state.failure?.kind, StateFailureKind.authentication);
      expect(controller.state.failure?.statusCode, 401);
      expect(controller.state.lastGoodData, isNull);
      controller.dispose();
    });
  });

  group('detail', () {
    test('forwards encoded device id and lands in data', () async {
      const selectedId = 'slot/a b?c#d';
      String? captured;
      final controller = DeviceDetailController(
        deviceId: selectedId,
        repository: _Repo(
          detail: <_DetailFn>[
            (id, _) async {
              captured = id;
              return _detail(id);
            },
          ],
        ),
        requestRegistry: RequestRegistry(),
      );

      await controller.load();

      expect(captured, selectedId);
      expect(controller.state.key, 'devices.detail:$selectedId');
      expect(controller.state.status, QueryStatus.data);
      expect(controller.state.lastGoodData?.device.id, selectedId);
      controller.dispose();
    });

    test('detail 401 stays unauthorized failure', () async {
      final controller = DeviceDetailController(
        deviceId: 'device-a',
        repository: _Repo(
          detail: <_DetailFn>[
            (_, _) async => throw const ApiFailure(
              ApiFailureKind.http,
              requestId: 'detail-401',
              statusCode: 401,
              backendCode: 'unauthorized',
            ),
          ],
        ),
        requestRegistry: RequestRegistry(),
      );

      await controller.load();

      expect(controller.state.status, QueryStatus.failed);
      expect(controller.state.failure?.kind, StateFailureKind.authentication);
      expect(controller.state.failure?.statusCode, 401);
      controller.dispose();
    });
  });

  group('actions', () {
    test('capability write is single-flight and refreshes after success', () async {
      final writes = <(DeviceCapability, bool)>[];
      final controller = DeviceDetailController(
        deviceId: 'device-a',
        repository: _Repo(
          detail: <_DetailFn>[
            (id, _) async => _detail(id),
            (id, _) async => DeviceDetail(
              device: _snapshot(id).copyWith(flightMode: true),
              traffic: const DeviceTraffic.unavailable(),
            ),
          ],
          capability: (id, capability, enabled, _) async {
            expect(id, 'device-a');
            writes.add((capability, enabled));
          },
        ),
        requestRegistry: RequestRegistry(),
      );

      await controller.load();
      final pending =
          controller.setCapability(DeviceCapability.flightMode, true);
      controller.setCapability(DeviceCapability.network, false);
      await pending;

      expect(writes, <(DeviceCapability, bool)>[
        (DeviceCapability.flightMode, true),
      ]);
      expect(controller.state.lastGoodData?.device.flightMode, isTrue);
      expect(controller.action.status, ActionStatus.succeeded);
      controller.dispose();
    });

    test('reboot is single-flight and refreshes after success', () async {
      final reboots = <String>[];
      final controller = DeviceDetailController(
        deviceId: 'device-a',
        repository: _Repo(
          detail: <_DetailFn>[
            (id, _) async => _detail(id, trafficBytes: 1),
            (id, _) async => _detail(id, trafficBytes: 9),
          ],
          onReboot: (id, _) async => reboots.add(id),
        ),
        requestRegistry: RequestRegistry(),
      );

      await controller.load();
      final pending = controller.reboot();
      unawaited(controller.reboot());
      await pending;

      expect(reboots, <String>['device-a']);
      expect(controller.action.status, ActionStatus.succeeded);
      expect(controller.state.lastGoodData?.traffic.rxBytes, 9);
      controller.dispose();
    });

    test('reconnectVowifi succeeds and refreshes detail', () async {
      var reconnects = 0;
      final controller = DeviceDetailController(
        deviceId: 'device-a',
        repository: _Repo(
          detail: <_DetailFn>[
            (id, _) async => _detail(id, trafficBytes: 3),
            (id, _) async => _detail(id, trafficBytes: 4),
          ],
          reconnect: (_, _) async {
            reconnects += 1;
          },
        ),
        requestRegistry: RequestRegistry(),
      );

      await controller.load();
      await controller.reconnectVowifi();

      expect(reconnects, 1);
      expect(controller.action.status, ActionStatus.succeeded);
      expect(controller.state.lastGoodData?.traffic.rxBytes, 4);
      controller.dispose();
    });

    test('reboot network failure is unknown outcome', () async {
      final controller = DeviceDetailController(
        deviceId: 'device-a',
        repository: _Repo(
          detail: <_DetailFn>[(id, _) async => _detail(id)],
          onReboot: (_, _) async => throw const ApiFailure(
            ApiFailureKind.network,
            requestId: 'reboot-network',
          ),
        ),
        requestRegistry: RequestRegistry(),
      );

      await controller.load();
      await controller.reboot();

      expect(controller.action.status, ActionStatus.failed);
      expect(controller.action.isUnknownOutcome, isTrue);
      expect(controller.state.lastGoodData?.device.id, 'device-a');
      controller.dispose();
    });

    test('reboot conflict stays known and is not treated as unknown', () async {
      final controller = DeviceDetailController(
        deviceId: 'device-a',
        repository: _Repo(
          detail: <_DetailFn>[(id, _) async => _detail(id)],
          onReboot: (_, _) async => throw const ApiFailure(
            ApiFailureKind.http,
            requestId: 'reboot-conflict',
            statusCode: 409,
          ),
        ),
        requestRegistry: RequestRegistry(),
      );

      await controller.load();
      await controller.reboot();

      expect(controller.action.status, ActionStatus.failed);
      expect(controller.action.isUnknownOutcome, isFalse);
      expect(controller.action.knownFailure?.kind, StateFailureKind.conflict);
      controller.dispose();
    });
  });
}

typedef _ListFn = Future<DeviceFleet> Function(RequestCancellation? cancellation);
typedef _DetailFn =
    Future<DeviceDetail> Function(
      String deviceId,
      RequestCancellation? cancellation,
    );

DeviceFleet _fleet(String id) =>
    DeviceFleet(deviceLimit: 4, devices: <DeviceSnapshot>[_snapshot(id)]);

DeviceDetail _detail(String id, {int trafficBytes = 0}) {
  return DeviceDetail(
    device: _snapshot(id),
    traffic: DeviceTraffic.available(
      rxBytes: trafficBytes,
      txBytes: trafficBytes,
      rxRateBytesPerSecond: 0,
      txRateBytesPerSecond: 0,
      status: DeviceTrafficStatus.ready,
    ),
  );
}

DeviceSnapshot _snapshot(String id) {
  return DeviceSnapshot(
    id: id,
    name: 'Device $id',
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
      smsReady: false,
    ),
  );
}

final class _Repo implements DeviceRepository {
  _Repo({
    this.list = const <_ListFn>[],
    this.detail = const <_DetailFn>[],
    this.capability,
    this.reconnect,
    this.onReboot,
  });

  final List<_ListFn> list;
  final List<_DetailFn> detail;
  final Future<void> Function(
    String deviceId,
    DeviceCapability capability,
    bool enabled,
    RequestCancellation? cancellation,
  )?
  capability;
  final Future<void> Function(
    String deviceId,
    RequestCancellation? cancellation,
  )?
  reconnect;
  final Future<void> Function(
    String deviceId,
    RequestCancellation? cancellation,
  )?
  onReboot;
  int listIndex = 0;
  int detailIndex = 0;

  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) {
    return list[listIndex++](cancellation);
  }

  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) {
    return detail[detailIndex++](deviceId, cancellation);
  }

  @override
  Future<void> setCapability({
    required String deviceId,
    required DeviceCapability capability,
    required bool enabled,
    RequestCancellation? cancellation,
  }) {
    return (this.capability ?? ((_, _, _, _) => throw UnimplementedError()))(
      deviceId,
      capability,
      enabled,
      cancellation,
    );
  }

  @override
  Future<void> reconnectVowifi(
    String deviceId, {
    RequestCancellation? cancellation,
  }) {
    return (reconnect ?? ((_, _) => throw UnimplementedError()))(
      deviceId,
      cancellation,
    );
  }

  @override
  Future<void> reboot(String deviceId, {RequestCancellation? cancellation}) {
    return (onReboot ?? ((_, _) => throw UnimplementedError()))(
      deviceId,
      cancellation,
    );
  }

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
