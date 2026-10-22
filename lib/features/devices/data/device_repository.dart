import '../../../core/http/http_transport.dart';
import '../domain/device.dart';
import 'device_api.dart';
import 'device_dto.dart';

enum DeviceCapability { network, vowifi, flightMode }

abstract interface class DeviceRepository {
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation});

  Future<DeviceDetail> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  });

  Future<void> setCapability({
    required String deviceId,
    required DeviceCapability capability,
    required bool enabled,
    RequestCancellation? cancellation,
  });

  Future<void> reconnectVowifi(
    String deviceId, {
    RequestCancellation? cancellation,
  });

  // dart format off
  // Privacy whitelist treats a one-line method whose first parameter is
  // followed by a comma as a multi-declarator field. Keep this wrapped.
  Future<void> reboot(
    String deviceId, {
    RequestCancellation? cancellation,
  });
  // dart format on

  Future<List<DiscoveredDevice>> fetchDiscoveredDevices({
    RequestCancellation? cancellation,
  });

  Future<DeviceRescanResult> rescanDevices({
    RequestCancellation? cancellation,
  });

  Future<void> registerDevice({
    required String deviceId,
    required String discoveryKey,
    required String deviceType,
    String? name,
    String? simPin,
    Map<String, Object?>? additionalConfig,
    RequestCancellation? cancellation,
  });
}

final class DefaultDeviceRepository implements DeviceRepository {
  const DefaultDeviceRepository(this._api);

  final DeviceApi _api;

  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) async {
    final dto = await _api.fetchDevices(cancellation: cancellation);
    return DeviceFleet(
      deviceLimit: dto.deviceLimit,
      devices: dto.devices.map(_deviceFromDto).toList(growable: false),
    );
  }

  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    final dto = await _api.fetchDeviceOverview(
      deviceId,
      cancellation: cancellation,
    );
    return DeviceDetail(
      device: _deviceFromDto(dto.device),
      traffic: _trafficFromDto(dto.traffic),
    );
  }

  @override
  Future<void> setCapability({
    required String deviceId,
    required DeviceCapability capability,
    required bool enabled,
    RequestCancellation? cancellation,
  }) {
    return switch (capability) {
      DeviceCapability.network => _api.patchNetwork(
        deviceId: deviceId,
        enabled: enabled,
        cancellation: cancellation,
      ),
      DeviceCapability.vowifi => _api.patchVowifi(
        deviceId: deviceId,
        enabled: enabled,
        cancellation: cancellation,
      ),
      DeviceCapability.flightMode => _api.patchFlightMode(
        deviceId: deviceId,
        enabled: enabled,
        cancellation: cancellation,
      ),
    };
  }

  @override
  Future<void> reconnectVowifi(
    String deviceId, {
    RequestCancellation? cancellation,
  }) {
    return _api.reconnectVowifi(deviceId, cancellation: cancellation);
  }

  // dart format off
  @override
  Future<void> reboot(
    String deviceId, {
    RequestCancellation? cancellation,
  }) {
    return _api.reboot(deviceId, cancellation: cancellation);
  }
  // dart format on

  @override
  Future<List<DiscoveredDevice>> fetchDiscoveredDevices({
    RequestCancellation? cancellation,
  }) async {
    final dto = await _api.fetchDiscoveredDevices(cancellation: cancellation);
    return dto.devices
        .map(_discoveredDeviceFromDto)
        .toList(growable: false);
  }

  @override
  Future<DeviceRescanResult> rescanDevices({
    RequestCancellation? cancellation,
  }) async {
    final dto = await _api.rescanDevices(cancellation: cancellation);
    return DeviceRescanResult(
      status: dto.status,
      devicesCount: dto.devicesCount,
    );
  }

  @override
  Future<void> registerDevice({
    required String deviceId,
    required String discoveryKey,
    required String deviceType,
    String? name,
    String? simPin,
    Map<String, Object?>? additionalConfig,
    RequestCancellation? cancellation,
  }) {
    return _api.registerDevice(
      deviceId: deviceId,
      discoveryKey: discoveryKey,
      deviceType: deviceType,
      name: name,
      simPin: simPin,
      additionalConfig: additionalConfig,
      cancellation: cancellation,
    );
  }
}

