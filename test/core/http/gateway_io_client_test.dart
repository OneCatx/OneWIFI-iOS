import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/gateway_io_client.dart';
import 'package:onewifi_android/core/security/gateway_trust_store.dart';

void main() {
  test('pin replacement supersedes a delayed storage read', () async {
    final server = await _Tls.start();
    final store = _DelayedStore();
    final client = createGatewayIoClient(trustStore: store);
    final old = client.get(server.origin);
    final assertion = expectLater(old, throwsException);
    await store.entered.future;
    await client.setFingerprint(server.origin, '0' * 64);
    store.gate.complete(_certificatePin());
    try {
      await assertion;
    } finally {
      client.close();
      await server.close();
    }
  });

  test(
    'closing during delayed storage lookup cannot resurrect a connection',
    () async {
      final server = await _Tls.start();
      final store = _DelayedStore();
      final client = createGatewayIoClient(trustStore: store);
      final assertion = expectLater(client.get(server.origin), throwsException);
      await store.entered.future;
      client.close();
      store.gate.complete(_certificatePin());
      try {
        await assertion;
        expect(server.requests, 0);
      } finally {
        await server.close();
      }
    },
  );

  test(
    'failed trust persistence retains the previous working connection policy',
    () async {
      final server = await _Tls.start();
      final store = _Store();
      final client = createGatewayIoClient(trustStore: store);
      try {
        await client.setFingerprint(server.origin, _certificatePin());
        expect((await client.get(server.origin)).body, 'ok');
        store.failWrites = true;
        await expectLater(
          client.setFingerprint(server.origin, '0' * 64),
          throwsStateError,
        );
        expect((await client.get(server.origin)).body, 'ok');
      } finally {
        client.close();
        await server.close();
      }
    },
  );

  test(
    'changing trust invalidates a WebSocket handshake that has not upgraded',
    () async {
      final server = await _Tls.start(pauseUpgrade: true);
      final client = createGatewayIoClient(trustStore: _Store());
      try {
        await client.setFingerprint(server.origin, _certificatePin());
        final assertion = expectLater(
          client.openWebSocket(
            server.origin.replace(scheme: 'wss', path: '/ws'),
          ),
          throwsException,
        );
        await server.upgradeEntered.future.timeout(const Duration(seconds: 5));
        await client.setFingerprint(server.origin, '0' * 64);
        server.releaseUpgrade.complete();
        await assertion;
      } finally {
        client.close();
        await server.close();
      }
    },
  );

  test(
    'a CA-trusted certificate cannot bypass an explicitly wrong leaf pin',
    () async {
      final server = await _Tls.start();
      try {
        // Test-only default trust roots; do not mutate the process/global context.
        await HttpOverrides.runWithHttpOverrides(() async {
          final client = createGatewayIoClient(trustStore: _Store());
          try {
            expect((await client.get(server.origin)).body, 'ok');
            await client.setFingerprint(server.origin, '0' * 64);
            await expectLater(client.get(server.origin), throwsException);
          } finally {
            client.close();
          }
        }, _TrustedFixtureRoots());
      } finally {
        await server.close();
      }
    },
  );
  test('default gateway client rejects an untrusted TLS certificate', () async {
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain('test/support/tls/tls-cert.pem')
        ..usePrivateKey('test/support/tls/tls-key.pem'),
    );
    final subscription = server.listen((r) {
      r.response.write('ok');
      unawaited(r.response.close());
    });
    final client = createGatewayIoClient(trustStore: _Store());
    try {
      await expectLater(
        client.get(Uri.parse('https://127.0.0.1:${server.port}/')),
        throwsException,
      );
    } finally {
      client.close();
      await server.close(force: true);
      await subscription.cancel();
    }
  });

  test(
    'explicit leaf fingerprint permits HTTP and WSS only for its origin',
    () async {
      final context = SecurityContext()
        ..useCertificateChain('test/support/tls/tls-cert.pem')
        ..usePrivateKey('test/support/tls/tls-key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      final serverSockets = <WebSocket>[];
      final subscription = server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          serverSockets.add(socket);
          socket.add('connected');
          socket.listen((_) {});
        } else {
          request.response.write('ok');
          await request.response.close();
        }
      });
      final store = _Store();
      final client = createGatewayIoClient(trustStore: store);
      final origin = Uri.parse('https://127.0.0.1:${server.port}');
      final pem = File('test/support/tls/tls-cert.pem').readAsStringSync();
      final der = base64Decode(
        pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''),
      );
      final pin = sha256.convert(der).toString();
      try {
        await client.setFingerprint(origin, pin.toUpperCase());
        expect((await client.get(origin)).body, 'ok');
        final wsUri = origin.replace(scheme: 'wss', path: '/ws');
        final socket = await client.openWebSocket(wsUri);
        final received = Completer<void>();
        final done = Completer<void>();
        socket.listen((event) {
          if (event == 'connected') received.complete();
        }, onDone: done.complete);
        await received.future.timeout(const Duration(seconds: 5));
        await client.setFingerprint(origin, '0' * 64);
        await done.future.timeout(const Duration(seconds: 5));
        await expectLater(client.get(origin), throwsException);
        await expectLater(client.openWebSocket(wsUri), throwsException);
        await client.setFingerprint(origin, pin);
        await expectLater(
          client.get(origin.replace(host: 'localhost')),
          throwsException,
        );
        await client.setFingerprint(origin, null);
        await expectLater(client.get(origin), throwsException);
      } finally {
        client.close();
        for (final socket in serverSockets) {
          unawaited(socket.close());
        }
        await server.close(force: true);
        await subscription.cancel();
      }
    },
  );
}

