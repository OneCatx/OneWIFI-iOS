import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/base_url_policy.dart';
import '../security/gateway_trust_store.dart';

GatewayConnectionFactory createGatewayIoClient({
  GatewayTrustStore? trustStore,
}) => GatewayConnectionFactory(
  trustStore: trustStore ?? SecureGatewayTrustStore(),
);

/// One origin-scoped trust source for REST, Mihomo and upgraded WebSockets.
/// No pin means system validation. A configured leaf pin never falls back to CA.
final class GatewayConnectionFactory extends http.BaseClient
    implements Listenable {
  GatewayConnectionFactory({required GatewayTrustStore trustStore})
    : _store = trustStore;
  final GatewayTrustStore _store;
  final Map<Uri, _Connection> _connections = {};
  final Map<Uri, int> _generations = {};
  final Map<Uri, Future<void>> _writes = {};
  bool _closed = false;
  Uri? _changedTrustOrigin;

  /// Origin of the effective trust change being delivered synchronously.
  Uri? get changedTrustOrigin => _changedTrustOrigin;
  final _TrustChanges _trustChanges = _TrustChanges();
  @override
  void addListener(VoidCallback listener) =>
      _trustChanges.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      _trustChanges.removeListener(listener);

  static Uri originOf(Uri uri) => BaseUrlPolicy.parseAndValidate(
    Uri(
      scheme: switch (uri.scheme) {
        'wss' => 'https',
        'ws' => 'http',
        _ => uri.scheme,
      },
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString(),
  );

  Future<String?> readFingerprint(Uri origin) async {
    final key = originOf(origin);
    await _writes[key];
    return _store.readFingerprint(key);
  }

  Future<void> setFingerprint(Uri origin, String? fingerprint) {
    final key = originOf(origin);
    if (key.scheme != 'https') throw const FormatException('证书指纹仅用于 HTTPS。');
    final normalized = fingerprint == null
        ? null
        : normalizeCertificateFingerprint(fingerprint);
    final next = (_writes[key] ?? Future<void>.value()).then((_) async {
      if (_closed) throw StateError('Connection factory is closed.');
      var previousKnown = false;
      String? effectivePrevious;
      try {
        final previous = await _store.readFingerprint(key);
        effectivePrevious = previous == null
            ? null
            : normalizeCertificateFingerprint(previous);
        previousKnown = true;
      } catch (_) {
        // An explicit write/clear must still repair unreadable or corrupt trust.
        // Only proven equality may suppress a write; persistence errors below
        // remain visible to the caller and never publish a change.
      }
      if (_closed) throw StateError('Connection factory is closed.');
      if (previousKnown && effectivePrevious == normalized) return;
      if (normalized == null) {
        await _store.clearFingerprint(key);
      } else {
        await _store.writeFingerprint(key, normalized);
      }
      if (_closed) throw StateError('Connection factory is closed.');
      _generations[key] = (_generations[key] ?? 0) + 1;
      _connections.remove(key)?.close();
      _changedTrustOrigin = key;
      _trustChanges.changed();
    });
    // Keep the queue usable after failure, but report the storage error to UI.
    _writes[key] = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<_Connection> _connection(Uri uri) async {
    final origin = originOf(uri);
    while (true) {
      final writes = _writes[origin];
      await writes;
      if (_closed) throw http.ClientException('Connection factory is closed.');
      final generation = _generations[origin] ?? 0;
      final cached = _connections[origin];
      if (cached != null && cached.generation == generation) return cached;
      final pin = origin.scheme == 'https'
          ? await _store.readFingerprint(origin)
          : null;
      if (_closed) throw http.ClientException('Connection factory is closed.');
      if (generation != (_generations[origin] ?? 0) ||
          !identical(writes, _writes[origin])) {
        continue;
      }
      final installed = _connections[origin];
      if (installed != null && installed.generation == generation) {
        return installed;
      }
      final raw = HttpClient(
        context: pin == null ? null : SecurityContext(withTrustedRoots: false),
      );
      if (pin != null) {
        final expected = normalizeCertificateFingerprint(pin);
        raw.badCertificateCallback = (certificate, host, port) {
          final now = DateTime.now();
          return host.toLowerCase() == origin.host.toLowerCase() &&
              port == origin.port &&
              !now.isBefore(certificate.startValidity) &&
              !now.isAfter(certificate.endValidity) &&
              sha256.convert(certificate.der).toString() == expected;
        };
      }
      final connection = _Connection(origin, generation, raw);
      _connections[origin] = connection;
      return connection;
    }
  }

  bool _current(_Connection connection) =>
      !_closed &&
      identical(_connections[connection.origin], connection) &&
      connection.generation == (_generations[connection.origin] ?? 0);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final connection = await _connection(request.url);
    // Never reuse a credentialed origin's explicit trust across redirects.
    request.followRedirects = false;
    final response = await connection.client.send(request);
    if (!_current(connection)) {
      unawaited(response.stream.listen(null).cancel());
      throw http.ClientException(
        'Certificate trust changed during the request.',
      );
    }
    return response;
  }

  Future<WebSocket> openWebSocket(Uri uri) async {
    final connection = await _connection(uri);
    final socket = await WebSocket.connect(
      uri.toString(),
      customClient: connection.raw,
    );
    if (!_current(connection)) {
      await socket.close();
      throw http.ClientException(
        'Certificate trust changed during connection.',
      );
    }
    connection.sockets.add(socket);
    unawaited(
      socket.done.then<void>(
        (_) => connection.sockets.remove(socket),
        onError: (Object _) => connection.sockets.remove(socket),
      ),
    );
    return socket;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _trustChanges.dispose();
    for (final connection in _connections.values) {
      connection.close();
    }
    _connections.clear();
  }
}

final class _TrustChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

final class _Connection {
  _Connection(this.origin, this.generation, this.raw) : client = IOClient(raw);
  final Uri origin;
  final int generation;
  final HttpClient raw;
  final IOClient client;
  final Set<WebSocket> sockets = {};
  void close() {
    client.close();
    for (final socket in sockets.toList()) {
      unawaited(socket.close().then<void>((_) {}, onError: (Object _) {}));
    }
    sockets.clear();
  }
}
