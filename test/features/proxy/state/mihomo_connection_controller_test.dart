import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_backend_store.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_client.dart';
import 'package:onewifi_android/features/proxy/domain/mihomo_backend.dart';
import 'package:onewifi_android/features/proxy/state/mihomo_connection_controller.dart';
import '../../../support/fakes.dart';

void main() {
  test('hydrate restores a saved backend', () async {
    final store = MemoryMihomoBackendStore(
      MihomoBackend(origin: Uri.parse('http://10.0.0.8:9090'), secret: 'clash'),
    );
    final controller = _controller(store);
    addTearDown(controller.dispose);

    await controller.hydrate();

    expect(controller.connected, isTrue);
    expect(controller.origin, Uri.parse('http://10.0.0.8:9090'));
    expect(controller.secret, 'clash');
  });

  test('hydrate with no saved backend leaves the form blank', () async {
    final controller = _controller(MemoryMihomoBackendStore());
    addTearDown(controller.dispose);

    await controller.hydrate();

    expect(controller.connected, isFalse);
    expect(controller.origin, isNull);
    expect(controller.secret, isEmpty);
  });

  test('connect without a secret does not send Authorization', () async {
    final store = MemoryMihomoBackendStore();
    final requests = <http.BaseRequest>[];
    final controller = _controller(
      store,
      FakeClient((request) async {
        requests.add(request);
        return http.StreamedResponse(
          Stream<List<int>>.value(
            utf8.encode(
              jsonEncode(<String, Object?>{'proxies': <String, Object?>{}}),
            ),
          ),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(controller.dispose);

    final ok = await controller.connect(
      host: '192.168.1.99',
      port: '9090',
      https: false,
      secret: '  ',
    );

    expect(ok, isTrue);
    expect(requests.single.headers.containsKey('authorization'), isFalse);
    final saved = await store.read();
    expect(saved!.origin, Uri.parse('http://192.168.1.99:9090'));
    expect(saved.secret, isEmpty);
  });

  test('connect probes GET /proxies then persists the backend', () async {
    final store = MemoryMihomoBackendStore();
    final requests = <http.BaseRequest>[];
    final controller = _controller(
      store,
      FakeClient((request) async {
        requests.add(request);
        return http.StreamedResponse(
          Stream<List<int>>.value(
            utf8.encode(
              jsonEncode(<String, Object?>{'proxies': <String, Object?>{}}),
            ),
          ),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(controller.dispose);

    final ok = await controller.connect(
      host: '192.168.1.88',
      port: '9090',
      https: false,
      secret: ' s3cret ',
    );

    expect(ok, isTrue);
    expect(controller.connectAction.status, ActionStatus.succeeded);
    expect(controller.connected, isTrue);
    expect(controller.status, '已连上');
    expect(requests.single.url.origin, 'http://192.168.1.88:9090');
    expect(requests.single.headers['authorization'], 'Bearer s3cret');
    final saved = await store.read();
    expect(saved!.origin, Uri.parse('http://192.168.1.88:9090'));
    expect(saved.secret, 's3cret');
  });

  test('connect keeps the store empty when Mihomo rejects the probe', () async {
    final store = MemoryMihomoBackendStore();
    final controller = _controller(
      store,
      FakeClient((request) async {
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('{"message":"Unauthorized"}')),
          401,
        );
      }),
    );
    addTearDown(controller.dispose);

    final ok = await controller.connect(
      host: '192.168.1.88',
      port: '9090',
      https: false,
      secret: 'bad',
    );

    expect(ok, isFalse);
    expect(controller.connected, isFalse);
    expect(controller.status, '密钥不对。');
    expect(await store.read(), isNull);
  });
}

MihomoConnectionController _controller(
  MihomoBackendStore store, [
  http.BaseClient? client,
]) {
  return MihomoConnectionController(
    store: store,
    client: MihomoClient(
      client:
          client ??
          FakeClient((request) async {
            return http.StreamedResponse(const Stream<List<int>>.empty(), 204);
          }),
      originProvider: () async => Uri.parse('http://unused.test:9090'),
    ),
    requestRegistry: RequestRegistry(),
  );
}
