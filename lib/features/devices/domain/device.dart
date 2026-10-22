enum DeviceType { wifi410, dji4g, pcieEc20Ec25, usbSimReader }

enum DeviceLifecyclePhase { missing, degraded, discovered, ready, unresponsive }

enum DeviceRuntimePhase {
  idle,
  simReady,
  accessReady,
  tunnelReady,
  imsReady,
  smsReady,
  failed,
  stopping,
}

enum DeviceReasonCategory { none, reported }

enum DeviceBlockedCategory { none, reported }

enum DeviceTrafficStatus { unavailable, ready, waitingSample, stale }

/// 网关切卡的五个步骤，顺序与后端 `esimSwitchStepDefs` / WEB `ESIM_SWITCH_STEPS` 一致。
enum DeviceSwitchStep { stop, flight, write, check, back }

enum DeviceSwitchStageState { pending, running, ready, failed }


final class DeviceSmsMailbox {
  const DeviceSmsMailbox({this.used = 0, this.total = 0});
  final int used;
  final int total;
}

final class DeviceSmsStorage {
  const DeviceSmsStorage({
    this.sm = const DeviceSmsMailbox(),
    this.me = const DeviceSmsMailbox(),
  });
  final DeviceSmsMailbox sm;
  final DeviceSmsMailbox me;
}

final class DeviceFleet {
  DeviceFleet({
    required this.deviceLimit,
    required List<DeviceSnapshot> devices,
  }) : devices = List<DeviceSnapshot>.unmodifiable(devices);

  final int deviceLimit;
  final List<DeviceSnapshot> devices;
}

final class DeviceSnapshot {
  const DeviceSnapshot({
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
    this.esimSwitch = const DeviceEsimSwitch.idle(),
    this.smsStorage,
  });

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
  final DeviceModem modem;
  final DeviceIdentityDisplays identities;
  final DeviceRuntime runtime;
  final DeviceEsimSwitch esimSwitch;
  final DeviceSmsStorage? smsStorage;

  DeviceSnapshot copyWith({
    bool? networkEnabled,
    bool? networkConnected,
    bool? vowifiEnabled,
    bool? vowifiActive,
    bool? flightMode,
  }) {
    return DeviceSnapshot(
      id: id,
      name: name,
      type: type,
      healthy: healthy,
      physicalPresent: physicalPresent,
      controlOnline: controlOnline,
      radioLive: radioLive,
      radioRegistered: radioRegistered,
      lifecyclePhase: lifecyclePhase,
      lifecycleReasonCategory: lifecycleReasonCategory,
      networkEnabled: networkEnabled ?? this.networkEnabled,
      networkConnected: networkConnected ?? this.networkConnected,
      vowifiEnabled: vowifiEnabled ?? this.vowifiEnabled,
      vowifiActive: vowifiActive ?? this.vowifiActive,
      smsEnabled: smsEnabled,
      flightMode: flightMode ?? this.flightMode,
      developerEnabled: developerEnabled,
      modem: modem,
      identities: identities,
      runtime: runtime,
      esimSwitch: esimSwitch,
      smsStorage: smsStorage,
    );
  }
}

/// WEB `switchProgress`：网关 `esim_switch` 快照。空闲时五段全 pending；
/// 进行中只有当前步 running，之前的 ready；失败时当前步 failed。
final class DeviceEsimSwitch {
  const DeviceEsimSwitch({required this.active, required this.stages});

  const DeviceEsimSwitch.idle()
    : active = false,
      stages = const <DeviceSwitchStageState>[
        DeviceSwitchStageState.pending,
        DeviceSwitchStageState.pending,
        DeviceSwitchStageState.pending,
        DeviceSwitchStageState.pending,
        DeviceSwitchStageState.pending,
      ];

  final bool active;

  /// 与 [DeviceSwitchStep.values] 一一对应，长度固定为 5。
  final List<DeviceSwitchStageState> stages;
}

final class DeviceModem {
  const DeviceModem({
    required this.operatorName,
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
    this.servingOperator = '',
    this.regStatus = 0,
    this.regStatusText = '',
  });

  /// 卡归属 / SPN（WEB `operator`）。
  final String operatorName;

