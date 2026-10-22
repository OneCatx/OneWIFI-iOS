import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_backend_store.dart';
import 'package:onewifi_android/features/proxy/data/proxy_repository.dart';
import 'package:onewifi_android/features/proxy/domain/mihomo_backend.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_call_connection.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_call_group.dart';
import 'package:onewifi_android/features/proxy/state/proxy_controller.dart';

void main() {
  test('load keeps WIFI groups and select patches the current node', () async {
    final repository = _Repo();
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.groups.status, QueryStatus.data);
    expect(controller.groups.lastGoodData!.first.now, 'old');

    final ok = await controller.selectNode(
      group: 'HK-WIFI Selector',
      name: 'new',
    );

    expect(ok, isTrue);
    expect(repository.selectCalls, 1);
    expect(controller.selectAction.status, ActionStatus.succeeded);
    expect(controller.groups.lastGoodData!.first.now, 'new');
    expect(controller.selectingGroup, isNull);
  });

  test('select is single-flight', () async {
    final repository = _Repo(blockSelect: true);
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    final first = controller.selectNode(group: 'HK-WIFI Selector', name: 'one');
    final second = controller.selectNode(
      group: 'HK-WIFI Selector',
      name: 'two',
    );
    repository.select.complete();
    expect(await first, isTrue);
    expect(await second, isFalse);
    expect(repository.selectCalls, 1);
    expect(controller.groups.lastGoodData!.first.now, 'one');
  });

  test('skips Mihomo until a backend is saved', () async {
    final store = MemoryMihomoBackendStore();
    final repository = _Repo();
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
      backendStore: store,
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.needsConnection, isTrue);
    expect(controller.groups.status, QueryStatus.empty);
    expect(repository.fetches, 0);

    await store.write(
      MihomoBackend(origin: Uri.parse('http://192.168.1.88:9090')),
    );
    await controller.load();
    expect(controller.needsConnection, isFalse);
    expect(controller.groups.status, QueryStatus.data);
    expect(repository.fetches, 1);
    expect(controller.connections.status, QueryStatus.data);
  });

  test('loads connections next to WIFI groups', () async {
    final repository = _Repo();
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.connections.status, QueryStatus.data);
    expect(controller.connections.lastGoodData, hasLength(1));
    expect(
      controller.connections.lastGoodData!.single.host,
      'epdg.epc.att.net:500',
    );
  });

  test('load probes the current node delay', () async {
    final repository = _Repo();
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(repository.probedNames, contains('HK-WIFI Selector'));
    expect(repository.probedNames, isNot(contains('JP-WIFI Selector')));
    expect(controller.groups.lastGoodData!.first.nodes.first.delayMs, 40);
    expect(controller.groups.lastGoodData!.first.nodes.first.alive, isTrue);
    expect(
      controller.groups.lastGoodData!.first.nodes.first.delayFailed,
      isFalse,
    );
  });

  test('unknown delay probe does not stamp 超时 onto a live node', () async {
    final repository = _Repo(unknown: true);
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    final node = controller.groups.lastGoodData!.first.nodes.first;
    expect(node.delayMs, 0);
    expect(node.alive, isTrue);
    expect(node.delayFailed, isFalse);
    expect(node.delayProbed, isTrue);
  });

  test('a real delay timeout marks the current node failed', () async {
    final repository = _Repo(timedOut: true);
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    final node = controller.groups.lastGoodData!.first.nodes.first;
    expect(node.delayMs, 0);
    expect(node.delayFailed, isTrue);
    expect(node.alive, isFalse);
  });

  test('group delay stamps the currently selected leaf', () async {
    final repository = _Repo();
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(repository.probedNames, contains('HK-WIFI Selector'));
    expect(controller.groups.lastGoodData!.first.now, 'old');
    expect(controller.groups.lastGoodData!.first.nodes.first.delayMs, 40);
  });

  test('probeGroup stamps every leaf from the group delay map', () async {
    final repository = _Repo();
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    repository.probedNames.clear();
    repository.probedGroups.clear();
    await controller.probeGroup('HK-WIFI Selector');
    expect(repository.probedGroups, <String>['HK-WIFI Selector']);
    expect(repository.probedNames, isEmpty);
    expect(
      controller.groups.lastGoodData!.first.nodes.map((node) => node.delayMs),
      <int>[40, 50, 60],
    );
  });

  test('probeGroup falls back to leaves if group delay is missing', () async {
    final repository = _Repo(groupMissing: true);
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    repository.probedNames.clear();
    await controller.probeGroup('HK-WIFI Selector');
    expect(repository.probedGroups, contains('HK-WIFI Selector'));
    expect(repository.probedNames, containsAll(<String>['old', 'new', 'one']));
    expect(repository.probedNames, isNot(contains('jp-now')));
  });

  test('empty group delay map marks every leaf timed out', () async {
    final repository = _Repo(groupEmpty: true);
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    await controller.probeGroup('HK-WIFI Selector');
    expect(
      controller.groups.lastGoodData!.first.nodes.every(
        (node) => node.delayFailed,
      ),
      isTrue,
    );
  });

  test(
    'probeGroup still probes every leaf if current probes are running',
    () async {
      final repository = _Repo(blockDelay: true);
      final controller = ProxyController(
        repository: repository,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      final load = controller.load();
      await Future<void>.delayed(Duration.zero);
      expect(controller.probing, isTrue);
      await controller.probeGroup('HK-WIFI Selector');
      expect(repository.probedNames, <String>['HK-WIFI Selector']);
      expect(repository.probedGroups, isEmpty);
      repository.delayGate.complete();
      await load;
      expect(repository.probedGroups, contains('HK-WIFI Selector'));
      expect(
        controller.groups.lastGoodData!.first.nodes.map((node) => node.delayMs),
        <int>[40, 50, 60],
      );
    },
  );

  test('probeCurrents can run again after load', () async {
    final repository = _Repo();
    final controller = ProxyController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    final afterLoad = repository.delayCalls;
    expect(afterLoad, greaterThan(0));
    await controller.probeCurrents();
    expect(repository.delayCalls, greaterThan(afterLoad));
  });
}

