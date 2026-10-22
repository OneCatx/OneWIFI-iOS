import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/gateway_extension.dart';

final class ExtensionsApi {
  const ExtensionsApi(this._transport);
  final HttpTransport _transport;

  Future<List<GatewayExtension>> list({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.extensions,
      cancellation: cancellation,
    );
    final items = data is List ? data : const <Object?>[];
    return List<GatewayExtension>.unmodifiable(items.map(_parse));
  }

  Future<void> installFromUrl(
    String url, {
    String sha256 = '',
    RequestCancellation? cancellation,
  }) async {
    final body = <String, String>{'url': url.trim()};
    final hash = sha256.trim();
    if (hash.isNotEmpty) body['sha256'] = hash;
    await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.extensionsInstallUrl,
      body: body,
      cancellation: cancellation,
    );
  }

  Future<void> setEnabled(
    String id,
    bool enabled, {
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.extensionItem,
      pathParameters: <String, String>{'id': id},
      body: <String, bool>{'enabled': enabled},
      cancellation: cancellation,
    );
  }

  Future<void> delete(
    String id, {
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendJson(
      method: 'DELETE',
      routeTemplate: GatewayApi.extensionItem,
      pathParameters: <String, String>{'id': id},
      cancellation: cancellation,
    );
  }

  static GatewayExtension _parse(Object? value) {
    final map = _shape.map(value);
    final id = _shape.string(map['id']).trim();
    return GatewayExtension(
      id: id,
      name: _opt(map['name'], id),
      enabled: map['enabled'] == true,
      version: _opt(map['version'], ''),
      description: _opt(map['description'], ''),
    );
  }

  static String _opt(Object? value, String fallback) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? fallback : text;
  }
}

final class ExtensionsDtoException implements DtoShapeException {
  const ExtensionsDtoException();
}

const _shape = JsonShape(ExtensionsDtoException.new);
