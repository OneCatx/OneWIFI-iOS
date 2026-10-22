import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/extensions/data/extensions_api.dart';

import '../../../support/fakes.dart';

void main() {
  test('ExtensionsApi list / enable / install-url hit WEB paths', () async {
    final calls = <http.BaseRequest>[];
    final api = ExtensionsApi(
      HttpTransport(
        client: FakeClient((request) async {
          calls.add(request);
          if (request.method == 'GET' &&
              request.url.path == '/api/extensions') {
            return _success(<Object?>[
              <String, Object?>{
                'id': 'demo',
                'name': 'Demo',
                'enabled': true,
                'version': '1',
              },
            ]);
          }
          return _success(<String, Object?>{});
        }),
        originProvider: () async => Uri.parse('https://api.example.test'),
        tokenProvider: (_) async => 'test-token',
        requestIdGenerator: () => 'extensions-api-test',
      ),
    );

    final list = await api.list();
    expect(list, hasLength(1));
    expect(list.single.id, 'demo');
    expect(calls.single.url.path, '/api/extensions');

    await api.setEnabled('demo', false);
    expect(calls.last.method, 'PUT');
    expect(calls.last.url.path, '/api/extensions/demo');

    await api.installFromUrl('https://example.com/p.zip', sha256: 'abc');
    expect(calls.last.method, 'POST');
    expect(calls.last.url.path, '/api/extensions/install-url');
  });
}

http.StreamedResponse _success(Object? data) => http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(jsonEncode(<String, Object?>{'data': data})),
      ),
      200,
    );
