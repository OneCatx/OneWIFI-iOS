import 'package:flutter/foundation.dart';

import '../../../core/http/http_transport.dart';
import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../data/device_repository.dart';
import '../domain/device.dart';

final class DeviceDetailController extends RequestNotifier {
  factory DeviceDetailController({
    required String deviceId,
    required DeviceRepository repository,
    required RequestRegistry requestRegistry,
  }) => DeviceDetailController._(deviceId, repository, requestRegistry);

  DeviceDetailController._(
    this.deviceId,
    this._repository,
    RequestRegistry requestRegistry,
  ) : _read = RequestSlot(requestRegistry, 'devices.detail:$deviceId'),
      _actionRun = RequestSlot(requestRegistry, 'devices.action:$deviceId'),
      _state = QueryState.initial(key: 'devices.detail:$deviceId');

  final String deviceId;
  final DeviceRepository _repository;
  final RequestSlot _read;
  final RequestSlot _actionRun;
  QueryState<DeviceDetail> _state;
  ActionState _action = const ActionState.idle();
  bool _automaticPollInFlight = false;

  QueryState<DeviceDetail> get state => _state;
  ActionState get action => _action;

  @override
  List<RequestSlot> get slots => <RequestSlot>[_read, _actionRun];

  Future<void> load() => _request();

  Future<void> refresh() => _request();

  /// 切卡期间的静默轮询：不切到 refreshing、不把瞬时失败刷成失败态，
  /// 只在拿到新快照时替换数据。没有旧数据时退回普通请求。
  Future<void> poll({bool automatic = false}) async {
    // Timer ticks must not supersede a slow poll or an explicit refresh.
    // Explicit poll callers retain the existing latest-read-wins contract.
    if (automatic && (_read.isActive || _automaticPollInFlight)) return;
    if (automatic) _automaticPollInFlight = true;
    try {
      await _request(silent: _state.lastGoodData != null);
    } finally {
      if (automatic) _automaticPollInFlight = false;
    }
  }

  Future<void> setCapability(DeviceCapability capability, bool enabled) {
    return _runAction(
      'devices.capability:$deviceId:${capability.name}',
      (cancellation) => _repository.setCapability(
        deviceId: deviceId,
        capability: capability,
        enabled: enabled,
        cancellation: cancellation,
      ),
      onAccepted: () => _applyCapability(capability, enabled),
    );
  }

  Future<void> reconnectVowifi() {
    return _runAction(
      'devices.vowifi-reconnect:$deviceId',
      (cancellation) =>
          _repository.reconnectVowifi(deviceId, cancellation: cancellation),
    );
  }

  Future<void> reboot() {
    return _runAction(
      'devices.reboot:$deviceId',
      (cancellation) =>
          _repository.reboot(deviceId, cancellation: cancellation),
    );
  }

  Future<void> _request({bool silent = false}) => runQuery<DeviceDetail>(
    slot: _read,
    current: () => _state,
    set: _setState,
    fetch: (ticket) => _repository.fetchDeviceOverview(
      deviceId,
      cancellation: ticket.cancellation,
    ),
    silent: silent,
  );

  void _setState(QueryState<DeviceDetail> next) => publish(() => _state = next);

  void _setAction(ActionState next) => publish(() => _action = next);

  void _applyCapability(DeviceCapability capability, bool enabled) {
    final current = _state.lastGoodData;
    if (current == null) return;
    final device = switch (capability) {
      DeviceCapability.network => current.device.copyWith(
        networkEnabled: enabled,
      ),
      DeviceCapability.vowifi => current.device.copyWith(
        vowifiEnabled: enabled,
      ),
      DeviceCapability.flightMode => current.device.copyWith(
        flightMode: enabled,
      ),
    };
    _setState(
      QueryState.data(
        data: DeviceDetail(device: device, traffic: current.traffic),
        key: _read.key,
      ),
    );
  }

  Future<void> _runAction(
    String key,
    Future<void> Function(RequestCancellation cancellation) body, {
    VoidCallback? onAccepted,
  }) async {
    final ok = await runAction<void>(
      slot: _actionRun,
      key: key,
      current: () => _action,
      set: _setAction,
      submitting: ActionState.submitting(operationId: key),
      request: (ticket) => body(ticket.cancellation),
      onSuccess: (_, _) {
        onAccepted?.call();
        return const ActionState.succeeded();
      },
    );
    if (ok) await _request();
  }
}
