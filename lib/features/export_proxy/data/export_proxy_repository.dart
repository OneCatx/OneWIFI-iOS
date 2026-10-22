import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/export_proxy.dart';
import 'export_proxy_api.dart';

abstract interface class ExportProxyRepository {
  Future<List<ExportProxyConfig>> list({RequestCancellation? cancellation});
  Future<List<ExportProxyConfig>> status({RequestCancellation? cancellation});
}

final class DefaultExportProxyRepository implements ExportProxyRepository {
  const DefaultExportProxyRepository(this._api);
  final ExportProxyApi _api;

  @override
  Future<List<ExportProxyConfig>> list({
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'export-proxy-list',
      () => _api.list(cancellation: cancellation),
    );
  }

  @override
  Future<List<ExportProxyConfig>> status({
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'export-proxy-status',
      () => _api.status(cancellation: cancellation),
    );
  }
}