  /// 正在服务的小区运营商（WEB `servingOperator` ← `modem.operator`）。
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

final class DeviceIdentityDisplays {
  const DeviceIdentityDisplays({
    required this.imeiDisplay,
    required this.iccidDisplay,
    required this.imsiDisplay,
    required this.phoneDisplay,
    this.imeiReveal,
    this.iccidReveal,
    this.imsiReveal,
    this.phoneReveal,
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

final class DeviceRuntime {
  const DeviceRuntime({
    required this.phase,
    required this.simReady,
    required this.accessReady,
    required this.tunnelReady,
    required this.imsReady,
    required this.smsReady,
    this.dataPlane = '',
    this.lastReason = '',
    this.errorCategory = '',
  });

  final DeviceRuntimePhase phase;
  final bool simReady;
  final bool accessReady;
  final bool tunnelReady;
  final bool imsReady;
  final bool smsReady;

  /// WEB「详情 · 数据平面」：网关 `vowifi_runtime.dataplane_mode` 原文。
  final String dataPlane;

  /// WEB「详情 · 最后原因」：`vowifi_runtime.last_reason` 原文。
  final String lastReason;

  /// WEB「详情 · 错误分类」：`vowifi_runtime.last_error_class` 原文。
  final String errorCategory;
}

/// 放在 extension 而不是类内 getter：隐私形状守卫（device_dto_test）禁止
/// 数据类里出现计算成员，避免有人借 getter 拼出原始明文。
extension DeviceRuntimeReadiness on DeviceRuntime {
  /// WEB `wificallReady`：五段就绪链全部点亮。
  bool get allReady =>
      simReady && accessReady && tunnelReady && imsReady && smsReady;
}

/// WEB `radioServingFields`：蜂窝驻留与 VoWiFi Access 分开。
extension DeviceCellularCamping on DeviceSnapshot {
  bool get cellularCamped => radioRegistered && !flightMode;

  String get radioStatus {
    if (!radioRegistered) return '';
    final text = modem.regStatusText.toLowerCase();
    final roaming = modem.regStatus == 5 || text.contains('roaming');
    return roaming ? '漫游驻留' : '已驻留';
  }

  String get radioModeLabel {
    final parts = <String>[
      modem.networkMode.trim(),
      modem.radioBand.trim(),
    ].where((part) => part.isNotEmpty);
    return parts.join(' ');
  }

  String get radioSignalLabel {
    final rsrp = modem.signalRsrp;
    if (rsrp != null && rsrp != 0) return '$rsrp dBm';
    if (modem.signalDbm != 0) return '${modem.signalDbm} dBm';
    return '';
  }

  String get radioLabel {
    if (!radioRegistered) return '';
    return <String>[
      modem.servingOperator.trim(),
      radioModeLabel,
      radioStatus,
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  /// 驻网正文：小区 + 频段 + 信号，状态单独做牌，避免和 WiFi Call 挤成一长串。
  String get radioSummary {
    if (!radioRegistered) return '';
    return <String>[
      modem.servingOperator.trim(),
      radioModeLabel,
      radioSignalLabel,
    ].where((part) => part.isNotEmpty).join(' · ');
  }
}

final class DeviceTraffic {
  factory DeviceTraffic.available({
    required int rxBytes,
    required int txBytes,
    required int rxRateBytesPerSecond,
    required int txRateBytesPerSecond,
    required DeviceTrafficStatus status,
  }) {
    if (rxBytes < 0 ||
        txBytes < 0 ||
        rxRateBytesPerSecond < 0 ||
        txRateBytesPerSecond < 0) {
      throw ArgumentError('Traffic counters must be non-negative.');
    }
    if (status == DeviceTrafficStatus.unavailable) {
      throw ArgumentError.value(status, 'status');
    }
    return DeviceTraffic._available(
      rxBytes: rxBytes,
      txBytes: txBytes,
      rxRateBytesPerSecond: rxRateBytesPerSecond,
      txRateBytesPerSecond: txRateBytesPerSecond,
      status: status,
    );
  }

  const DeviceTraffic._available({
    required this.rxBytes,
    required this.txBytes,
    required this.rxRateBytesPerSecond,
    required this.txRateBytesPerSecond,
    required this.status,
  }) : available = true;

  const DeviceTraffic.unavailable() : this._unavailable();

  const DeviceTraffic._unavailable()
    : available = false,
      rxBytes = null,
      txBytes = null,
      rxRateBytesPerSecond = null,
      txRateBytesPerSecond = null,
      status = DeviceTrafficStatus.unavailable;

  final bool available;
  final int? rxBytes;
  final int? txBytes;
  final int? rxRateBytesPerSecond;
  final int? txRateBytesPerSecond;
  final DeviceTrafficStatus status;
}

final class DeviceDetail {
  const DeviceDetail({required this.device, required this.traffic});

  final DeviceSnapshot device;
  final DeviceTraffic traffic;
}

final class DeviceRescanResult {
  const DeviceRescanResult({
    required this.status,
    required this.devicesCount,
  });

  final String status;
  final int devicesCount;
}

final class DiscoveredDevice {
  const DiscoveredDevice({
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

  bool get isUnregistered => !configured;
  bool get hasIssues => degraded || discoveryIssue.isNotEmpty;
}
