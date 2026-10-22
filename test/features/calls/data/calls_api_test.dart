import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/calls/data/calls_api.dart';

import '../../../support/fakes.dart';

void main() {
  test(
    'injected connector receives the WSS URI and owns transport trust',
    () async {
      final client = FakeClient(
        (_) async => throw StateError('REST not expected'),
      );
      final transport = HttpTransport(
        client: client,
        originProvider: () async => Uri.parse('https://gateway.test:8443'),
        tokenProvider: (_) async => null,
      );
      final expected = _Socket();
      Uri? captured;
      Future<WebSocket> connect(Uri uri) async {
        captured = uri;
        return expected;
      }

      final api = CallsApi(transport, socketConnector: connect);
      final socket = await api.openMediaSocket(
        origin: Uri.parse('https://gateway.test:8443'),
        deviceId: 'a/b',
        callId: 'call-1',
        accessToken: null,
      );
      expect(identical(socket, expected), isTrue);
      expect(captured!.scheme, 'wss');
      expect(captured!.host, 'gateway.test');
      expect(captured!.port, 8443);
      expect(captured!.pathSegments, [
        'api',
        'devices',
        'a/b',
        'calls',
        'media',
      ]);
      expect(captured!.queryParameters, {'id': 'call-1'});
    },
  );

  test('media socket preserves reserved device and call identifiers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<WebSocket>();
    final requested = Completer<Uri>();
    server.listen((request) async {
      requested.complete(request.uri);
      accepted.complete(await WebSocketTransformer.upgrade(request));
    });
    addTearDown(() => server.close(force: true));
    final origin = Uri.parse('http://127.0.0.1:${server.port}');
    final client = FakeClient(
      (_) async => throw StateError('REST not expected'),
    );
    final api = CallsApi(
      HttpTransport(
        client: client,
        originProvider: () async => origin,
        tokenProvider: (_) async => 'ignored',
      ),
    );
    final socket = await api.openMediaSocket(
      origin: origin,
      deviceId: 'device/a % 中文',
      callId: 'call/?+%',
      accessToken: 'test-token',
    );
    final peer = await accepted.future;
    socket.listen((_) {});
    peer.listen((_) {});
    addTearDown(() async {
      await Future.wait([socket.close(), peer.close()]);
    });
    final uri = await requested.future;
    expect(uri.pathSegments, [
      'api',
      'devices',
      'device/a % 中文',
      'calls',
      'media',
    ]);
    expect(uri.queryParameters, {
      'id': 'call/?+%',
      'access_token': 'test-token',
    });
  });
}

class _Socket implements WebSocket {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
