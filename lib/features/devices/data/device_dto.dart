import '../../../core/http/json_shape.dart';
import '../../../core/security/redaction.dart';
import '../domain/device.dart';

final class DeviceFleetDto {
  DeviceFleetDto._({
    required this.deviceLimit,
    required List<DeviceSnapshotDto> devices,
  }) : devices = List<DeviceSnapshotDto>.unmodifiable(devices);

  factory DeviceFleetDto.fromData(Object? value) {
    final data = _shape.map(value);
    final limit = _shape.nonNegativeIntegralInt(data['device_limit']);
    final devices = _shape
        .list(data['devices'])
        .map((item) => DeviceSnapshotDto._fromData(item, detail: false))
        .toList(growable: false);
    return DeviceFleetDto._(deviceLimit: limit, devices: devices);
  }

  final int deviceLimit;
  final List<DeviceSnapshotDto> devices;
}

final class DeviceDetailDto {
  const DeviceDetailDto._({required this.device, required this.traffic});

  factory DeviceDetailDto.fromData(
    Object? value, {
    required String expectedDeviceId,
  }) {
    final data = _shape.map(value);
    final devices = _shape.list(data['devices']);
    if (devices.length != 1) throw const DeviceDtoException();
    final device = DeviceSnapshotDto._fromData(devices.single, detail: true);
    if (device.id != expectedDeviceId) throw const DeviceDtoException();
    return DeviceDetailDto._(
      device: device,
      traffic: DeviceTrafficDto._fromDetailData(_shape.map(devices.single)),
    );
  }

  final DeviceSnapshotDto device;
  final DeviceTrafficDto traffic;
}

final class DeviceSnapshotDto {
  const DeviceSnapshotDto._({
    required this.id,
    required this.name,
    required this.type,
    required this.healthy,
    required this.physicalPresent,
    required this.controlOnline,
    required this.radioLive,
    required this.radioRegistered,
    required this.lifecyclePhase,
    required this.lifecycleReasonCategory,
    required this.networkEnabled,
    required this.networkConnected,
    required this.vowifiEnabled,
    required this.vowifiActive,
    required this.smsEnabled,
    required this.flightMode,
    required this.developerEnabled,
    required this.modem,
    required this.identities,
    required this.runtime,
    required this.esimSwitch,
    this.smsStorage,
  });

