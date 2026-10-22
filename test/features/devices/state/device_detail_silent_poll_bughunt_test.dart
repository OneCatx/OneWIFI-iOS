import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/state/device_detail_controller.dart';

// B1-03 用户可见面：`poll()`（silent）与 `refresh()` 共用 `_read`。silent 一代
// `begin()` 取消非 silent 刷新；silent 失败按契约不落 failed。两边都不写时，
// `device_detail_view` 把 `refreshing` 画成「正在刷新设备」进度条常驻。
void main() {
  test('refresh 被 poll 顶替且 poll 失败后，不得停留在 refreshing', () async {
    final repo = _Repo();
    final controller = DeviceDetailController(
      deviceId: 'device-a',
      repository: repo,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    repo.enqueue().complete(_detail('device-a', trafficBytes: 1));
    await controller.load();
    expect(controller.state.status, QueryStatus.data);

    final refreshGate = repo.enqueue();
    final refresh = controller.refresh();
    expect(controller.state.status, QueryStatus.refreshing);

    final pollGate = repo.enqueue();
    final poll = controller.poll();
    expect(repo.cancellations[1]!.isCancelled, isTrue);
    expect(repo.cancellations[2]!.isCancelled, isFalse);

    pollGate.completeError(
      const ApiFailure(ApiFailureKind.network, requestId: 'poll-net'),
    );
    refreshGate.complete(_detail('device-a', trafficBytes: 2));
    await poll;
    await refresh;

    expect(controller.state.status, QueryStatus.data);
    expect(controller.state.lastGoodData?.traffic.rxBytes, 1);
  });
}

DeviceDetail _detail(String id, {int trafficBytes = 0}) => DeviceDetail(
  device: DeviceSnapshot(
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
  ),
  traffic: DeviceTraffic.available(
    rxBytes: trafficBytes,
    txBytes: trafficBytes,
    rxRateBytesPerSecond: 0,
    txRateBytesPerSecond: 0,
    status: DeviceTrafficStatus.ready,
  ),
);

final class _Repo implements DeviceRepository {
  final List<Completer<DeviceDetail>> _queue = <Completer<DeviceDetail>>[];
  final List<RequestCancellation?> cancellations = <RequestCancellation?>[];
  int _next = 0;

  Completer<DeviceDetail> enqueue() {
    final gate = Completer<DeviceDetail>();
    _queue.add(gate);
    return gate;
  }

  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) {
    cancellations.add(cancellation);
    return _queue[_next++].future;
  }

  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) =>
      throw UnimplementedError();

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
