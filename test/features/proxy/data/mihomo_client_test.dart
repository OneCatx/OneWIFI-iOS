import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_client.dart';
import 'package:onewifi_android/features/proxy/data/proxy_repository.dart';
import 'package:onewifi_android/features/proxy/domain/mihomo_backend.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_call_group.dart';
import '../../../support/fakes.dart';

void main() {
  test(
    'atomic backend provider resolves origin and secret from one snapshot',
    () async {
      var reads = 0;
      http.BaseRequest? sent;
      final client = MihomoClient(
        client: FakeClient((request) async {
          sent = request;
          return _json(204, const <String, Object?>{});
        }),
        backendProvider: () async {
          reads++;
          return MihomoBackend(
            origin: Uri.parse('http://a.test:9090'),
            secret: 'a-secret',
          );
        },
        originProvider: () async =>
            throw StateError('legacy provider must not run'),
        secretProvider: () async =>
            throw StateError('legacy provider must not run'),
      );
      await client.selectProxy(group: 'HK-WIFI', name: 'node');
      expect(reads, 1);
      expect(sent!.url.host, 'a.test');
      expect(sent!.headers['authorization'], 'Bearer a-secret');
    },
  );

  test(
    'bound repository keeps empty secret and fallback probes on captured origin',
    () async {
      final requests = <http.BaseRequest>[];
      final client = MihomoClient(
        client: FakeClient((request) async {
          requests.add(request);
          return request.url.path.endsWith('/delay')
              ? _json(404, const <String, Object?>{})
              : _json(204, const <String, Object?>{});
        }),
        originProvider: () async => Uri.parse('http://b.test:9090'),
        secretProvider: () async => 'b-secret',
      );
      final repository = DefaultProxyRepository(
        client,
      ).forBackend(MihomoBackend(origin: Uri.parse('http://a.test:9090')));
      await repository.selectNode(group: 'HK-WIFI', name: 'node');
      await repository.probeDelay(name: 'primary', altName: 'fallback');
      expect(requests, hasLength(3));
      expect(requests.every((r) => r.url.host == 'a.test'), isTrue);
      expect(
        requests.every((r) => !r.headers.containsKey('authorization')),
        isTrue,
      );
      expect(requests.last.url.path, '/proxies/fallback/delay');
    },
  );

  test(
    'GET /proxies reads the raw Clash map without a data envelope',
    () async {
      final client = MihomoClient(
        client: FakeClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.origin, 'http://mihomo.example.test:9090');
          expect(request.url.path, '/proxies');
          expect(request.headers.containsKey('authorization'), isFalse);
          return _json(200, <String, Object?>{
            'proxies': <String, Object?>{
              'HK-WIFI Selector': <String, Object?>{
                'type': 'Selector',
                'now': 'TAG | 香港 家宽 01',
                'all': <Object?>['TAG | 香港 家宽 01'],
              },
            },
          });
        }),
        originProvider: () async =>
            Uri.parse('http://mihomo.example.test:9090'),
        requestIdGenerator: () => 'mihomo-test',
      );

      final proxies = await client.fetchProxies();
      expect(proxies.keys, <String>['HK-WIFI Selector']);
    },
  );

  test('GET /connections reads the raw Clash list', () async {
    final client = MihomoClient(
      client: FakeClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/connections');
        return _json(200, <String, Object?>{
          'connections': <Object?>[
            <String, Object?>{
              'id': 'c1',
              'download': 10,
              'upload': 2,
              'chains': <Object?>['DIRECT'],
              'metadata': <String, Object?>{
                'host': '120.53.53.53',
                'destinationPort': '443',
              },
            },
          ],
        });
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );

    final payload = await client.fetchConnections();
    expect(
      (payload['connections'] as List<Object?>).single,
      isA<Map<dynamic, dynamic>>(),
    );
  });

  test('PUT selects a node and encodes the group name', () async {
    http.BaseRequest? put;
    final client = MihomoClient(
      client: FakeClient((request) async {
        put = request;
        return http.StreamedResponse(const Stream<List<int>>.empty(), 204);
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );

    await client.selectProxy(group: 'HK-WIFI Selector', name: 'TAG | 香港 家宽 02');

    expect(put!.method, 'PUT');
    expect(put!.url.pathSegments, <String>['proxies', 'HK-WIFI Selector']);
    final body =
        jsonDecode(utf8.decode(await put!.finalize().toBytes()))
            as Map<String, Object?>;
    expect(body, <String, Object?>{'name': 'TAG | 香港 家宽 02'});
  });

  test('GET delay returns milliseconds and classifies failures', () async {
    http.BaseRequest? delayRequest;
    final client = MihomoClient(
      client: FakeClient((request) async {
        delayRequest = request;
        expect(request.method, 'GET');
        expect(request.url.pathSegments, <String>['proxies', 'home', 'delay']);
        expect(request.url.queryParameters['timeout'], '5000');
        return _json(200, <String, Object?>{'delay': 88});
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );
    expect(await client.fetchProxyDelay(name: 'home'), WifiDelay.measured(88));
    expect(
      delayRequest!.url.queryParameters['url'],
      'https://www.gstatic.com/generate_204',
    );

    final timedOut = MihomoClient(
      client: FakeClient((request) async {
        return http.StreamedResponse(const Stream<List<int>>.empty(), 504);
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );
    expect(
      await timedOut.fetchProxyDelay(name: 'home'),
      const WifiDelay.timedOut(),
    );

    final missing = MihomoClient(
      client: FakeClient((request) async {
        return http.StreamedResponse(const Stream<List<int>>.empty(), 404);
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );
    expect(
      await missing.fetchProxyDelay(name: 'home'),
      const WifiDelay.unknown(),
    );

    final zero = MihomoClient(
      client: FakeClient((request) async {
        return _json(200, <String, Object?>{'delay': 0});
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );
    expect(
      await zero.fetchProxyDelay(name: 'home'),
      const WifiDelay.timedOut(),
    );

    final unavailable = MihomoClient(
      client: FakeClient((request) async {
        return _json(503, <String, Object?>{
          'message': 'An error occurred in the delay test',
        });
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );
    expect(
      await unavailable.fetchProxyDelay(name: 'MESL | 香港 家宽 01'),
      const WifiDelay.timedOut(),
    );
  });

  test('GET group delay stamps pipe names from the JSON map', () async {
    http.BaseRequest? seen;
    final client = MihomoClient(
      client: FakeClient((request) async {
        seen = request;
        return _json(200, <String, Object?>{
          'MESL | 香港 家宽 01': 88,
          'MESL | 香港 家宽 02': 0,
        });
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );

    expect(await client.fetchGroupDelay(name: 'HK-WIFI Selector'), {
      'MESL | 香港 家宽 01': WifiDelay.measured(88),
      'MESL | 香港 家宽 02': const WifiDelay.timedOut(),
    });
    expect(seen!.url.pathSegments, <String>[
      'group',
      'HK-WIFI Selector',
      'delay',
    ]);
    expect(seen!.url.queryParameters['timeout'], '5000');

    final missing = MihomoClient(
      client: FakeClient((request) async {
        return http.StreamedResponse(const Stream<List<int>>.empty(), 404);
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );
    expect(await missing.fetchGroupDelay(name: 'HK-WIFI Selector'), isNull);

    final unavailable = MihomoClient(
      client: FakeClient((request) async {
        return _json(503, <String, Object?>{
          'message': 'An error occurred in the delay test',
        });
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );
    expect(
      await unavailable.fetchGroupDelay(name: 'HK-WIFI Selector'),
      const <String, WifiDelay>{},
    );
  });

  test('GET delay encodes a pipe in the path, not as a query break', () async {
    http.BaseRequest? seen;
    final client = MihomoClient(
      client: FakeClient((request) async {
        seen = request;
        return _json(200, <String, Object?>{'delay': 12});
      }),
      originProvider: () async => Uri.parse('http://mihomo.example.test:9090'),
      requestIdGenerator: () => 'mihomo-test',
    );

    expect(
      await client.fetchProxyDelay(name: 'TAG | 香港 家宽 01'),
      WifiDelay.measured(12),
    );
    expect(seen!.url.pathSegments, <String>[
      'proxies',
      'TAG | 香港 家宽 01',
      'delay',
    ]);
  });

  test(
    '401 stays a local auth failure and does not look like OneWIFI JSON',
    () async {
      final client = MihomoClient(
        client: FakeClient((request) async {
          return _json(401, <String, Object?>{'message': 'Unauthorized'});
        }),
        originProvider: () async =>
            Uri.parse('http://mihomo.example.test:9090'),
        requestIdGenerator: () => 'mihomo-test',
      );

      expect(
        client.fetchProxies(),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.authentication,
          ),
        ),
      );
    },
  );
}

http.StreamedResponse _json(int status, Object body) => http.StreamedResponse(
  Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);