  factory DeviceSnapshotDto._fromData(Object? value, {required bool detail}) {
    final data = _shape.map(value);
    _validateRequiredStrings(data, const <String>[
      'id',
      'name',
      'device_type',
      'public_ip',
      'private_ip',
      'interface',
      'esim_transport',
      'local_phone',
      'phone_number_source',
      'registration_state_label',
      'lifecycle_reason',
    ]);
    _validateRequiredBools(data, const <String>[
      'running',
      'healthy',
      'control_online',
      'physical_present',
      'worker_running',
      'data_connected',
      'radio_registered',
      'sms_enabled',
      'network_enabled',
      'developer_enabled',
      'network_connected',
      'vowifi_enabled',
      'vowifi_active',
      'flight_mode',
    ]);
    _shape.integralInt(data['proxy_port']);
    final esimSwitch = DeviceEsimSwitchDto._fromData(data['esim_switch']);
    final smsStorage = _parseSmsStorage(data['sms_storage']);
    if (detail) {
      _validateRequiredStrings(data, const <String>[
        'at_port',
        'audio_device',
        'backend_mode',
        'control_device',
      ]);
      _shape.boolean(data['radio_live_ok']);
    }
    final id = _shape.nonEmptyString(data['id']);
    final modemResult = _parseModem(data['modem']);
    final runtimeResult = _parseRuntime(data['vowifi_runtime'], id);
    final topLevelPhoneDisplay = _maskIdentity(data['local_phone']);
    final topLevelPhoneReveal = _plainIdentity(data['local_phone']);
    final reason = _shape.string(data['lifecycle_reason']);
    final radioLive = detail
        ? _shape.boolean(data['radio_live_ok'])
        : _optionalBool(data, 'radio_live_ok');

    return DeviceSnapshotDto._(
      id: id,
      name: _shape.string(data['name']),
      type: _parseDeviceType(data['device_type']),
      healthy: _shape.boolean(data['healthy']),
      physicalPresent: _shape.boolean(data['physical_present']),
      controlOnline: _shape.boolean(data['control_online']),
      radioLive: radioLive,
      radioRegistered: _shape.boolean(data['radio_registered']),
      lifecyclePhase: _parseLifecyclePhase(data['lifecycle_phase']),
      lifecycleReasonCategory: reason.isEmpty
          ? DeviceReasonCategory.none
          : DeviceReasonCategory.reported,
      networkEnabled: _shape.boolean(data['network_enabled']),
      networkConnected: _shape.boolean(data['network_connected']),
      vowifiEnabled: _shape.boolean(data['vowifi_enabled']),
      vowifiActive: _shape.boolean(data['vowifi_active']),
      smsEnabled: _shape.boolean(data['sms_enabled']),
      flightMode: _shape.boolean(data['flight_mode']),
      developerEnabled: _shape.boolean(data['developer_enabled']),
      modem: modemResult.dto,
      identities: DeviceIdentityDisplaysDto._(
        imeiDisplay: modemResult.imeiDisplay,
        iccidDisplay: modemResult.iccidDisplay ?? runtimeResult.iccidDisplay,
        imsiDisplay: modemResult.imsiDisplay ?? runtimeResult.imsiDisplay,
        phoneDisplay:
            topLevelPhoneDisplay ??
            modemResult.phoneDisplay ??
            runtimeResult.phoneDisplay,
        imeiReveal: modemResult.imeiReveal,
        iccidReveal: modemResult.iccidReveal ?? runtimeResult.iccidReveal,
        imsiReveal: modemResult.imsiReveal ?? runtimeResult.imsiReveal,
        phoneReveal:
            topLevelPhoneReveal ??
            modemResult.phoneReveal ??
            runtimeResult.phoneReveal,
      ),
      runtime: runtimeResult.dto,
      esimSwitch: esimSwitch,
      smsStorage: smsStorage,
    );
  }

  final String id;
  final String name;
  final DeviceType type;
  final bool healthy;
  final bool physicalPresent;
  final bool controlOnline;
  final bool? radioLive;
  final bool radioRegistered;
  final DeviceLifecyclePhase lifecyclePhase;
  final DeviceReasonCategory lifecycleReasonCategory;
  final bool networkEnabled;
  final bool networkConnected;
  final bool vowifiEnabled;
  final bool vowifiActive;
  final bool smsEnabled;
  final bool flightMode;
  final bool developerEnabled;
  final DeviceModemDto modem;
  final DeviceIdentityDisplaysDto identities;
  final DeviceRuntimeDto runtime;
  final DeviceEsimSwitchDto esimSwitch;
  final DeviceSmsStorage? smsStorage;
}

/// 网关 `esim_switch`：`{active, step, status, steps:[{key,ready,pending,failed}]}`。
/// 对齐 WEB `normalizeEsimSwitchProgress`：按 key 对位、缺项当 pending，
/// 不因为多一步或少一步就整台设备解析失败。
final class DeviceEsimSwitchDto {
  const DeviceEsimSwitchDto._({required this.active, required this.stages});

  factory DeviceEsimSwitchDto._fromData(Object? value) {
    final data = _shape.map(value);
    final active = data['active'] == true;
    final stepList = data['steps'];
    final steps = stepList is List<Object?> ? stepList : const <Object?>[];
    final byKey = <String, Map<Object?, Object?>>{};
    for (final step in steps) {
      if (step is Map<Object?, Object?> && step['key'] is String) {
        byKey[step['key'] as String] = step;
      }
    }
    final stages = <DeviceSwitchStageState>[
      for (final step in DeviceSwitchStep.values)
        _stageState(byKey[step.name] ?? const <Object?, Object?>{}),
    ];
    return DeviceEsimSwitchDto._(active: active, stages: stages);
  }

