import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/state/device_list_controller.dart';
import 'package:onewifi_android/features/esim/domain/esim.dart';
import 'package:onewifi_android/features/esim/domain/euicc_hardware.dart';

void main() {
  group('after dispose()', () {
    _Harness disposed() {
      final h = _Harness();
      h.controller.dispose();
      return h;
    }

    void expectSilent(_Harness h) {
      expect(h.notifications, 0);
      expect(h.repo.calls, isEmpty);
      expect(h.overview.calls, 0);
      expect(h.controller.state.status, QueryStatus.initial);
    }

    test('load completes silently', () async {
      final h = disposed();
      await expectLater(h.controller.load(), completes);
      expectSilent(h);
    });

    test('refresh completes silently', () async {
      final h = disposed();
      await expectLater(h.controller.refresh(), completes);
      expectSilent(h);
    });

    test('hardwareFor returns null silently', () {
      final h = disposed();
      expect(h.controller.hardwareFor('m1'), isNull);
      expectSilent(h);
    });

    test('cardNameFor returns null silently', () {
      final h = disposed();
      expect(h.controller.cardNameFor('m1', '•••• 1234'), isNull);
      expectSilent(h);
    });

    test('deviceIdNamed returns null silently', () {
      final h = disposed();
      expect(h.controller.deviceIdNamed('Device m1'), isNull);
      expectSilent(h);
    });
  });

  group('disposed while a request is in flight', () {
    test('load: late failure completes silently', () async {
      final h = _Harness();
      h.hold();
      final pending = h.controller.load();
      expect(h.repo.calls, <String>['fetchDevices']);
      expect(h.notifications, 1);
      h.controller.dispose();
      h.fail();
      h.release();
      await expectLater(pending, completes);
      expect(h.notifications, 1);
      expect(h.repo.calls, <String>['fetchDevices']);
      expect(h.overview.calls, 0);
      expect(h.controller.state.status, QueryStatus.loading);
    });

    test('load: late overview success completes silently', () async {
      final h = _Harness();
      h.holdOverview();
      await h.controller.load();
      expect(h.overview.calls, 1);
      expect(h.notifications, 2);
      h.controller.dispose();
      h.releaseOverview();
      await pumpEventQueue();
      expect(h.notifications, 2);
      expect(h.repo.calls, <String>['fetchDevices']);
      expect(h.overview.calls, 1);
      expect(h.controller.hardwareFor('m1'), isNull);
    });

    test('load: late overview failure completes silently', () async {
      final h = _Harness();
      h.holdOverview();
      await h.controller.load();
      expect(h.overview.calls, 1);
      expect(h.notifications, 2);
      h.controller.dispose();
      h.failOverview();
      h.releaseOverview();
      await pumpEventQueue();
      expect(h.notifications, 2);
      expect(h.repo.calls, <String>['fetchDevices']);
      expect(h.overview.calls, 1);
      expect(h.controller.hardwareFor('m1'), isNull);
    });
  });

  group('dispose() twice', () {
    test('second dispose() returns normally without a notification', () {
      final h = _Harness();
      h.controller.dispose();
      expect(h.controller.dispose, returnsNormally);
      expect(h.notifications, 0);
    });
  });
}

final class _Harness {
  _Harness() {
    controller = DeviceListController(
      repository: repo,
      requestRegistry: RequestRegistry(),
      overviewLoader: overview.load,
    );
    controller.addListener(() => notifications += 1);
    addTearDown(controller.dispose);
  }

  final _Repository repo = _Repository();
  final _OverviewLoader overview = _OverviewLoader();
  int notifications = 0;
  late final DeviceListController controller;
  Completer<void>? _gate;
  Completer<void>? _overviewGate;

  void hold() {
    final gate = Completer<void>();
    _gate = gate;
    repo.gate = gate;
  }

  void release() => _gate?.complete();

  void fail() => repo.failure = StateError('boom');

  void holdOverview() {
    final gate = Completer<void>();
    _overviewGate = gate;
    overview.gate = gate;
  }

  void releaseOverview() => _overviewGate?.complete();

  void failOverview() => overview.failure = StateError('boom');
}

final class _OverviewLoader {
  Completer<void>? gate;
  Object? failure;
  int calls = 0;

  Future<EuiccOverview> load(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    calls += 1;
    final pending = gate;
    if (pending != null) await pending.future;
    final error = failure;
    if (error != null) throw error;
    return EuiccOverview(
      hardware: const <EuiccHardware>[],
      profiles: const <EsimProfile>[],
    );
  }
}

final class _Repository implements DeviceRepository {
  Completer<void>? gate;
  Object? failure;
  final List<String> calls = <String>[];

  Future<T> _respond<T>(String name, T Function() result) async {
    calls.add(name);
    final pending = gate;
    if (pending != null) await pending.future;
    final error = failure;
    if (error != null) throw error;
    return result();
  }

  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) =>
      _respond<DeviceFleet>('fetchDevices', () => _fleet('m1'));

  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) => _respond<DeviceDetail>(
    'fetchDeviceOverview',
    () => DeviceDetail(
      device: _snapshot(deviceId),
      traffic: const DeviceTraffic.unavailable(),
    ),
  );

  @override
  Future<void> setCapability({
    required String deviceId,
    required DeviceCapability capability,
    required bool enabled,
    RequestCancellation? cancellation,
  }) => _respond<void>('setCapability', () {});

  @override
  Future<void> reconnectVowifi(
    String deviceId, {
    RequestCancellation? cancellation,
  }) => _respond<void>('reconnectVowifi', () {});

  @override
  Future<void> reboot(String deviceId, {RequestCancellation? cancellation}) =>
      _respond<void>('reboot', () {});
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

DeviceFleet _fleet(String id) {
  return DeviceFleet(deviceLimit: 4, devices: <DeviceSnapshot>[_snapshot(id)]);
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
