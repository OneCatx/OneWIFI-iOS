import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import 'overview_dto.dart';

final class OverviewApi {
  const OverviewApi(this._transport);

  final HttpTransport _transport;

  Future<HostOverviewDto> fetchHost({RequestCancellation? cancellation}) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.dashboardHost,
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
    return _parse(() => HostOverviewDto.fromData(data));
  }

  Future<List<DeviceOverviewDto>> fetchDevices({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.dashboardDevices,
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
    return _parse(() => DeviceOverviewDto.listFromData(data));
  }

  static T _parse<T>(T Function() parse) =>
      guardShapeSync('local-overview-response', parse);
}