  static DeviceSwitchStageState _stageState(Map<Object?, Object?> step) {
    if (step['failed'] == true) return DeviceSwitchStageState.failed;
    if (step['ready'] == true) return DeviceSwitchStageState.ready;
    if (step['pending'] == true) return DeviceSwitchStageState.running;
    return DeviceSwitchStageState.pending;
  }

  final bool active;
  final List<DeviceSwitchStageState> stages;
}

final class DeviceModemDto {
  const DeviceModemDto._({
    required this.operatorName,
    required this.servingOperator,
    required this.model,
    required this.firmware,
    required this.networkMode,
    required this.radioBand,
    required this.signalDbm,
    required this.signalRsrp,
    required this.signalRsrq,
    required this.signalSinr,
    required this.simPresent,
    required this.serviceBlocked,
    required this.blockedCategory,
    required this.regStatus,
    required this.regStatusText,
  });

  final String operatorName;
  final String servingOperator;
  final String model;
  final String? firmware;
  final String networkMode;
  final String radioBand;
  final int signalDbm;
  final int? signalRsrp;
  final int? signalRsrq;
  final int signalSinr;
  final bool simPresent;
  final bool serviceBlocked;
  final DeviceBlockedCategory blockedCategory;
  final int regStatus;
  final String regStatusText;
}

final class DeviceIdentityDisplaysDto {
  const DeviceIdentityDisplaysDto._({
    required this.imeiDisplay,
    required this.iccidDisplay,
    required this.imsiDisplay,
    required this.phoneDisplay,
    required this.imeiReveal,
    required this.iccidReveal,
    required this.imsiReveal,
    required this.phoneReveal,
  });

  final String? imeiDisplay;
  final String? iccidDisplay;
  final String? imsiDisplay;
  final String? phoneDisplay;
  final String? imeiReveal;
  final String? iccidReveal;
  final String? imsiReveal;
  final String? phoneReveal;
}

final class DeviceRuntimeDto {
  const DeviceRuntimeDto._({
    required this.phase,
    required this.simReady,
    required this.accessReady,
    required this.tunnelReady,
    required this.imsReady,
    required this.smsReady,
    required this.dataPlane,
    required this.lastReason,
    required this.errorCategory,
  });

  final DeviceRuntimePhase phase;
  final bool simReady;
  final bool accessReady;
  final bool tunnelReady;
  final bool imsReady;
  final bool smsReady;
  final String dataPlane;
  final String lastReason;
  final String errorCategory;
}

final class DeviceTrafficDto {
  const DeviceTrafficDto._({
    required this.available,
    required this.rxBytes,
    required this.txBytes,
    required this.rxRateBytesPerSecond,
    required this.txRateBytesPerSecond,
    required this.status,
  });

  const DeviceTrafficDto._unavailable()
    : available = false,
      rxBytes = null,
      txBytes = null,
      rxRateBytesPerSecond = null,
      txRateBytesPerSecond = null,
      status = DeviceTrafficStatus.unavailable;

