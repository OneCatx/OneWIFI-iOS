import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/export_proxy.dart';

final class ExportProxyApi {
  const ExportProxyApi(this._transport);
  final HttpTransport _transport;

  Future<List<ExportProxyConfig>> list({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.exportProxies,
      cancellation: cancellation,
    );
    return _configs(data);
  }

  Future<List<ExportProxyConfig>> status({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.exportProxiesStatus,
      cancellation: cancellation,
    );
    return _configs(data, runningHint: true);
  }

  List<ExportProxyConfig> _configs(Object? data, {bool runningHint = false}) {
    final map = data is Map ? _shape.map(data) : const <String, Object?>{};
    final raw = map['configs'] ?? data;
    final items = raw is List ? raw : const <Object?>[];
    return List<ExportProxyConfig>.unmodifiable(
      items.map((e) => _parse(e, runningHint: runningHint)),
    );
  }

  static ExportProxyConfig _parse(Object? value, {bool runningHint = false}) {
    final map = _shape.map(value);
    final id = _shape.string(map['id']).trim();
    final port = map['listen_port'];
    return ExportProxyConfig(
      id: id,
      name: _opt(map['name'], id),
      mode: _opt(map['mode'], 'socks5'),
      listenHost: _opt(map['listen_host'], '127.0.0.1'),
      listenPort: port is num ? port.toInt() : int.tryParse('$port') ?? 0,
      enabled: map['enabled'] == true,
      deviceId: _opt(map['device_id'], ''),
      running: runningHint ? map['running'] != false : map['running'] == true,
    );
  }

  static String _opt(Object? value, String fallback) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? fallback : text;
  }
}

final class ExportProxyDtoException implements DtoShapeException {
  const ExportProxyDtoException();
}

const _shape = JsonShape(ExportProxyDtoException.new);
