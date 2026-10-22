import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import 'device_dto.dart';

final class DeviceApi {
  const DeviceApi(this._transport);

  final HttpTransport _transport;

  Future<DeviceFleetDto> fetchDevices({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.devices,
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
    return _parse(() => DeviceFleetDto.fromData(data));
  }

  /// WEB: detail is `GET /api/devices/{id}/overview` — not bare `GET …/{id}` (405).
  Future<DeviceDetailDto> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: '/api/devices/{id}/overview',
      pathParameters: <String, String>{'id': deviceId},
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
    return _parse(
      () => DeviceDetailDto.fromData(data, expectedDeviceId: deviceId),
    );
  }

  Future<void> patchNetwork({
    required String deviceId,
    required bool enabled,
    RequestCancellation? cancellation,
  }) => _sendEnabled(
    method: 'PATCH',
    routeTemplate: '/api/devices/{id}/network',
    deviceId: deviceId,
    enabled: enabled,
    cancellation: cancellation,
  );

  Future<void> patchVowifi({
    required String deviceId,
    required bool enabled,
    RequestCancellation? cancellation,
  }) => _sendEnabled(
    method: 'PATCH',
    routeTemplate: '/api/devices/{id}/vowifi',
    deviceId: deviceId,
    enabled: enabled,
    cancellation: cancellation,
  );

  Future<void> patchFlightMode({
    required String deviceId,
    required bool enabled,
    RequestCancellation? cancellation,
  }) => _sendEnabled(
    method: 'PATCH',
    routeTemplate: '/api/devices/{id}/flight-mode',
    deviceId: deviceId,
    enabled: enabled,
    cancellation: cancellation,
  );

  Future<void> reconnectVowifi(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendJson(
      method: 'POST',
      routeTemplate: '/api/devices/{id}/vowifi/actions/reconnect',
      pathParameters: <String, String>{'id': deviceId},
      body: const <String, Object?>{},
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
  }

  Future<void> reboot(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendJson(
      method: 'POST',
      routeTemplate: '/api/devices/{id}/actions/reboot',
      pathParameters: <String, String>{'id': deviceId},
      body: const <String, Object?>{},
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
  }

  /// WEB: `POST /api/devices/{id}/actions/refresh` — modem snapshot refresh.
  Future<void> refreshSnapshot(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendJson(
      method: 'POST',
      routeTemplate: '/api/devices/{id}/actions/refresh',
      pathParameters: <String, String>{'id': deviceId},
      body: const <String, Object?>{},
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
  }

  Future<DiscoveredDevicesDto> fetchDiscoveredDevices({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.devicesDiscovered,
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
    return _parse(() => DiscoveredDevicesDto.fromData(data));
  }

  Future<DeviceRescanResultDto> rescanDevices({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.devicesRescan,
      body: const <String, Object?>{},
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
    return _parse(() => DeviceRescanResultDto.fromData(data));
  }

  Future<void> registerDevice({
    required String deviceId,
    required String discoveryKey,
    required String deviceType,
    String? name,
    String? simPin,
    Map<String, Object?>? additionalConfig,
    RequestCancellation? cancellation,
  }) async {
    final config = <String, Object?>{
      'id': deviceId,
      'device_type': deviceType,
      'discovery_key': discoveryKey,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (simPin != null && simPin.trim().isNotEmpty) 'sim_pin': simPin.trim(),
      ...?additionalConfig,
    };

    await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.devices,
      body: <String, Object?>{'config': config},
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
  }

  Future<void> _sendEnabled({
    required String method,
    required String routeTemplate,
    required String deviceId,
    required bool enabled,
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendJson(
      method: method,
      routeTemplate: routeTemplate,
      pathParameters: <String, String>{'id': deviceId},
      body: <String, Object?>{'enabled': enabled},
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
  }

  static T _parse<T>(T Function() parse) =>
      guardShapeSync('local-device-response', parse);
}
