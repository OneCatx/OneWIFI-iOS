import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_backend_store.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_client.dart';
import 'package:onewifi_android/features/proxy/data/proxy_repository.dart';
import 'package:onewifi_android/features/proxy/domain/mihomo_backend.dart';
import 'package:onewifi_android/features/proxy/presentation/wifi_node_sheet.dart';
import 'package:onewifi_android/features/proxy/state/mihomo_connection_controller.dart';
import 'package:onewifi_android/features/proxy/state/proxy_controller.dart';

const group = 'HK-WIFI Selector';

void main() {
  for (final phase in [1, 2, 3]) {
    test(
      'backend switch in select notification $phase prevents unsent write',
      () async {
        final rig = _Rig();
        await rig.proxy.load();
        var notifications = 0;
        var switched = false;
        rig.proxy.addListener(() {
          notifications += 1;
          if (!switched && notifications == phase) {
            switched = true;
            unawaited(rig.store.write(_backend('b')));
          }
        });
        expect(await rig.proxy.selectNode(group: group, name: 'new'), isFalse);
        expect(switched, isTrue);
        expect(rig.writes, isEmpty);
        expect(rig.proxy.groups.lastGoodData, isNull);
        await rig.proxy.load();
        expect(rig.proxy.groups.lastGoodData!.single.now, 'old');
      },
    );
  }
  test('backend switch resets connection byte-rate baseline', () async {
    final rig = _Rig();
    await rig.proxy.load();
    rig.now = rig.now.add(const Duration(seconds: 1));
    rig.onConnections = (_) async => rig.connectionResponse('a', 500);
    await rig.proxy.refresh();
    expect(rig.proxy.connections.lastGoodData!.single.downloadBps, 400);
    await rig.store.write(_backend('b'));
    rig.now = rig.now.add(const Duration(seconds: 1));
    rig.onConnections = (_) async => rig.connectionResponse('b', 2000);
    await rig.proxy.load();
    expect(rig.proxy.connections.lastGoodData!.single.host, 'b:500');
    expect(rig.proxy.connections.lastGoodData!.single.downloadBps, 0);
  });

  test('A connection response cannot repopulate the cleared B state', () async {
    final rig = _Rig();
    final entered = Completer<void>();
    final gate = Completer<http.Response>();
    rig.onConnections = (_) {
      entered.complete();
      return gate.future;
    };
    final load = rig.proxy.load();
    await entered.future;
    await rig.store.write(_backend('b'));
    gate.complete(rig.connectionResponse('a', 100));
    await load;
    expect(rig.proxy.connections.lastGoodData, isNull);
  });

  testWidgets('old open sheet cannot select a same-named B node', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.proxy.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWifiNodeSheet(
                context: context,
                controller: rig.proxy,
                groupName: group,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await rig.store.write(_backend('b', 'b-secret'));
    await rig.proxy.load();
    await tester.pumpAndSettle();
    final oldNode = find.byKey(WifiNodeSheet.nodeKey('new'));
    if (oldNode.evaluate().isNotEmpty) {
      await tester.tap(oldNode);
      await tester.pumpAndSettle();
    }
    expect(rig.writes, isEmpty, reason: 'an A sheet must not authorize B');
    expect(find.text('这组已经不在列表里。'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WifiNodeSheet.nodeKey('new')));
    await tester.pumpAndSettle();
    expect(rig.writes.single.url.host, 'b.example.test');
    expect(rig.writes.single.headers['authorization'], 'Bearer b-secret');
  });

  for (final result in ['failed', 'pending', 'empty']) {
    test(
      'A cannot authorize B after connect when B groups are $result',
      () async {
        final rig = _Rig();
        await rig.proxy.load();
        expect(
          await rig.settings.connect(
            host: 'b.example.test',
            port: '9090',
            https: false,
            secret: 'b-secret',
          ),
          isTrue,
        );
        final entered = Completer<void>();
        final gate = Completer<http.Response>();
        rig.onGroups = (request) async {
          if (request.url.host != 'b.example.test') return rig.groups(request);
          if (!entered.isCompleted) entered.complete();
          return switch (result) {
            'pending' => gate.future,
            'empty' => http.Response('{"proxies":{}}', 200),
            _ => http.Response('{}', 503),
          };
        };
        final load = rig.proxy.load();
        await entered.future;
        if (result != 'pending') await load;
        final ok = await rig.proxy.selectNode(group: group, name: 'old');
        if (result == 'pending') {
          gate.complete(rig.response('old'));
          await load;
        }
        expect(rig.writes, isEmpty, reason: 'A snapshot must not write B');
        expect(ok, isFalse);
      },
    );
  }

  for (final change in ['B', 'ABA', 'secret']) {
    test(
      '$change invalidates loaded groups immediately without another load',
      () async {
        final rig = _Rig();
        await rig.proxy.load();
        await rig.store.write(
          change == 'secret' ? _backend('a', 'new-secret') : _backend('b'),
        );
        if (change == 'ABA') await rig.store.write(_backend('a'));
        expect(rig.proxy.groups.lastGoodData, isNull);
        expect(rig.proxy.connections.lastGoodData, isNull);
        expect(await rig.proxy.selectNode(group: group, name: 'new'), isFalse);
        expect(rig.writes, isEmpty);
      },
    );
  }

  for (final duringWrite in [false, true]) {
    test(
      'same backend slow refresh cannot overwrite select (during=$duringWrite)',
      () async {
        final rig = _Rig();
        await rig.proxy.load();
        final readEntered = Completer<void>();
        final readGate = Completer<http.Response>();
        rig.onGroups = (_) {
          readEntered.complete();
          return readGate.future;
        };
        final writeEntered = Completer<void>();
        final writeGate = Completer<http.Response>();
        rig.onWrite = (_) {
          writeEntered.complete();
          return writeGate.future;
        };
        late Future<void> refresh;
        late Future<bool> select;
        if (duringWrite) {
          select = rig.proxy.selectNode(group: group, name: 'new');
          await writeEntered.future;
          refresh = rig.proxy.refresh();
          await readEntered.future;
        } else {
          refresh = rig.proxy.refresh();
          await readEntered.future;
          select = rig.proxy.selectNode(group: group, name: 'new');
          await writeEntered.future;
        }
        writeGate.complete(http.Response('', 204));
        expect(await select, isTrue);
        readGate.complete(rig.response('old'));
        await refresh;
        expect(rig.proxy.groups.lastGoodData!.single.now, 'new');
      },
    );
  }

  test(
    'old A read cannot populate B before B has a successful snapshot',
    () async {
      final rig = _Rig();
      final entered = Completer<void>();
      final gate = Completer<http.Response>();
      rig.onGroups = (_) {
        entered.complete();
        return gate.future;
      };
      final load = rig.proxy.load();
      await entered.future;
      await rig.store.write(_backend('b'));
      gate.complete(rig.response('old'));
      await load;
      expect(rig.proxy.groups.lastGoodData, isNull);
      expect(
        rig.probes.where((request) => request.url.host == 'b.example.test'),
        isEmpty,
      );
    },
  );

  test('A late probe cannot stamp a B node with the same name', () async {
    final rig = _Rig();
    await rig.proxy.load();
    final entered = Completer<void>();
    final gate = Completer<http.Response>();
    rig.onProbe = (request) {
      if (request.url.host == 'a.example.test') {
        entered.complete();
        return gate.future;
      }
      return Future.value(http.Response('{"delay":22}', 200));
    };
    final probe = rig.proxy.probeCurrents();
    await entered.future;
    await rig.store.write(_backend('b'));
    await rig.proxy.load();
    gate.complete(http.Response('{"delay":999}', 200));
    await probe;
    expect(rig.proxy.groups.lastGoodData!.single.nodes.first.delayMs, 22);
  });

  test('same backend failed refresh retains its authorized snapshot', () async {
    final rig = _Rig();
    await rig.proxy.load();
    rig.onGroups = (_) async => http.Response('{}', 503);
    await rig.proxy.refresh();
    expect(rig.proxy.groups.lastGoodData!.single.now, 'old');
    expect(await rig.proxy.selectNode(group: group, name: 'new'), isTrue);
    expect(rig.writes.single.url.host, 'a.example.test');
  });

  test('a write already sent to A cannot publish success into B', () async {
    final rig = _Rig();
    await rig.proxy.load();
    final entered = Completer<void>();
    final gate = Completer<http.Response>();
    rig.onWrite = (_) {
      entered.complete();
      return gate.future;
    };
    final select = rig.proxy.selectNode(group: group, name: 'new');
    await entered.future;
    await rig.store.write(_backend('b'));
    await rig.proxy.load();
    gate.complete(http.Response('', 204));
    expect(await select, isFalse);
    expect(rig.proxy.groups.lastGoodData!.single.now, 'old');
    expect(rig.writes.single.url.host, 'a.example.test');
  });

  test(
    'switch during post-select probe cannot report A success as current',
    () async {
      final rig = _Rig();
      await rig.proxy.load();
      final entered = Completer<void>();
      final gate = Completer<http.Response>();
      rig.onProbe = (_) {
        entered.complete();
        return gate.future;
      };
      final select = rig.proxy.selectNode(group: group, name: 'new');
      await entered.future;
      await rig.store.write(_backend('b'));
      gate.complete(http.Response('{"delay":999}', 200));
      expect(await select, isFalse);
    },
  );

  test(
    'a backend change from a hydration listener cannot authorize old data',
    () async {
      final rig = _Rig();
      var changed = false;
      var publishedOldSnapshot = false;
      rig.proxy.addListener(() {
        if (!changed) {
          changed = true;
          unawaited(rig.store.write(_backend('b')));
        } else if (rig.proxy.groups.lastGoodData != null) {
          publishedOldSnapshot = true;
        }
      });
      await rig.proxy.load();
      expect(publishedOldSnapshot, isFalse);
      expect(rig.proxy.groups.lastGoodData, isNull);
    },
  );
}