  factory DeviceTrafficDto._fromDetailData(Map<Object?, Object?> data) {
    final formattedPresent = data.containsKey('traffic');
    final rawPresent = data.containsKey('traffic_raw');
    final metaPresent = data.containsKey('traffic_meta');
    final formatted = formattedPresent ? _shape.map(data['traffic']) : null;
    final raw = rawPresent ? _shape.map(data['traffic_raw']) : null;
    final meta = metaPresent ? _shape.map(data['traffic_meta']) : null;
    if (formatted != null && formatted.isNotEmpty) {
      _validateRequiredStrings(formatted, const <String>[
        'rx',
        'tx',
        'rate',
        'rate_tx',
      ]);
    }
    int? rxBytes;
    int? txBytes;
    int? rxRateBytesPerSecond;
    int? txRateBytesPerSecond;
    if (raw != null && raw.isNotEmpty) {
      rxBytes = _shape.nonNegativeIntegralInt(raw['rx']);
      txBytes = _shape.nonNegativeIntegralInt(raw['tx']);
      rxRateBytesPerSecond = _shape.nonNegativeIntegralInt(raw['rate']);
      txRateBytesPerSecond = _shape.nonNegativeIntegralInt(raw['rate_tx']);
    }
    DeviceTrafficStatus? status;
    if (meta != null && meta.isNotEmpty) {
      status = _parseTrafficStatus(meta['status']);
    }
    if (formatted == null || raw == null || meta == null) {
      return const DeviceTrafficDto._unavailable();
    }
    if (formatted.isEmpty || raw.isEmpty || meta.isEmpty) {
      return const DeviceTrafficDto._unavailable();
    }
    return DeviceTrafficDto._(
      available: true,
      rxBytes: rxBytes!,
      txBytes: txBytes!,
      rxRateBytesPerSecond: rxRateBytesPerSecond!,
      txRateBytesPerSecond: txRateBytesPerSecond!,
      status: status!,
    );
  }

  final bool available;
  final int? rxBytes;
  final int? txBytes;
  final int? rxRateBytesPerSecond;
  final int? txRateBytesPerSecond;
  final DeviceTrafficStatus status;
}

final class DeviceDtoException implements DtoShapeException {
  const DeviceDtoException();
}

const _shape = JsonShape(DeviceDtoException.new);

typedef _ParsedModem = ({
  DeviceModemDto dto,
  String? imeiDisplay,
  String? iccidDisplay,
  String? imsiDisplay,
  String? phoneDisplay,
  String? imeiReveal,
  String? iccidReveal,
  String? imsiReveal,
  String? phoneReveal,
});

typedef _ParsedRuntime = ({
  DeviceRuntimeDto dto,
  String? iccidDisplay,
  String? imsiDisplay,
  String? phoneDisplay,
  String? iccidReveal,
  String? imsiReveal,
  String? phoneReveal,
});

/// 对齐 WEB `resolveOperatorFromModem` 的卡归属回退链：`native_spn` →
/// `operator` → `home_carrier_name` → PLMN。正在服务的小区走单独的
/// `servingOperator`（只吃 `modem.operator`），不要合成进「原运营商」。
String _resolveOperatorName(
  Map<Object?, Object?> data, {
  required bool simInserted,
}) {
  for (final key in const <String>[
    'native_spn',
    'operator',
    'home_carrier_name',
  ]) {
    final candidate = _shape.string(data[key]).trim();
    if (candidate.isNotEmpty) return candidate;
  }
  final mcc = _shape.string(data['native_mcc']).trim();
  final mnc = _shape.string(data['native_mnc']).trim();
  if (mcc.isNotEmpty && mnc.isNotEmpty) return '$mcc$mnc';
  return simInserted ? '' : '未插 SIM';
}

