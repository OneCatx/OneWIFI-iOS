import '../../../core/http/json_shape.dart';
import '../domain/overview.dart';

final class HostOverviewDto {
  const HostOverviewDto._({
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

  factory HostOverviewDto.fromData(Object? value) {
    final data = _shape.map(value);
    final host = _shape.map(data['host']);
    final perf = _shape.map(data['perf']);
    final cpuModel = _shape.string(host['cpu_model']);
    final boardModel = _shape.string(host['board_model']);
    _shape.string(host['memory_model']);
    _shape.string(host['disk_model']);
    return HostOverviewDto._(
      cpuModel: cpuModel,
      boardModel: boardModel,
      cpuPercent: _requirePercentage(perf['cpu_percent']),
      memoryPercent: _requirePercentage(perf['memory_percent']),
      memoryUsedBytes: _shape.nonNegativeInt(perf['memory_used_bytes']),
      memoryTotalBytes: _shape.nonNegativeInt(perf['memory_total_bytes']),
      diskPercent: _requirePercentage(perf['disk_percent']),
      diskUsedBytes: _shape.nonNegativeInt(perf['disk_used_bytes']),
      diskTotalBytes: _shape.nonNegativeInt(perf['disk_total_bytes']),
      netRxBps: _requireNonNegativeDouble(perf['net_rx_bps']),
      netTxBps: _requireNonNegativeDouble(perf['net_tx_bps']),
    );
  }

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

  HostOverview toDomain() => HostOverview(
    cpuModel: cpuModel,
    boardModel: boardModel,
    cpuPercent: cpuPercent,
    memoryPercent: memoryPercent,
    memoryUsedBytes: memoryUsedBytes,
    memoryTotalBytes: memoryTotalBytes,
    diskPercent: diskPercent,
    diskUsedBytes: diskUsedBytes,
    diskTotalBytes: diskTotalBytes,
    netRxBps: netRxBps,
    netTxBps: netTxBps,
  );
}

final class DeviceRuntimeOverviewDto {
  const DeviceRuntimeOverviewDto._({
    required this.phase,
    required this.simReady,
    required this.accessReady,
    required this.tunnelReady,
    required this.imsReady,
    required this.smsReady,
  });

  factory DeviceRuntimeOverviewDto.fromData(Object? value) {
    final data = _shape.map(value);
    _shape.string(data['device_id']);
    final phase = _parsePhase(data['phase']);
    _shape.boolean(data['enabled']);
    _shape.boolean(data['active']);
    _shape.string(data['dataplane_mode']);
    _shape.string(data['iccid']);
    _shape.string(data['imsi']);
    final simReady = _shape.boolean(data['sim_ready']);
    final accessReady = _shape.boolean(data['access_ready']);
    final tunnelReady = _shape.boolean(data['tunnel_ready']);
    final imsReady = _shape.boolean(data['ims_ready']);
    final smsReady = _shape.boolean(data['sms_ready']);
    _shape.integer(data['reg_status']);
    _shape.string(data['reg_status_text']);
    _shape.string(data['network_mode']);
    _shape.string(data['local_phone']);
    _shape.string(data['phone_number_source']);
    _shape.string(data['last_error_class']);
    _shape.string(data['last_error']);
    _shape.string(data['last_reason']);
    _shape.string(data['updated_at']);
    return DeviceRuntimeOverviewDto._(
      phase: phase,
      simReady: simReady,
      accessReady: accessReady,
      tunnelReady: tunnelReady,
      imsReady: imsReady,
      smsReady: smsReady,
    );
  }

  final DeviceRuntimePhase phase;
  final bool simReady;
  final bool accessReady;
  final bool tunnelReady;
  final bool imsReady;
  final bool smsReady;

  DeviceRuntimeOverview toDomain() => DeviceRuntimeOverview(
    phase: phase,
    simReady: simReady,
    accessReady: accessReady,
    tunnelReady: tunnelReady,
    imsReady: imsReady,
    smsReady: smsReady,
  );
}

final class DeviceOverviewDto {
  const DeviceOverviewDto._({
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

  factory DeviceOverviewDto.fromData(Object? value) {
    final data = _shape.map(value);
    final id = _shape.string(data['id']);
    final name = _shape.string(data['name']);
    final type = _shape.string(data['device_type']);
    _shape.string(data['interface']);
    _shape.integer(data['proxy_port']);
    _shape.string(data['public_ip']);
    final healthy = _shape.boolean(data['healthy']);
    final operatorName = _shape.string(data['operator']);
    final signalDbm = _shape.integer(data['signal_dbm']);
    final networkMode = _shape.string(data['network_mode']);
    _shape.string(data['network_duplex']);
    final vowifiActive = _shape.boolean(data['vowifi_active']);
    final runtime = DeviceRuntimeOverviewDto.fromData(data['vowifi_runtime']);
    final networkConnected = _shape.boolean(data['network_connected']);
    final model = _shape.string(data['model']);
    return DeviceOverviewDto._(
      id: id,
      name: name,
      model: model,
      type: type,
      healthy: healthy,
      operatorName: operatorName,
      signalDbm: signalDbm,
      networkMode: networkMode,
      vowifiActive: vowifiActive,
      networkConnected: networkConnected,
      runtime: runtime,
    );
  }

  static List<DeviceOverviewDto> listFromData(Object? value) {
    if (value is! List<Object?>) throw const OverviewDtoException();
    return value.map(DeviceOverviewDto.fromData).toList(growable: false);
  }

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
  final DeviceRuntimeOverviewDto runtime;

  DeviceOverview toDomain() => DeviceOverview(
    id: id,
    name: name,
    model: model,
    type: type,
    healthy: healthy,
    operatorName: operatorName,
    signalDbm: signalDbm,
    networkMode: networkMode,
    vowifiActive: vowifiActive,
    networkConnected: networkConnected,
    runtime: runtime.toDomain(),
  );
}

final class OverviewDtoException implements DtoShapeException {
  const OverviewDtoException();
}

const _shape = JsonShape(OverviewDtoException.new);

double _requireNonNegativeDouble(Object? value) {
  if (value is! num) {
    throw const OverviewDtoException();
  }
  final parsed = value.toDouble();
  if (!parsed.isFinite || parsed < 0) throw const OverviewDtoException();
  return parsed;
}

double _requirePercentage(Object? value) {
  final parsed = _requireNonNegativeDouble(value);
  if (parsed > 100) throw const OverviewDtoException();
  return parsed;
}

DeviceRuntimePhase _parsePhase(Object? value) {
  return switch (_shape.string(value)) {
    'idle' => DeviceRuntimePhase.idle,
    'sim_ready' => DeviceRuntimePhase.simReady,
    'access_ready' => DeviceRuntimePhase.accessReady,
    'tunnel_ready' => DeviceRuntimePhase.tunnelReady,
    'ims_ready' => DeviceRuntimePhase.imsReady,
    'sms_ready' => DeviceRuntimePhase.smsReady,
    'failed' => DeviceRuntimePhase.failed,
    'stopping' => DeviceRuntimePhase.stopping,
    _ => throw const OverviewDtoException(),
  };
}
