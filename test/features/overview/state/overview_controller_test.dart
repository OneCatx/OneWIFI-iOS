import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';
import 'package:onewifi_android/features/overview/data/overview_repository.dart';
import 'package:onewifi_android/features/overview/domain/overview.dart';
import 'package:onewifi_android/features/overview/state/overview_controller.dart';

void main() {
  test('loads host and devices concurrently into data', () async {
    final hostStarted = Completer<void>();
    final devicesStarted = Completer<void>();
    final hostResult = Completer<HostOverview>();
    final devicesResult = Completer<List<DeviceOverview>>();
    final controller = _controller(
      host: <_HostHandler>[
        (_) {
          hostStarted.complete();
          return hostResult.future;
        },
      ],
      devices: <_DevicesHandler>[
        (_) {
          devicesStarted.complete();
          return devicesResult.future;
        },
      ],
    );

    final pending = controller.load();
    expect(controller.state.status, QueryStatus.loading);
    await Future.wait<void>(<Future<void>>[
      hostStarted.future,
      devicesStarted.future,
    ]);
    hostResult.complete(_host(cpuModel: 'Current host'));
    devicesResult.complete(<DeviceOverview>[_device('current-device')]);
    await pending;

    expect(controller.state.status, QueryStatus.data);
    expect(controller.state.lastGoodData?.host?.cpuModel, 'Current host');
    expect(controller.state.lastGoodData?.devices?.single.id, 'current-device');
    controller.dispose();
  });

  test('uses empty only after both successful sides have no content', () async {
    final controller = _controller(
      host: <_HostHandler>[(_) async => _host()],
      devices: <_DevicesHandler>[(_) async => const <DeviceOverview>[]],
    );

    await controller.load();

    expect(controller.state.status, QueryStatus.empty);
    expect(controller.state.failure, isNull);
    controller.dispose();
  });

  test(
    'reports initial request failure instead of fabricated empty data',
    () async {
      final controller = _controller(
        host: <_HostHandler>[
          (_) async => throw const ApiFailure(
            ApiFailureKind.network,
            requestId: 'host-failure',
          ),
        ],
        devices: <_DevicesHandler>[
          (_) async => throw const ApiFailure(
            ApiFailureKind.timeout,
            requestId: 'devices-failure',
          ),
        ],
      );

      await controller.load();

      expect(controller.state.status, QueryStatus.failed);
      expect(controller.state.failure?.kind, StateFailureKind.network);
      expect(controller.state.lastGoodData?.host, isNull);
      expect(controller.state.lastGoodData?.devices, isNull);
      expect(
        controller.state.lastGoodData?.devicesFailure?.kind,
        StateFailureKind.timeout,
      );
      controller.dispose();
    },
  );

  test(
    'keeps an initially successful side visible on partial failure',
    () async {
      final controller = _controller(
        host: <_HostHandler>[(_) async => _host(cpuModel: 'Visible host')],
        devices: <_DevicesHandler>[
          (_) async => throw const ApiFailure(
            ApiFailureKind.http,
            requestId: 'forbidden',
            statusCode: 403,
          ),
        ],
      );

      await controller.load();

      expect(controller.state.status, QueryStatus.failed);
      expect(controller.state.lastGoodData?.host?.cpuModel, 'Visible host');
      expect(
        controller.state.lastGoodData?.devicesFailure?.kind,
        StateFailureKind.forbidden,
      );
      expect(controller.state.lastGoodData?.devicesStale, isFalse);
      controller.dispose();
    },
  );

  test(
    'refresh preserves each failed last-good side and marks it stale',
    () async {
      final controller = _controller(
        host: <_HostHandler>[
          (_) async => _host(cpuModel: 'Last host'),
          (_) async => throw const ApiFailure(
            ApiFailureKind.network,
            requestId: 'refresh-host',
          ),
        ],
        devices: <_DevicesHandler>[
          (_) async => <DeviceOverview>[_device('last-device')],
          (_) async => throw const ApiFailure(
            ApiFailureKind.timeout,
            requestId: 'refresh-devices',
          ),
        ],
      );
      await controller.load();

      final pending = controller.refresh();
      expect(controller.state.status, QueryStatus.refreshing);
      expect(controller.state.lastGoodData?.host?.cpuModel, 'Last host');
      await pending;

      final snapshot = controller.state.lastGoodData;
      expect(controller.state.status, QueryStatus.failed);
      expect(controller.state.isStale, isTrue);
      expect(snapshot?.host?.cpuModel, 'Last host');
      expect(snapshot?.devices?.single.id, 'last-device');
      expect(snapshot?.hostStale, isTrue);
      expect(snapshot?.devicesStale, isTrue);
      expect(snapshot?.hostFailure?.kind, StateFailureKind.network);
      expect(snapshot?.devicesFailure?.kind, StateFailureKind.timeout);
      controller.dispose();
    },
  );

  test(
    'refresh updates one side while retaining only the failed side',
    () async {
      final controller = _controller(
        host: <_HostHandler>[
          (_) async => _host(cpuModel: 'Old host'),
          (_) async => _host(cpuModel: 'New host'),
        ],
        devices: <_DevicesHandler>[
          (_) async => <DeviceOverview>[_device('old-device')],
          (_) async => throw const ApiFailure(
            ApiFailureKind.network,
            requestId: 'refresh-devices',
          ),
        ],
      );
      await controller.load();
      await controller.refresh();

      final snapshot = controller.state.lastGoodData;
      expect(snapshot?.host?.cpuModel, 'New host');
      expect(snapshot?.hostStale, isFalse);
      expect(snapshot?.devices?.single.id, 'old-device');
      expect(snapshot?.devicesStale, isTrue);
      controller.dispose();
    },
  );

  test(
    'replacement cancels the old read and discards its late generation',
    () async {
      final firstHost = Completer<HostOverview>();
      final firstDevices = Completer<List<DeviceOverview>>();
      final firstHostCancellation = Completer<RequestCancellation?>();
      final secondHostCancellation = Completer<RequestCancellation?>();
      final controller = _controller(
        host: <_HostHandler>[
          (cancellation) {
            firstHostCancellation.complete(cancellation);
            return firstHost.future;
          },
          (cancellation) async {
            secondHostCancellation.complete(cancellation);
            return _host(cpuModel: 'Newest host');
          },
        ],
        devices: <_DevicesHandler>[
          (_) => firstDevices.future,
          (_) async => <DeviceOverview>[_device('newest-device')],
        ],
      );

      final older = controller.load();
      final oldCancellation = await firstHostCancellation.future;
      final newer = controller.refresh();
      await secondHostCancellation.future;
      expect(oldCancellation?.isCancelled, isTrue);
      await newer;
      expect(controller.state.lastGoodData?.host?.cpuModel, 'Newest host');

      firstHost.complete(_host(cpuModel: 'Late old host'));
      firstDevices.complete(<DeviceOverview>[_device('late-old-device')]);
      await older;
      expect(controller.state.lastGoodData?.host?.cpuModel, 'Newest host');
      expect(
        controller.state.lastGoodData?.devices?.single.id,
        'newest-device',
      );
      controller.dispose();
    },
  );

  test(
    'dispose cancels its read and prevents late notification or commit',
    () async {
      final hostResult = Completer<HostOverview>();
      final devicesResult = Completer<List<DeviceOverview>>();
      final capturedCancellation = Completer<RequestCancellation?>();
      final controller = _controller(
        host: <_HostHandler>[
          (cancellation) {
            capturedCancellation.complete(cancellation);
            return hostResult.future;
          },
        ],
        devices: <_DevicesHandler>[(_) => devicesResult.future],
      );
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      final pending = controller.load();
      final cancellation = await capturedCancellation.future;
      expect(notifications, 1);
      controller.dispose();
      expect(cancellation?.isCancelled, isTrue);
      hostResult.complete(_host(cpuModel: 'Too late'));
      devicesResult.complete(<DeviceOverview>[_device('too-late')]);
      await pending;

      expect(notifications, 1);
      expect(controller.state.status, QueryStatus.loading);
    },
  );
}

typedef _HostHandler =
    Future<HostOverview> Function(RequestCancellation? cancellation);
typedef _DevicesHandler =
    Future<List<DeviceOverview>> Function(RequestCancellation? cancellation);

OverviewController _controller({
  required List<_HostHandler> host,
  required List<_DevicesHandler> devices,
}) {
  return OverviewController(
    repository: _Repository(host: host, devices: devices),
    requestRegistry: RequestRegistry(),
  );
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
  _Repository({required this.host, required this.devices});

  final List<_HostHandler> host;
  final List<_DevicesHandler> devices;
  int hostIndex = 0;
  int devicesIndex = 0;

  @override
  Future<HostOverview> fetchHost({RequestCancellation? cancellation}) {
    return host[hostIndex++](cancellation);
  }

  @override
  Future<List<DeviceOverview>> fetchDevices({
    RequestCancellation? cancellation,
  }) {
    return devices[devicesIndex++](cancellation);
  }
}
