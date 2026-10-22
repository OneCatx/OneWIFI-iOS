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

void main() {
  test(
    'forwards the exact selected ID and accepts configured offline data',
    () async {
      const selectedId = 'slot/a b?c#d';
      String? capturedId;
      RequestCancellation? capturedCancellation;
      final registry = RequestRegistry();
      final controller = DeviceDetailController(
        deviceId: selectedId,
        repository: _Repository(
          detail: <_DetailHandler>[
            (deviceId, cancellation) async {
              capturedId = deviceId;
              capturedCancellation = cancellation;
              return _detail(deviceId, physicalPresent: false);
            },
          ],
        ),
        requestRegistry: registry,
      );

      final pending = controller.load();
      expect(controller.deviceId, selectedId);
      expect(controller.state.status, QueryStatus.loading);
      expect(controller.state.key, 'devices.detail:$selectedId');
      await pending;

      expect(capturedId, selectedId);
      expect(capturedCancellation, isNotNull);
      expect(controller.state.status, QueryStatus.data);
      expect(controller.state.lastGoodData?.device.id, selectedId);
      expect(controller.state.lastGoodData?.device.physicalPresent, isFalse);

      final probe = registry.register('devices.detail:$selectedId');
      expect(
        capturedCancellation?.isCancelled,
        isFalse,
        reason: 'a completed registration must have been removed',
      );
      registry.remove('devices.detail:$selectedId', probe);
      controller.dispose();
    },
  );

  test('preserves detail 404 as failure instead of offline success', () async {
    final controller = _detailController('missing-config', <_DetailHandler>[
      (_, _) async => throw const ApiFailure(
        ApiFailureKind.http,
        requestId: 'detail-not-found',
        statusCode: 404,
      ),
    ]);

    await controller.load();

    expect(controller.state.status, QueryStatus.failed);
    expect(controller.state.failure?.kind, StateFailureKind.generic);
    expect(controller.state.failure?.statusCode, 404);
    expect(controller.state.lastGoodData, isNull);
    controller.dispose();
  });

  test('refresh retains detail and marks forbidden failure stale', () async {
    final controller = _detailController('device-a', <_DetailHandler>[
      (id, _) async => _detail(id),
      (_, _) async => throw const ApiFailure(
        ApiFailureKind.http,
        requestId: 'detail-forbidden',
        statusCode: 403,
      ),
    ]);
    await controller.load();

    final pending = controller.refresh();
    expect(controller.state.status, QueryStatus.refreshing);
    expect(controller.state.lastGoodData?.device.id, 'device-a');
    await pending;

    expect(controller.state.status, QueryStatus.failed);
    expect(controller.state.failure?.kind, StateFailureKind.forbidden);
    expect(controller.state.failure?.statusCode, 403);
    expect(controller.state.isStale, isTrue);
    expect(controller.state.lastGoodData?.device.id, 'device-a');
    controller.dispose();
  });

  test('replacement cancels and discards the old late detail', () async {
    final oldResult = Completer<DeviceDetail>();
    final oldCancellation = Completer<RequestCancellation?>();
    final controller = _detailController('device-a', <_DetailHandler>[
      (_, cancellation) {
        oldCancellation.complete(cancellation);
        return oldResult.future;
      },
      (id, _) async => _detail(id, trafficBytes: 22),
    ]);

    final oldPending = controller.load();
    final cancellation = await oldCancellation.future;
    final newPending = controller.refresh();
    expect(cancellation?.isCancelled, isTrue);
    await newPending;
    expect(controller.state.lastGoodData?.traffic.rxBytes, 22);

    oldResult.complete(_detail('device-a', trafficBytes: 11));
    await oldPending;
    expect(controller.state.status, QueryStatus.data);
    expect(controller.state.lastGoodData?.traffic.rxBytes, 22);
    controller.dispose();
  });

  test(
    'dispose cancels and suppresses late detail notification and commit',
    () async {
      final result = Completer<DeviceDetail>();
      final capturedCancellation = Completer<RequestCancellation?>();
      final controller = _detailController('device-a', <_DetailHandler>[
        (_, cancellation) {
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
      result.complete(_detail('device-a'));
      await pending;

      expect(notifications, 1);
      expect(controller.state.status, QueryStatus.loading);
    },
  );

  test(
    'old controller cannot commit across a new same-ID controller',
    () async {
      final registry = RequestRegistry();
      final oldResult = Completer<DeviceDetail>();
      final oldCancellation = Completer<RequestCancellation?>();
      final oldController = DeviceDetailController(
        deviceId: 'device-a',
        repository: _Repository(
          detail: <_DetailHandler>[
            (_, cancellation) {
              oldCancellation.complete(cancellation);
              return oldResult.future;
            },
          ],
        ),
        requestRegistry: registry,
      );
      final newController = DeviceDetailController(
        deviceId: 'device-a',
        repository: _Repository(
          detail: <_DetailHandler>[
            (id, _) async => _detail(id, trafficBytes: 99),
          ],
        ),
        requestRegistry: registry,
      );

      final oldPending = oldController.load();
      final cancellation = await oldCancellation.future;
      await newController.load();
      expect(cancellation?.isCancelled, isTrue);
      expect(newController.state.lastGoodData?.traffic.rxBytes, 99);

      oldResult.complete(_detail('device-a', trafficBytes: 1));
      await oldPending;
      expect(oldController.state.status, QueryStatus.loading);
      expect(newController.state.status, QueryStatus.data);
      expect(newController.state.lastGoodData?.traffic.rxBytes, 99);
      oldController.dispose();
      newController.dispose();
    },
  );

  test('detail maps only HTTP 500 through 599 as unavailable', () async {
    for (final testCase in <(int, StateFailureKind)>[
      (500, StateFailureKind.unavailable),
      (599, StateFailureKind.unavailable),
      (600, StateFailureKind.generic),
    ]) {
      final controller = _detailController('device-a', <_DetailHandler>[
        (_, _) async => throw ApiFailure(
          ApiFailureKind.http,
          requestId: 'detail-http-${testCase.$1}',
          statusCode: testCase.$1,
        ),
      ]);

      await controller.load();

      expect(controller.state.failure?.kind, testCase.$2);
      expect(controller.state.failure?.statusCode, testCase.$1);
      controller.dispose();
    }
  });

  test(
    'capability write is single-flight and refreshes after success',
    () async {
      final writes = <(DeviceCapability, bool)>[];
      final controller = DeviceDetailController(
        deviceId: 'device-a',
        repository: _Repository(
          detail: <_DetailHandler>[
            (id, _) async => _detail(id),
            (id, _) async => DeviceDetail(
              device: _snapshot(
                id,
                physicalPresent: true,
              ).copyWith(vowifiEnabled: false),
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
      expect(controller.state.lastGoodData?.device.vowifiEnabled, isTrue);

      final pending = controller.setCapability(DeviceCapability.vowifi, false);
      controller.setCapability(DeviceCapability.network, false);
      await pending;

      expect(writes, <(DeviceCapability, bool)>[
        (DeviceCapability.vowifi, false),
      ]);
      expect(controller.state.lastGoodData?.device.vowifiEnabled, isFalse);
      expect(controller.action.status, ActionStatus.succeeded);
      controller.dispose();
    },
  );

  test('capability conflict stays known and is not retried', () async {
    var writes = 0;
    final controller = DeviceDetailController(
      deviceId: 'device-a',
      repository: _Repository(
        detail: <_DetailHandler>[(id, _) async => _detail(id)],
        capability: (_, _, _, _) async {
          writes += 1;
          throw const ApiFailure(
            ApiFailureKind.http,
            requestId: 'capability-conflict',
            statusCode: 409,
          );
        },
      ),
      requestRegistry: RequestRegistry(),
    );
    await controller.load();
    await controller.setCapability(DeviceCapability.network, false);

    expect(writes, 1);
    expect(controller.action.status, ActionStatus.failed);
    expect(controller.action.isUnknownOutcome, isFalse);
    expect(controller.action.knownFailure?.kind, StateFailureKind.conflict);
    expect(controller.state.lastGoodData?.device.networkEnabled, isTrue);
    controller.dispose();
  });
}

typedef _DetailHandler =
    Future<DeviceDetail> Function(
      String deviceId,
      RequestCancellation? cancellation,
    );

DeviceDetailController _detailController(
  String deviceId,
  List<_DetailHandler> handlers,
) {
  return DeviceDetailController(
    deviceId: deviceId,
    repository: _Repository(detail: handlers),
    requestRegistry: RequestRegistry(),
  );
}

DeviceDetail _detail(
  String id, {
  bool physicalPresent = true,
  int trafficBytes = 0,
}) {
  return DeviceDetail(
    device: _snapshot(id, physicalPresent: physicalPresent),
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
}

DeviceSnapshot _snapshot(String id, {required bool physicalPresent}) {
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
  _Repository({required this.detail, this.capability});

  final List<_DetailHandler> detail;
  final Future<void> Function(
    String deviceId,
    DeviceCapability capability,
    bool enabled,
    RequestCancellation? cancellation,
  )?
  capability;
  int detailIndex = 0;

  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) {
    throw UnimplementedError();
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
