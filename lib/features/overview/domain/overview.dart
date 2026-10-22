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

final class HostOverview {
  const HostOverview({
    required this.cpuModel,
    required this.boardModel,
    required this.cpuPercent,
    required this.memoryPercent,
    required this.memoryUsedBytes,
    required this.memoryTotalBytes,
    required this.diskPercent,
    required this.diskUsedBytes,
    required this.diskTotalBytes,
    required this.netRxBps,
    required this.netTxBps,
  });

  final String cpuModel;
  final String boardModel;
  final double cpuPercent;
  final double memoryPercent;
  final int memoryUsedBytes;
  final int memoryTotalBytes;
  final double diskPercent;
  final int diskUsedBytes;
  final int diskTotalBytes;
  final double netRxBps;
  final double netTxBps;

  bool get hasMeaningfulContent =>
      cpuModel.isNotEmpty ||
      boardModel.isNotEmpty ||
      cpuPercent != 0 ||
      memoryPercent != 0 ||
      memoryUsedBytes != 0 ||
      memoryTotalBytes != 0 ||
      diskPercent != 0 ||
      diskUsedBytes != 0 ||
      diskTotalBytes != 0 ||
      netRxBps != 0 ||
      netTxBps != 0;
}

final class DeviceRuntimeOverview {
  const DeviceRuntimeOverview({
    required this.phase,
    required this.simReady,
    required this.accessReady,
    required this.tunnelReady,
    required this.imsReady,
    required this.smsReady,
  });

  final DeviceRuntimePhase phase;
  final bool simReady;
  final bool accessReady;
  final bool tunnelReady;
  final bool imsReady;
  final bool smsReady;
}

final class DeviceOverview {
  const DeviceOverview({
    required this.id,
    required this.name,
    required this.model,
    required this.type,
    required this.healthy,
    required this.operatorName,
    required this.signalDbm,
    required this.networkMode,
    required this.vowifiActive,
    required this.networkConnected,
    required this.runtime,
  });

  final String id;
  final String name;
  final String model;
  final String type;
  final bool healthy;
  final String operatorName;
  final int signalDbm;
  final String networkMode;
  final bool vowifiActive;
  final bool networkConnected;
  final DeviceRuntimeOverview runtime;
}