_ParsedModem _parseModem(Object? value) {
  final data = _shape.map(value);
  _validateRequiredStrings(data, const <String>[
    'operator',
    'native_mcc',
    'native_mnc',
    'native_spn',
    'operator_country_code',
    'card_mcc',
    'card_mnc',
    'card_country',
    'home_carrier_name',
    'home_carrier_plmn',
    'home_carrier_country_code',
    'blocked_reason',
    'network_mode',
    'radio_band',
    'reg_status_text',
    'phone_number_source',
    'model',
    'imei',
    'iccid',
    'phone_number',
  ]);
  _validateRequiredBools(data, const <String>[
    'service_blocked',
    'sim_inserted',
  ]);
  _validateRequiredInts(data, const <String>[
    'radio_channel',
    'signal_dbm',
    'signal_sinr',
    'reg_status',
  ]);
  _optionalString(data, 'network_duplex');
  _optionalString(data, 'firmware');
  _optionalString(data, 'imsi');
  _optionalIntegralInt(data, 'signal_rsrp');
  _optionalIntegralInt(data, 'signal_rsrq');
  _optionalBool(data, 'ps_attached');
  _optionalIntegralInt(data, 'operating_mode');
  final blockedReason = _shape.string(data['blocked_reason']);
  final simInserted = _shape.boolean(data['sim_inserted']);
  return (
    dto: DeviceModemDto._(
      operatorName: _resolveOperatorName(data, simInserted: simInserted),
      servingOperator: _shape.string(data['operator']).trim(),
      model: _shape.string(data['model']),
      firmware: _optionalString(data, 'firmware'),
      networkMode: _shape.string(data['network_mode']),
      radioBand: _shape.string(data['radio_band']),
      signalDbm: _shape.integralInt(data['signal_dbm']),
      signalRsrp: _optionalIntegralInt(data, 'signal_rsrp'),
      signalRsrq: _optionalIntegralInt(data, 'signal_rsrq'),
      signalSinr: _shape.integralInt(data['signal_sinr']),
      simPresent: _shape.boolean(data['sim_inserted']),
      serviceBlocked: _shape.boolean(data['service_blocked']),
      blockedCategory: blockedReason.isEmpty
          ? DeviceBlockedCategory.none
          : DeviceBlockedCategory.reported,
      regStatus: _shape.integralInt(data['reg_status']),
      regStatusText: _shape.string(data['reg_status_text']),
    ),
    imeiDisplay: _maskIdentity(data['imei']),
    iccidDisplay: _maskIdentity(data['iccid']),
    imsiDisplay: _optionalMaskedIdentity(data, 'imsi'),
    phoneDisplay: _maskIdentity(data['phone_number']),
    imeiReveal: _plainIdentity(data['imei']),
    iccidReveal: _plainIdentity(data['iccid']),
    imsiReveal: _optionalPlainIdentity(data, 'imsi'),
    phoneReveal: _plainIdentity(data['phone_number']),
  );
}

_ParsedRuntime _parseRuntime(Object? value, String expectedDeviceId) {
  final data = _shape.map(value);
  _validateRequiredStrings(data, const <String>[
    'device_id',
    'phase',
    'dataplane_mode',
    'iccid',
    'imsi',
    'reg_status_text',
    'network_mode',
    'local_phone',
    'phone_number_source',
    'last_error_class',
    'last_error',
    'last_reason',
    'updated_at',
  ]);
  _validateRequiredBools(data, const <String>[
    'enabled',
    'active',
    'sim_ready',
    'access_ready',
    'tunnel_ready',
    'ims_ready',
    'sms_ready',
  ]);
  _shape.integralInt(data['reg_status']);
  _optionalNullableString(data, 'carrier_profile_from');
  if (_shape.string(data['device_id']) != expectedDeviceId) {
    throw const DeviceDtoException();
  }
  return (
    dto: DeviceRuntimeDto._(
      phase: _parseRuntimePhase(data['phase']),
      simReady: _shape.boolean(data['sim_ready']),
      accessReady: _shape.boolean(data['access_ready']),
      tunnelReady: _shape.boolean(data['tunnel_ready']),
      imsReady: _shape.boolean(data['ims_ready']),
      smsReady: _shape.boolean(data['sms_ready']),
      dataPlane: _shape.string(data['dataplane_mode']).trim(),
      lastReason: _shape.string(data['last_reason']).trim(),
      errorCategory: _shape.string(data['last_error_class']).trim(),
    ),
    iccidDisplay: _maskIdentity(data['iccid']),
    imsiDisplay: _maskIdentity(data['imsi']),
    phoneDisplay: _maskIdentity(data['local_phone']),
    iccidReveal: _plainIdentity(data['iccid']),
    imsiReveal: _plainIdentity(data['imsi']),
    phoneReveal: _plainIdentity(data['local_phone']),
  );
}

