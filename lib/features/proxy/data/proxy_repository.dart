import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/mihomo_backend.dart';
import '../domain/wifi_call_connection.dart';
import '../domain/wifi_call_group.dart';
import '../domain/wifi_connection_catalog.dart';
import '../domain/wifi_selector_catalog.dart';
import 'mihomo_client.dart';

abstract interface class ProxyRepository {
  Future<List<WifiCallGroup>> fetchWifiCallGroups({
    RequestCancellation? cancellation,
  });

  Future<List<WifiCallConnection>> fetchConnections({
    RequestCancellation? cancellation,
    List<WifiCallConnection>? previous,
    DateTime? previousAt,
    DateTime? now,
  });

  Future<void> selectNode({
    required String group,
    required String name,
    RequestCancellation? cancellation,
  });

  Future<WifiDelay> probeDelay({
    required String name,
    String? altName,
    RequestCancellation? cancellation,
  });

  /// `null` = 不是组，退回逐叶子；空 map = 整组超时。
  Future<Map<String, WifiDelay>?> probeGroupDelay({
    required String name,
    RequestCancellation? cancellation,
  });
}

final class DefaultProxyRepository implements ProxyRepository {
  const DefaultProxyRepository(this._client) : _backend = null;
  const DefaultProxyRepository._bound(this._client, this._backend);

  final MihomoClient _client;
  final MihomoBackend? _backend;

  DefaultProxyRepository forBackend(MihomoBackend backend) =>
      DefaultProxyRepository._bound(_client, backend);

  @override
  Future<List<WifiCallGroup>> fetchWifiCallGroups({
    RequestCancellation? cancellation,
  }) {
    return guardShape('local-mihomo-response', () async {
      final proxies = await _client.fetchProxies(
        cancellation: cancellation,
        origin: _backend?.origin,
        secret: _backend?.secret,
      );
      return WifiSelectorCatalog.fromProxies(proxies);
    });
  }

  @override
  Future<List<WifiCallConnection>> fetchConnections({
    RequestCancellation? cancellation,
    List<WifiCallConnection>? previous,
    DateTime? previousAt,
    DateTime? now,
  }) {
    return guardShape('local-mihomo-response', () async {
      final raw = await _client.fetchConnections(
        cancellation: cancellation,
        origin: _backend?.origin,
        secret: _backend?.secret,
      );
      return WifiConnectionCatalog.fromConnections(
        raw,
        previous: previous,
        previousAt: previousAt,
        now: now,
      );
    });
  }

  @override
  Future<void> selectNode({
    required String group,
    required String name,
    RequestCancellation? cancellation,
  }) {
    return _client.selectProxy(
      group: group,
      name: name,
      cancellation: cancellation,
      origin: _backend?.origin,
      secret: _backend?.secret,
    );
  }

  @override
  Future<WifiDelay> probeDelay({
    required String name,
    String? altName,
    RequestCancellation? cancellation,
  }) async {
    final primary = await _client.fetchProxyDelay(
      name: name,
      cancellation: cancellation,
      origin: _backend?.origin,
      secret: _backend?.secret,
    );
    if (primary.kind != WifiDelayKind.unknown) return primary;
    final alt = altName?.trim();
    if (alt == null || alt.isEmpty || alt == name.trim()) return primary;
    return _client.fetchProxyDelay(
      name: alt,
      cancellation: cancellation,
      origin: _backend?.origin,
      secret: _backend?.secret,
    );
  }

  @override
  Future<Map<String, WifiDelay>?> probeGroupDelay({
    required String name,
    RequestCancellation? cancellation,
  }) {
    return _client.fetchGroupDelay(
      name: name,
      cancellation: cancellation,
      origin: _backend?.origin,
      secret: _backend?.secret,
    );
  }
}