MihomoBackend _backend(String host, [String secret = '']) => MihomoBackend(
  origin: Uri.parse('http://$host.example.test:9090'),
  secret: secret,
);

final class _Rig {
  _Rig() {
    httpClient = MockClient((request) async {
      if (request.method == 'PUT') {
        writes.add(request);
        return onWrite?.call(request) ?? http.Response('', 204);
      }
      if (request.url.path == '/proxies') {
        return onGroups?.call(request) ?? groups(request);
      }
      if (request.url.path == '/connections') {
        return onConnections?.call(request) ?? connectionResponse('a', 100);
      }
      probes.add(request);
      return onProbe?.call(request) ?? http.Response('{"delay":20}', 200);
    });
    client = MihomoClient(
      client: httpClient,
      originProvider: () async => (await store.read())!.origin,
      secretProvider: () async => (await store.read())!.secret,
    );
    final registry = RequestRegistry();
    proxy = ProxyController(
      repository: DefaultProxyRepository(client),
      requestRegistry: registry,
      backendStore: store,
      clock: () => now,
    );
    settings = MihomoConnectionController(
      store: store,
      client: client,
      requestRegistry: registry,
    );
    addTearDown(proxy.dispose);
    addTearDown(settings.dispose);
    addTearDown(httpClient.close);
  }

