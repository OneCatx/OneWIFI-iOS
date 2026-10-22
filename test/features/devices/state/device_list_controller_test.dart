import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/state/device_list_controller.dart';
import 'package:onewifi_android/features/esim/domain/esim.dart';
import 'package:onewifi_android/features/esim/domain/euicc_hardware.dart';

void main() {
  test('loads fleet into data with the stable list request key', () async {
    RequestCancellation? capturedCancellation;
    final registry = RequestRegistry();
    final controller = DeviceListController(
      repository: _Repository(
        list: <_ListHandler>[
          (cancellation) async {
            capturedCancellation = cancellation;
            return _fleet('device-a');
          },
        ],
      ),
      requestRegistry: registry,
    );

    final pending = controller.load();
    expect(controller.state.status, QueryStatus.loading);
    expect(controller.state.key, 'devices.list');
    await pending;

    expect(controller.state.status, QueryStatus.data);
    expect(controller.state.lastGoodData?.devices.single.id, 'device-a');
    expect(capturedCancellation, isNotNull);

    final probe = registry.register('devices.list');
    expect(
      capturedCancellation?.isCancelled,
      isFalse,
      reason: 'a completed registration must have been removed',
    );
    registry.remove('devices.list', probe);
    controller.dispose();
  });

  test('uses empty only after a successful empty fleet', () async {
    final controller = _listController(<_ListHandler>[
      (_) async => DeviceFleet(deviceLimit: 4, devices: const []),
    ]);

    await controller.load();

    expect(controller.state.status, QueryStatus.empty);
    expect(controller.state.failure, isNull);
    expect(controller.state.lastGoodData, isNull);
    controller.dispose();
  });

  test('maps initial forbidden without fabricating empty or data', () async {
    final controller = _listController(<_ListHandler>[
      (_) async => throw const ApiFailure(
        ApiFailureKind.http,
        requestId: 'list-forbidden',
        statusCode: 403,
      ),
    ]);

    await controller.load();

    expect(controller.state.status, QueryStatus.failed);
    expect(controller.state.failure?.kind, StateFailureKind.forbidden);
    expect(controller.state.failure?.statusCode, 403);
    expect(controller.state.lastGoodData, isNull);
    expect(controller.state.isStale, isFalse);
    controller.dispose();
  });

  test('refresh keeps last-good fleet and marks a failure stale', () async {
    final controller = _listController(<_ListHandler>[
      (_) async => _fleet('last-good'),
      (_) async => throw const ApiFailure(
        ApiFailureKind.network,
        requestId: 'list-refresh',
      ),
    ]);
    await controller.load();

    final pending = controller.refresh();
    expect(controller.state.status, QueryStatus.refreshing);
    expect(controller.state.lastGoodData?.devices.single.id, 'last-good');
    await pending;

    expect(controller.state.status, QueryStatus.failed);
    expect(controller.state.failure?.kind, StateFailureKind.network);
    expect(controller.state.isStale, isTrue);
    expect(controller.state.lastGoodData?.devices.single.id, 'last-good');
    controller.dispose();
  });

  test('replacement cancels and discards the old late generation', () async {
    final oldResult = Completer<DeviceFleet>();
    final oldCancellation = Completer<RequestCancellation?>();
    final controller = _listController(<_ListHandler>[
      (cancellation) {
        oldCancellation.complete(cancellation);
        return oldResult.future;
      },
      (_) async => _fleet('newest'),
    ]);

    final oldPending = controller.load();
    final cancellation = await oldCancellation.future;
    final newPending = controller.refresh();
    expect(cancellation?.isCancelled, isTrue);
    await newPending;
    expect(controller.state.lastGoodData?.devices.single.id, 'newest');

    oldResult.complete(_fleet('too-late'));
    await oldPending;
    expect(controller.state.status, QueryStatus.data);
    expect(controller.state.lastGoodData?.devices.single.id, 'newest');
    controller.dispose();
  });

  test('dispose cancels and suppresses late notification and commit', () async {
    final result = Completer<DeviceFleet>();
    final capturedCancellation = Completer<RequestCancellation?>();
    final controller = _listController(<_ListHandler>[
      (cancellation) {
        capturedCancellation.complete(cancellation);
        return result.future;
      },
    ]);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    final pending = controller.load();
    final cancellation = await capturedCancellation.future;
    expect(notifications, 1);
    controller.dispose();
    expect(cancellation?.isCancelled, isTrue);
    result.complete(_fleet('too-late'));
    await pending;

    expect(notifications, 1);
    expect(controller.state.status, QueryStatus.loading);
  });

  test('overview loader feeds hardware and card names per device', () async {
    final loaded = <String>[];
    final controller = DeviceListController(
      repository: _Repository(list: <_ListHandler>[(_) async => _fleet('m1')]),
      requestRegistry: RequestRegistry(),
      overviewLoader: (deviceId, {cancellation}) async {
        loaded.add(deviceId);
        return EuiccOverview(
          hardware: const <EuiccHardware>[
            EuiccHardware(
              index: 0,
              eidDisplay: '•••• 8901',
              chipMaker: 'G+D Mobile Security GmbH',
              freeNvram: '634.55 KB',
              freeNvramBytes: 649779,
              nameplate: 'G+D天联',
            ),
          ],
          profiles: <EsimProfile>[
            EsimProfile(
              name: 'Travel eSIM',
              provider: 'One Carrier',
              iccidDisplay: '•••• 1234',
              active: true,
              state: EsimProfileState.enabled,
              target: _Target(),
            ),
          ],
        );
      },
    );

    await controller.load();
    // 总览是列表落地后逐台补读的，等一轮微任务让它写回。
    await Future<void>.delayed(Duration.zero);

    expect(loaded, <String>['m1']);
    expect(controller.hardwareFor('m1')?.single.nameplate, 'G+D天联');
    expect(controller.deviceIdNamed('Device m1'), 'm1');
    expect(controller.deviceIdNamed('nobody'), isNull);
    expect(controller.cardNameFor('m1', '•••• 1234'), 'Travel eSIM');
    expect(controller.enabledCardNameFor('m1'), 'Travel eSIM');
    expect(controller.enabledCardNameFor('ghost'), isNull);
    expect(controller.cardNameFor('m1', '•••• 9999'), isNull);
    expect(controller.cardNameFor('m1', ''), isNull);
    expect(controller.cardNameFor('ghost', '•••• 1234'), isNull);
    controller.dispose();
  });

  test('overview loader failure never fails the fleet list', () async {
    final controller = DeviceListController(
      repository: _Repository(list: <_ListHandler>[(_) async => _fleet('m1')]),
      requestRegistry: RequestRegistry(),
      overviewLoader: (deviceId, {cancellation}) async =>
          throw const ApiFailure(ApiFailureKind.network, requestId: 'euicc'),
    );

    await controller.load();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, QueryStatus.data);
    expect(controller.hardwareFor('m1'), isNull);
    expect(controller.cardNameFor('m1', '•••• 1234'), isNull);
    controller.dispose();
  });

  test('projects protocol timeout and service failures safely', () async {
    final cases = <(Object, StateFailureKind)>[
      (
        const FormatException('unsafe parser detail'),
        StateFailureKind.protocol,
      ),
      (
        const ApiFailure(ApiFailureKind.timeout, requestId: 'list-timeout'),
        StateFailureKind.timeout,
      ),
      (
        const ApiFailure(
          ApiFailureKind.http,
          requestId: 'list-service-lower',
          statusCode: 500,
        ),
        StateFailureKind.unavailable,
      ),
      (
        const ApiFailure(
          ApiFailureKind.http,
          requestId: 'list-service-upper',
          statusCode: 599,
        ),
        StateFailureKind.unavailable,
      ),
      (
        const ApiFailure(
          ApiFailureKind.http,
          requestId: 'list-unmapped-600',
          statusCode: 600,
        ),
        StateFailureKind.generic,
      ),
    ];

    for (final testCase in cases) {
      final controller = _listController(<_ListHandler>[
        (_) async => throw testCase.$1,
      ]);
      await controller.load();
      expect(controller.state.failure?.kind, testCase.$2);
      if (testCase.$1 case final ApiFailure failure) {
        expect(controller.state.failure?.statusCode, failure.statusCode);
      }
      controller.dispose();
    }
  });

  test('PERF-P4: overview fan-out does not wait for catalogSync', () async {
    final catalogGate = Completer<void>();
    final overviewStarted = Completer<void>();
    var overviewCalls = 0;

    final controller = DeviceListController(
      repository: _Repository(list: <_ListHandler>[(_) async => _fleet('m1')]),
      requestRegistry: RequestRegistry(),
      catalogSync: () => catalogGate.future,
      overviewLoader: (deviceId, {cancellation}) async {
        overviewCalls += 1;
        if (!overviewStarted.isCompleted) {
          overviewStarted.complete();
        }
        return EuiccOverview(
          hardware: const <EuiccHardware>[
            EuiccHardware(
              index: 0,
              eidDisplay: '****8901',
              chipMaker: 'G+D Mobile Security GmbH',
              freeNvram: '634.55 KB',
              freeNvramBytes: 649779,
              nameplate: 'G+D天联',
            ),
          ],
          profiles: const <EsimProfile>[],
        );
      },
    );

    final pending = controller.load();
    await overviewStarted.future.timeout(const Duration(seconds: 2));
    expect(overviewCalls, greaterThan(0));
    expect(catalogGate.isCompleted, isFalse);

    catalogGate.complete();
    await pending;
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, QueryStatus.data);
    expect(controller.hardwareFor('m1')?.single.nameplate, 'G+D天联');
    controller.dispose();
  });
}

