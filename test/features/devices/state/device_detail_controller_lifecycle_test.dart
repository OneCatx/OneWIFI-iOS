import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/state/device_detail_controller.dart';

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
      expect(h.controller.state.status, QueryStatus.initial);
      expect(h.controller.action.status, ActionStatus.idle);
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

    test('poll completes silently', () async {
      final h = disposed();
      await expectLater(h.controller.poll(), completes);
      expectSilent(h);
    });

    test('setCapability(network, true) completes silently', () async {
      final h = disposed();
      await expectLater(
        h.controller.setCapability(DeviceCapability.network, true),
        completes,
      );
      expectSilent(h);
    });

    test('reconnectVowifi completes silently', () async {
      final h = disposed();
      await expectLater(h.controller.reconnectVowifi(), completes);
      expectSilent(h);
    });

    test('reboot completes silently', () async {
      final h = disposed();
      await expectLater(h.controller.reboot(), completes);
      expectSilent(h);
    });
  });

  group('disposed while a request is in flight', () {
    Future<void> expectLateIgnored(
      _Harness h,
      Future<void> Function() start,
      List<String> issued, {
      bool fail = false,
    }) async {
      h.hold();
      final pending = start();
      expect(h.repo.calls, issued);
      expect(h.notifications, 1);
      h.controller.dispose();
      if (fail) h.fail();
      h.release();
      await expectLater(pending, completes);
      expect(h.notifications, 1);
      expect(h.repo.calls, issued);
    }

    test('load: late failure completes silently', () async {
      final h = _Harness();
      await expectLateIgnored(h, h.controller.load, <String>[
        'fetchDeviceOverview',
      ], fail: true);
      expect(h.controller.state.status, QueryStatus.loading);
      expect(h.controller.action.status, ActionStatus.idle);
    });

    test('setCapability: late success completes silently', () async {
      final h = _Harness();
      await expectLateIgnored(
        h,
        () => h.controller.setCapability(DeviceCapability.network, true),
        <String>['setCapability'],
      );
      expect(h.controller.state.status, QueryStatus.initial);
      expect(h.controller.action.status, ActionStatus.submitting);
    });

    test('setCapability: late failure completes silently', () async {
      final h = _Harness();
      await expectLateIgnored(
        h,
        () => h.controller.setCapability(DeviceCapability.network, true),
        <String>['setCapability'],
        fail: true,
      );
      expect(h.controller.state.status, QueryStatus.initial);
      expect(h.controller.action.status, ActionStatus.submitting);
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
    controller = DeviceDetailController(
      deviceId: 'device-a',
      repository: repo,
      requestRegistry: RequestRegistry(),
    );
    controller.addListener(() => notifications += 1);
    addTearDown(controller.dispose);
  }

  final _Repository repo = _Repository();
  int notifications = 0;
  late final DeviceDetailController controller;
  Completer<void>? _gate;

  void hold() {
    final gate = Completer<void>();
    _gate = gate;
    repo.gate = gate;
  }

  void release() => _gate?.complete();

  void fail() => repo.failure = StateError('boom');
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
      _respond<DeviceFleet>(
        'fetchDevices',
        () => DeviceFleet(deviceLimit: 4, devices: const <DeviceSnapshot>[]),
      );

  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) => _respond<DeviceDetail>('fetchDeviceOverview', () => _detail(deviceId));

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

DeviceDetail _detail(String id) {
  return DeviceDetail(
    device: _snapshot(id),
    traffic: const DeviceTraffic.unavailable(),
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
