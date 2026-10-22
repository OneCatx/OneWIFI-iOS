import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/overview/data/overview_repository.dart';
import 'package:onewifi_android/features/overview/domain/overview.dart';
import 'package:onewifi_android/features/overview/state/overview_controller.dart';

void main() {
  const loaded = <String>['fetchHost', 'fetchDevices'];

  group('after dispose()', () {
    Future<_Harness> disposed() async {
      final h = _Harness();
      await h.controller.load();
      expect(h.repo.calls, loaded);
      expect(h.notifications, 2);
      expect(h.controller.state.status, QueryStatus.data);
      h.controller.dispose();
      return h;
    }

    void expectSilent(_Harness h, QueryState<OverviewSnapshot> state) {
      expect(h.notifications, 2);
      expect(h.repo.calls, loaded);
      expect(h.controller.state, same(state));
    }

    test('load completes silently', () async {
      final h = await disposed();
      final state = h.controller.state;
      await expectLater(h.controller.load(), completes);
      expectSilent(h, state);
    });

    test('refresh completes silently', () async {
      final h = await disposed();
      final state = h.controller.state;
      await expectLater(h.controller.refresh(), completes);
      expectSilent(h, state);
    });
  });

  group('disposed while a request is in flight', () {
    test('load: late failure on both sides completes silently', () async {
      final h = _Harness();
      h.hold();
      final pending = h.controller.load();
      expect(h.repo.calls, loaded);
      expect(h.notifications, 1);
      h.controller.dispose();
      h.fail();
      h.release();
      await expectLater(pending, completes);
      expect(h.notifications, 1);
      expect(h.repo.calls, loaded);
      expect(h.controller.state.status, QueryStatus.loading);
      expect(h.controller.state.lastGoodData, isNull);
    });

    test(
      'load: late host success with late devices failure completes silently',
      () async {
        final h = _Harness();
        h.hold();
        final pending = h.controller.load();
        expect(h.repo.calls, loaded);
        expect(h.notifications, 1);
        h.controller.dispose();
        h.fail(host: false);
        h.release();
        await expectLater(pending, completes);
        expect(h.notifications, 1);
        expect(h.repo.calls, loaded);
        expect(h.controller.state.status, QueryStatus.loading);
        expect(h.controller.state.lastGoodData, isNull);
      },
    );
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
    controller = OverviewController(
      repository: repo,
      requestRegistry: RequestRegistry(),
    );
    controller.addListener(() => notifications += 1);
    addTearDown(controller.dispose);
  }

  final _Repository repo = _Repository();
  int notifications = 0;
  late final OverviewController controller;
  Completer<void>? _gate;

  void hold() {
    final gate = Completer<void>();
    _gate = gate;
    repo.gate = gate;
  }

  void release() => _gate?.complete();

  void fail({bool host = true, bool devices = true}) {
    if (host) repo.failures['fetchHost'] = StateError('host boom');
    if (devices) repo.failures['fetchDevices'] = StateError('devices boom');
  }
}

HostOverview _host({String cpuModel = ''}) => HostOverview(
  cpuModel: cpuModel,
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
);

DeviceOverview _device(String id) => DeviceOverview(
  id: id,
  name: 'Device $id',
  model: 'EC25',
  type: 'pcie_ec20_ec25',
  healthy: true,
  operatorName: 'Carrier',
  signalDbm: -70,
  networkMode: 'LTE',
  vowifiActive: true,
  networkConnected: true,
  runtime: const DeviceRuntimeOverview(
    phase: DeviceRuntimePhase.imsReady,
    simReady: true,
    accessReady: true,
    tunnelReady: true,
    imsReady: true,
    smsReady: false,
  ),
);

final class _Repository implements OverviewRepository {
  Completer<void>? gate;
  final Map<String, Object> failures = <String, Object>{};
  final List<String> calls = <String>[];

  Future<T> _respond<T>(String name, T Function() result) async {
    calls.add(name);
    final pending = gate;
    if (pending != null) await pending.future;
    final error = failures[name];
    if (error != null) throw error;
    return result();
  }

  @override
  Future<HostOverview> fetchHost({RequestCancellation? cancellation}) =>
      _respond<HostOverview>('fetchHost', () => _host(cpuModel: 'Host'));

  @override
  Future<List<DeviceOverview>> fetchDevices({
    RequestCancellation? cancellation,
  }) => _respond<List<DeviceOverview>>(
    'fetchDevices',
    () => <DeviceOverview>[_device('device-a')],
  );
}