typedef _ListHandler =
    Future<DeviceFleet> Function(RequestCancellation? cancellation);

final class _Target implements EsimSwitchTarget {}

DeviceListController _listController(List<_ListHandler> handlers) {
  return DeviceListController(
    repository: _Repository(list: handlers),
    requestRegistry: RequestRegistry(),
  );
}

DeviceFleet _fleet(String id) {
  return DeviceFleet(deviceLimit: 4, devices: <DeviceSnapshot>[_snapshot(id)]);
}

DeviceSnapshot _snapshot(String id, {bool physicalPresent = true}) {
  return DeviceSnapshot(
    id: id,
    name: 'Device $id',
    type: DeviceType.pcieEc20Ec25,
    healthy: physicalPresent,
    physicalPresent: physicalPresent,
    controlOnline: physicalPresent,
    radioLive: physicalPresent,
    radioRegistered: physicalPresent,
    lifecyclePhase: physicalPresent
        ? DeviceLifecyclePhase.ready
        : DeviceLifecyclePhase.missing,
    lifecycleReasonCategory: physicalPresent
        ? DeviceReasonCategory.none
        : DeviceReasonCategory.reported,
    networkEnabled: true,
    networkConnected: physicalPresent,
    vowifiEnabled: true,
    vowifiActive: physicalPresent,
    smsEnabled: true,
    flightMode: false,
    developerEnabled: false,
    modem: DeviceModem(
      operatorName: physicalPresent ? 'Carrier' : '',
      model: physicalPresent ? 'EC25' : '',
      firmware: null,
      networkMode: physicalPresent ? 'LTE' : '',
      radioBand: physicalPresent ? 'B3' : '',
      signalDbm: physicalPresent ? -70 : 0,
      signalRsrp: null,
      signalRsrq: null,
      signalSinr: 0,
      simPresent: physicalPresent,
      serviceBlocked: false,
      blockedCategory: DeviceBlockedCategory.none,
    ),
    identities: const DeviceIdentityDisplays(
      imeiDisplay: null,
      iccidDisplay: null,
      imsiDisplay: null,
      phoneDisplay: null,
    ),
    runtime: DeviceRuntime(
      phase: physicalPresent
          ? DeviceRuntimePhase.imsReady
          : DeviceRuntimePhase.idle,
      simReady: physicalPresent,
      accessReady: physicalPresent,
      tunnelReady: physicalPresent,
      imsReady: physicalPresent,
      smsReady: false,
    ),
  );
}

final class _Repository implements DeviceRepository {
  _Repository({required this.list});

  final List<_ListHandler> list;
  int listIndex = 0;

  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) {
    return list[listIndex++](cancellation);
  }

  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) {
    throw UnimplementedError();
  }

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