String? _optionalString(Map<Object?, Object?> data, String key) {
  if (!data.containsKey(key)) return null;
  return _shape.string(data[key]);
}

String? _optionalNullableString(Map<Object?, Object?> data, String key) {
  if (!data.containsKey(key) || data[key] == null) return null;
  return _shape.string(data[key]);
}

bool? _optionalBool(Map<Object?, Object?> data, String key) {
  if (!data.containsKey(key)) return null;
  return _shape.boolean(data[key]);
}

int? _optionalIntegralInt(Map<Object?, Object?> data, String key) {
  if (!data.containsKey(key)) return null;
  return _shape.integralInt(data[key]);
}

void _validateRequiredStrings(Map<Object?, Object?> data, List<String> keys) {
  for (final key in keys) {
    _shape.string(data[key]);
  }
}

void _validateRequiredBools(Map<Object?, Object?> data, List<String> keys) {
  for (final key in keys) {
    _shape.boolean(data[key]);
  }
}

void _validateRequiredInts(Map<Object?, Object?> data, List<String> keys) {
  for (final key in keys) {
    _shape.integralInt(data[key]);
  }
}

String? _maskIdentity(Object? value) {
  final identity = _shape.string(value);
  return identity.isEmpty ? null : Redaction.maskTail4(identity);
}

String? _plainIdentity(Object? value) {
  final identity = _shape.string(value);
  return identity.isEmpty ? null : identity;
}

String? _optionalMaskedIdentity(Map<Object?, Object?> data, String key) {
  if (!data.containsKey(key)) return null;
  return _maskIdentity(data[key]);
}

String? _optionalPlainIdentity(Map<Object?, Object?> data, String key) {
  if (!data.containsKey(key)) return null;
  return _plainIdentity(data[key]);
}

DeviceType _parseDeviceType(Object? value) {
  return switch (_shape.string(value)) {
    'wifi_410' => DeviceType.wifi410,
    'dji_4g' => DeviceType.dji4g,
    'pcie_ec20_ec25' => DeviceType.pcieEc20Ec25,
    'usb_sim_reader' => DeviceType.usbSimReader,
    _ => throw const DeviceDtoException(),
  };
}

DeviceLifecyclePhase _parseLifecyclePhase(Object? value) {
  return switch (_shape.string(value)) {
    'missing' => DeviceLifecyclePhase.missing,
    'degraded' => DeviceLifecyclePhase.degraded,
    'discovered' => DeviceLifecyclePhase.discovered,
    'ready' => DeviceLifecyclePhase.ready,
    'unresponsive' => DeviceLifecyclePhase.unresponsive,
    _ => throw const DeviceDtoException(),
  };
}

DeviceRuntimePhase _parseRuntimePhase(Object? value) {
  return switch (_shape.string(value)) {
    'idle' => DeviceRuntimePhase.idle,
    'sim_ready' => DeviceRuntimePhase.simReady,
    'access_ready' => DeviceRuntimePhase.accessReady,
    'tunnel_ready' => DeviceRuntimePhase.tunnelReady,
    'ims_ready' => DeviceRuntimePhase.imsReady,
    'sms_ready' => DeviceRuntimePhase.smsReady,
    'failed' => DeviceRuntimePhase.failed,
    'stopping' => DeviceRuntimePhase.stopping,
    _ => throw const DeviceDtoException(),
  };
}

DeviceTrafficStatus _parseTrafficStatus(Object? value) {
  return switch (_shape.string(value)) {
    '' => DeviceTrafficStatus.ready,
    'waiting_sample' => DeviceTrafficStatus.waitingSample,
    'stale' => DeviceTrafficStatus.stale,
    _ => throw const DeviceDtoException(),
  };
}