  final store = MemoryMihomoBackendStore(_backend('a'));
  final writes = <http.Request>[];
  final probes = <http.Request>[];
  late final MockClient httpClient;
  late final MihomoClient client;
  late final ProxyController proxy;
  late final MihomoConnectionController settings;
  Future<http.Response> Function(http.Request)? onGroups;
  Future<http.Response> Function(http.Request)? onWrite;
  Future<http.Response> Function(http.Request)? onProbe;
  Future<http.Response> Function(http.Request)? onConnections;
  DateTime now = DateTime.utc(2026, 10, 8);

  http.Response connectionResponse(String host, int bytes) => http.Response(
    jsonEncode({
      'connections': [
        {
          'id': 'same-id',
          'download': bytes,
          'upload': 0,
          'chains': [group, 'old'],
          'metadata': {'host': host, 'destinationPort': '500'},
        },
      ],
    }),
    200,
  );

  http.Response groups(http.Request request) => response('old');
  http.Response response(String now) => http.Response(
    jsonEncode({
      'proxies': {
        group: {
          'type': 'Selector',
          'now': now,
          'all': ['old', 'new'],
        },
        'old': {'type': 'Shadowsocks', 'alive': true, 'history': <Object?>[]},
        'new': {'type': 'Shadowsocks', 'alive': true, 'history': <Object?>[]},
      },
    }),
    200,
  );
}
