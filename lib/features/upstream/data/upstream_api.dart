import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/upstream_proxy.dart';

final class UpstreamApi {
  const UpstreamApi(this._transport);
  final HttpTransport _transport;

  Future<List<UpstreamProxy>> list({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.upstreamProxies,
      cancellation: cancellation,
    );
    final items = data is List ? data : const <Object?>[];
    return List<UpstreamProxy>.unmodifiable(items.map(_parse));
  }

  Future<void> setEnabled(
    String id,
    bool enabled, {
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendJson(
      method: 'PATCH',
      routeTemplate: GatewayApi.upstreamProxyItem,
      pathParameters: <String, String>{'id': id},
      body: <String, bool>{'enabled': enabled},
      cancellation: cancellation,
    );
  }

  Future<void> probe(
    String id, {
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.upstreamProxyProbeActionPath,
      pathParameters: <String, String>{'id': id},
      body: const <String, Object?>{},
      cancellation: cancellation,
    );
  }

  static UpstreamProxy _parse(Object? value) {
    final map = _shape.map(value);
    final id = _shape.string(map['id']).trim();
    return UpstreamProxy(
      id: id,
      name: _opt(map['name'], id),
      addr: _opt(map['addr'], _opt(map['server'], '')),
      enabled: map['enabled'] != false,
    );
  }

  static String _opt(Object? value, String fallback) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? fallback : text;
  }
}

final class UpstreamDtoException implements DtoShapeException {
  const UpstreamDtoException();
}

const _shape = JsonShape(UpstreamDtoException.new);
