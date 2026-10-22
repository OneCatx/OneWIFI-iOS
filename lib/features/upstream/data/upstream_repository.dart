import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/upstream_proxy.dart';
import 'upstream_api.dart';

abstract interface class UpstreamRepository {
  Future<List<UpstreamProxy>> list({RequestCancellation? cancellation});
  Future<void> setEnabled(
    String id,
    bool enabled, {
    RequestCancellation? cancellation,
  });
  Future<void> probe(String id, {RequestCancellation? cancellation});
}

final class DefaultUpstreamRepository implements UpstreamRepository {
  const DefaultUpstreamRepository(this._api);
  final UpstreamApi _api;

  @override
  Future<List<UpstreamProxy>> list({RequestCancellation? cancellation}) {
    return guardShape(
      'upstream-list',
      () => _api.list(cancellation: cancellation),
    );
  }

  @override
  Future<void> setEnabled(
    String id,
    bool enabled, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'upstream-enable',
      () => _api.setEnabled(id, enabled, cancellation: cancellation),
    );
  }

  @override
  Future<void> probe(String id, {RequestCancellation? cancellation}) {
    return guardShape(
      'upstream-probe',
      () => _api.probe(id, cancellation: cancellation),
    );
  }
}