final class _Repo implements ProxyRepository {
  _Repo({
    this.blockSelect = false,
    this.unknown = false,
    this.timedOut = false,
    this.blockDelay = false,
    this.groupMissing = false,
    this.groupEmpty = false,
  });

  final bool blockSelect;
  final bool unknown;
  final bool timedOut;
  final bool blockDelay;
  final bool groupMissing;
  final bool groupEmpty;
  final Completer<void> select = Completer<void>();
  final Completer<void> delayGate = Completer<void>();
  int selectCalls = 0;
  int fetches = 0;
  int delayCalls = 0;
  final List<String> probedNames = <String>[];
  final List<String> probedGroups = <String>[];

  @override
  Future<List<WifiCallGroup>> fetchWifiCallGroups({
    RequestCancellation? cancellation,
  }) async {
    fetches += 1;
    return <WifiCallGroup>[
      WifiCallGroup(
        groupName: 'HK-WIFI Selector',
        countryCode: 'HK',
        countryName: '香港',
        flagEmoji: '🇭🇰',
        now: 'old',
        aliveCount: 1,
        totalCount: 1,
        nodes: const <WifiCallNode>[
          WifiCallNode(name: 'old', alive: true),
          WifiCallNode(name: 'new', alive: true, delayMs: 50),
          WifiCallNode(name: 'one', alive: true, delayMs: 60),
        ],
      ),
      WifiCallGroup(
        groupName: 'JP-WIFI Selector',
        countryCode: 'JP',
        countryName: '日本',
        flagEmoji: '🇯🇵',
        now: 'jp-now',
        aliveCount: 1,
        totalCount: 1,
        nodes: const <WifiCallNode>[WifiCallNode(name: 'jp-now', alive: true)],
      ),
    ];
  }

  @override
  Future<List<WifiCallConnection>> fetchConnections({
    RequestCancellation? cancellation,
    List<WifiCallConnection>? previous,
    DateTime? previousAt,
    DateTime? now,
  }) async {
    return const <WifiCallConnection>[
      WifiCallConnection(
        id: 'us',
        host: 'epdg.epc.att.net:500',
        chainLabel: 'US-WIFI → 自建USHOME',
        countryCode: 'US',
      ),
    ];
  }

  @override
  Future<void> selectNode({
    required String group,
    required String name,
    RequestCancellation? cancellation,
  }) async {
    selectCalls += 1;
    if (blockSelect && !select.isCompleted) await select.future;
  }

  @override
  Future<WifiDelay> probeDelay({
    required String name,
    String? altName,
    RequestCancellation? cancellation,
  }) async {
    delayCalls += 1;
    probedNames.add(name);
    if (blockDelay && !delayGate.isCompleted) await delayGate.future;
    if (timedOut) return const WifiDelay.timedOut();
    if (unknown) return const WifiDelay.unknown();
    return _lookup(name, altName);
  }

  static WifiDelay _lookup(String name, String? altName) {
    WifiDelay of(String value) => switch (value) {
      'old' => const WifiDelay.measured(40),
      'new' => const WifiDelay.measured(50),
      'one' => const WifiDelay.measured(60),
      _ => const WifiDelay.unknown(),
    };
    final primary = of(name);
    if (primary.kind != WifiDelayKind.unknown) return primary;
    final alt = altName?.trim();
    if (alt == null || alt.isEmpty) return primary;
    return of(alt);
  }

  @override
  Future<Map<String, WifiDelay>?> probeGroupDelay({
    required String name,
    RequestCancellation? cancellation,
  }) async {
    delayCalls += 1;
    probedGroups.add(name);
    if (blockDelay && !delayGate.isCompleted) await delayGate.future;
    if (groupMissing) return null;
    if (groupEmpty || timedOut) return const <String, WifiDelay>{};
    if (name != 'HK-WIFI Selector') return const <String, WifiDelay>{};
    return const <String, WifiDelay>{
      'old': WifiDelay.measured(40),
      'new': WifiDelay.measured(50),
      'one': WifiDelay.measured(60),
    };
  }
}