DeviceSmsStorage? _parseSmsStorage(Object? value) {
  if (value == null) return null;
  try {
    final map = _shape.map(value);
    DeviceSmsMailbox box(Object? mailboxData) {
      if (mailboxData == null) return const DeviceSmsMailbox();
      final m = _shape.map(mailboxData);
      return DeviceSmsMailbox(
        used: _shape.nonNegativeIntegralInt(m['used'] ?? 0),
        total: _shape.nonNegativeIntegralInt(m['total'] ?? 0),
      );
    }

    return DeviceSmsStorage(sm: box(map['sm']), me: box(map['me']));
  } catch (_) {
    return null;
  }
}

// Device discovery DTOs

final class DiscoveredDeviceDto {
  const DiscoveredDeviceDto._({
    required this.hardwareKind,
    required this.readerName,
    required this.deviceType,
    required this.discoveryKey,
    required this.controlPath,
    required this.netInterface,
    required this.usbPath,
    required this.vendorId,
    required this.productId,
    required this.driverName,
    required this.atPorts,
    required this.atPort,
    required this.imei,
    required this.mode,
    required this.networkCapable,
    required this.configured,
    required this.configuredId,
    required this.degraded,
    required this.discoveryIssue,
  });

  factory DiscoveredDeviceDto._fromData(Object? value) {
    final data = _shape.map(value);
    return DiscoveredDeviceDto._(
      hardwareKind: _shape.string(data['hardware_kind']),
      readerName: _shape.string(data['reader_name']),
      deviceType: _shape.string(data['device_type']),
      discoveryKey: _shape.string(data['discovery_key']),
      controlPath: _shape.string(data['control_path']),
      netInterface: _shape.string(data['net_interface']),
      usbPath: _shape.string(data['usb_path']),
      vendorId: _shape.integralInt(data['vendor_id']),
      productId: _shape.integralInt(data['product_id']),
      driverName: _shape.string(data['driver_name']),
      atPorts: _shape.list(data['at_ports'])
          .map((item) => _shape.string(item))
          .toList(growable: false),
      atPort: _shape.string(data['at_port']),
      imei: _shape.string(data['imei']),
      mode: _shape.string(data['mode']),
      networkCapable: _shape.boolean(data['network_capable']),
      configured: _shape.boolean(data['configured']),
      configuredId: _shape.string(data['configured_id']),
      degraded: _shape.boolean(data['degraded']),
      discoveryIssue: _shape.string(data['discovery_issue']),
    );
  }

  final String hardwareKind;
  final String readerName;
  final String deviceType;
  final String discoveryKey;
  final String controlPath;
  final String netInterface;
  final String usbPath;
  final int vendorId;
  final int productId;
  final String driverName;
  final List<String> atPorts;
  final String atPort;
  final String imei;
  final String mode;
  final bool networkCapable;
  final bool configured;
  final String configuredId;
  final bool degraded;
  final String discoveryIssue;
}

final class DiscoveredDevicesDto {
  DiscoveredDevicesDto._({
    required List<DiscoveredDeviceDto> devices,
    required this.unsupported,
  }) : devices = List<DiscoveredDeviceDto>.unmodifiable(devices);

  factory DiscoveredDevicesDto.fromData(Object? value) {
    final data = _shape.map(value);
    final devices = _shape
        .list(data['devices'])
        .map((item) => DiscoveredDeviceDto._fromData(item))
        .toList(growable: false);
    final unsupportedRaw = data['unsupported'];
    final unsupported =
        unsupportedRaw == null ? false : _shape.boolean(unsupportedRaw);
    return DiscoveredDevicesDto._(
      devices: devices,
      unsupported: unsupported,
    );
  }

  final List<DiscoveredDeviceDto> devices;
  final bool unsupported;
}

final class DeviceRescanResultDto {
  const DeviceRescanResultDto._({
    required this.status,
    required this.devicesCount,
  });

  factory DeviceRescanResultDto.fromData(Object? value) {
    final data = _shape.map(value);
    return DeviceRescanResultDto._(
      status: _shape.string(data['status']),
      devicesCount: _shape.nonNegativeIntegralInt(data['devices']),
    );
  }

  final String status;
  final int devicesCount;
}