class _Store implements GatewayTrustStore {
  final pins = <Uri, String>{};
  bool failWrites = false;
  @override
  Future<String?> readFingerprint(Uri origin) async => pins[origin];
  @override
  Future<void> writeFingerprint(Uri origin, String fingerprint) async {
    if (failWrites) throw StateError('synthetic write failure');
    pins[origin] = fingerprint;
  }

  @override
  Future<void> clearFingerprint(Uri origin) async {
    pins.remove(origin);
  }
}

String _certificatePin() {
  final pem = File('test/support/tls/tls-cert.pem').readAsStringSync();
  return sha256
      .convert(base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '')))
      .toString();
}

class _DelayedStore extends _Store {
  final gate = Completer<String?>();
  final entered = Completer<void>();
  @override
  Future<String?> readFingerprint(Uri origin) {
    if (!entered.isCompleted) {
      entered.complete();
      return gate.future;
    }
    return super.readFingerprint(origin);
  }
}

class _TrustedFixtureRoots extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(
        context ??
            (SecurityContext(withTrustedRoots: false)
              ..setTrustedCertificates('test/support/tls/tls-cert.pem')),
      );
}

class _Tls {
  _Tls(this.server, this.pauseUpgrade);
  final HttpServer server;
  final bool pauseUpgrade;
  late final StreamSubscription<HttpRequest> subscription;
  final sockets = <WebSocket>[];
  final upgradeEntered = Completer<void>();
  final releaseUpgrade = Completer<void>();
  int requests = 0;
  Uri get origin => Uri.parse('https://127.0.0.1:${server.port}');
  static Future<_Tls> start({bool pauseUpgrade = false}) async {
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain('test/support/tls/tls-cert.pem')
        ..usePrivateKey('test/support/tls/tls-key.pem'),
    );
    final fixture = _Tls(server, pauseUpgrade);
    fixture.subscription = server.listen((request) async {
      fixture.requests++;
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        if (!fixture.upgradeEntered.isCompleted) {
          fixture.upgradeEntered.complete();
        }
        if (pauseUpgrade) await fixture.releaseUpgrade.future;
        try {
          final socket = await WebSocketTransformer.upgrade(request);
          fixture.sockets.add(socket);
          socket.listen((_) {}, onError: (Object _) {});
        } on Exception {
          // The client deliberately revoked trust during the held handshake.
          if (!pauseUpgrade) rethrow;
        }
      } else {
        request.response.write('ok');
        await request.response.close();
      }
    });
    return fixture;
  }

  Future<void> close() async {
    if (pauseUpgrade && !releaseUpgrade.isCompleted) releaseUpgrade.complete();
    for (final socket in sockets) {
      unawaited(socket.close());
    }
    await server.close(force: true);
    await subscription.cancel();
  }
}
