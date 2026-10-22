import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/gateway_extension.dart';
import 'extensions_api.dart';

abstract interface class ExtensionsRepository {
  Future<List<GatewayExtension>> list({RequestCancellation? cancellation});
  Future<void> installFromUrl(
    String url, {
    String sha256,
    RequestCancellation? cancellation,
  });
  Future<void> setEnabled(
    String id,
    bool enabled, {
    RequestCancellation? cancellation,
  });
  Future<void> delete(String id, {RequestCancellation? cancellation});
}

final class DefaultExtensionsRepository implements ExtensionsRepository {
  const DefaultExtensionsRepository(this._api);
  final ExtensionsApi _api;

  @override
  Future<List<GatewayExtension>> list({
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'extensions-list',
      () => _api.list(cancellation: cancellation),
    );
  }

  @override
  Future<void> installFromUrl(
    String url, {
    String sha256 = '',
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'extensions-install',
      () => _api.installFromUrl(
        url,
        sha256: sha256,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<void> setEnabled(
    String id,
    bool enabled, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'extensions-enable',
      () => _api.setEnabled(id, enabled, cancellation: cancellation),
    );
  }

  @override
  Future<void> delete(String id, {RequestCancellation? cancellation}) {
    return guardShape(
      'extensions-delete',
      () => _api.delete(id, cancellation: cancellation),
    );
  }
}