DeviceSnapshot _deviceFromDto(DeviceSnapshotDto dto) {
  return DeviceSnapshot(
    id: dto.id,
    name: dto.name,
    type: dto.type,
    healthy: dto.healthy,
    physicalPresent: dto.physicalPresent,
    controlOnline: dto.controlOnline,
    radioLive: dto.radioLive,
    radioRegistered: dto.radioRegistered,
    lifecyclePhase: dto.lifecyclePhase,
    lifecycleReasonCategory: dto.lifecycleReasonCategory,
    networkEnabled: dto.networkEnabled,
    networkConnected: dto.networkConnected,
    vowifiEnabled: dto.vowifiEnabled,
    vowifiActive: dto.vowifiActive,
    smsEnabled: dto.smsEnabled,
    flightMode: dto.flightMode,
    developerEnabled: dto.developerEnabled,
    modem: DeviceModem(
      operatorName: dto.modem.operatorName,
      servingOperator: dto.modem.servingOperator,
      model: dto.modem.model,
      firmware: dto.modem.firmware,
      networkMode: dto.modem.networkMode,
      radioBand: dto.modem.radioBand,
      signalDbm: dto.modem.signalDbm,
      signalRsrp: dto.modem.signalRsrp,
      signalRsrq: dto.modem.signalRsrq,
      signalSinr: dto.modem.signalSinr,
      simPresent: dto.modem.simPresent,
      serviceBlocked: dto.modem.serviceBlocked,
      blockedCategory: dto.modem.blockedCategory,
      regStatus: dto.modem.regStatus,
      regStatusText: dto.modem.regStatusText,
    ),
    identities: DeviceIdentityDisplays(
      imeiDisplay: dto.identities.imeiDisplay,
      iccidDisplay: dto.identities.iccidDisplay,
      imsiDisplay: dto.identities.imsiDisplay,
      phoneDisplay: dto.identities.phoneDisplay,
      imeiReveal: dto.identities.imeiReveal,
      iccidReveal: dto.identities.iccidReveal,
      imsiReveal: dto.identities.imsiReveal,
      phoneReveal: dto.identities.phoneReveal,
    ),
    runtime: DeviceRuntime(
      phase: dto.runtime.phase,
      simReady: dto.runtime.simReady,
      accessReady: dto.runtime.accessReady,
      tunnelReady: dto.runtime.tunnelReady,
      imsReady: dto.runtime.imsReady,
      smsReady: dto.runtime.smsReady,
      dataPlane: dto.runtime.dataPlane,
      lastReason: dto.runtime.lastReason,
      errorCategory: dto.runtime.errorCategory,
    ),
    esimSwitch: DeviceEsimSwitch(
      active: dto.esimSwitch.active,
      stages: dto.esimSwitch.stages,
    ),
    smsStorage: dto.smsStorage,
  );
}

DeviceTraffic _trafficFromDto(DeviceTrafficDto dto) {
  if (!dto.available) return const DeviceTraffic.unavailable();
  return DeviceTraffic.available(
    rxBytes: dto.rxBytes!,
    txBytes: dto.txBytes!,
    rxRateBytesPerSecond: dto.rxRateBytesPerSecond!,
    txRateBytesPerSecond: dto.txRateBytesPerSecond!,
    status: dto.status,
  );
}

DiscoveredDevice _discoveredDeviceFromDto(DiscoveredDeviceDto dto) {
  return DiscoveredDevice(
    hardwareKind: dto.hardwareKind,
    readerName: dto.readerName,
    deviceType: dto.deviceType,
    discoveryKey: dto.discoveryKey,
    controlPath: dto.controlPath,
    netInterface: dto.netInterface,
    usbPath: dto.usbPath,
    vendorId: dto.vendorId,
    productId: dto.productId,
    driverName: dto.driverName,
    atPorts: dto.atPorts,
    atPort: dto.atPort,
    imei: dto.imei,
    mode: dto.mode,
    networkCapable: dto.networkCapable,
    configured: dto.configured,
    configuredId: dto.configuredId,
    degraded: dto.degraded,
    discoveryIssue: dto.discoveryIssue,
  );
}
