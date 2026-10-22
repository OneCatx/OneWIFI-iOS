import '../../../core/http/http_transport.dart';
import '../domain/overview.dart';
import 'overview_api.dart';

abstract interface class OverviewRepository {
  Future<HostOverview> fetchHost({RequestCancellation? cancellation});

  Future<List<DeviceOverview>> fetchDevices({
    RequestCancellation? cancellation,
  });
}

final class DefaultOverviewRepository implements OverviewRepository {
  const DefaultOverviewRepository(this._api);

  final OverviewApi _api;

  @override
  Future<HostOverview> fetchHost({RequestCancellation? cancellation}) async {
    return (await _api.fetchHost(cancellation: cancellation)).toDomain();
  }

  @override
  Future<List<DeviceOverview>> fetchDevices({
    RequestCancellation? cancellation,
  }) async {
    final dtos = await _api.fetchDevices(cancellation: cancellation);
    return dtos.map((dto) => dto.toDomain()).toList(growable: false);
  }
}
