import 'dart:async';

import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../../esim/data/esim_repository.dart';
import '../../esim/domain/euicc_hardware.dart';
import '../data/device_repository.dart';
import '../domain/device.dart';

final class DeviceListController extends RequestNotifier {
  factory DeviceListController({
    required DeviceRepository repository,
    required RequestRegistry requestRegistry,
    EuiccOverviewLoader? overviewLoader,
    Future<void> Function()? catalogSync,
  }) => DeviceListController._(
    repository,
    requestRegistry,
    overviewLoader,
    catalogSync,
  );

  DeviceListController._(
    this._repository,
    this._requestRegistry,
    this._overviewLoader,
    this._catalogSync,
  ) : _read = RequestSlot(_requestRegistry, _requestKey),
      _discoveredRead = RequestSlot(_requestRegistry, _discoveredRequestKey),
      _rescanSlot = RequestSlot(_requestRegistry, _rescanRequestKey),
      _registerSlot = RequestSlot(_requestRegistry, _registerRequestKey);

  static const String _requestKey = 'devices.list';
  static const String _discoveredRequestKey = 'devices.discovered';
  static const String _rescanRequestKey = 'devices.rescan';
  static const String _registerRequestKey = 'devices.register';
  static const String _overviewKeyPrefix = 'devices.list.euicc:';

  final DeviceRepository _repository;
  final RequestRegistry _requestRegistry;
  final EuiccOverviewLoader? _overviewLoader;
  final Future<void> Function()? _catalogSync;
  final RequestSlot _read;
  final RequestSlot _discoveredRead;
  final RequestSlot _rescanSlot;
  final RequestSlot _registerSlot;
  QueryState<DeviceFleet> _state = const QueryState.initial(key: _requestKey);
  QueryState<List<DiscoveredDevice>> _discoveredState =
      const QueryState.initial(key: _discoveredRequestKey);
  bool _isRescanning = false;
  bool _isRegistering = false;
  final Map<String, EuiccOverview> _overviews = <String, EuiccOverview>{};
  final Map<String, RequestSlot> _overviewReads = <String, RequestSlot>{};

  QueryState<DeviceFleet> get state => _state;
  QueryState<List<DiscoveredDevice>> get discoveredState => _discoveredState;
  bool get isRescanning => _isRescanning;
  bool get isRegistering => _isRegistering;

  @override
  List<RequestSlot> get slots => <RequestSlot>[
    _read,
    _discoveredRead,
    _rescanSlot,
    _registerSlot,
    ..._overviewReads.values,
  ];

  /// 每台模组的 eUICC 硬件（铭牌 / 厂商 / 容量）。与 WEB 设备卡同源：
  /// 列表拉完后逐台补读；没读到的设备不在 map 里，卡片只是不显示铭牌。
  List<EuiccHardware>? hardwareFor(String deviceId) =>
      _overviews[deviceId]?.hardware;

  /// 某台模组上、打码 ICCID 对应的 profile 名字；总览没读到或卡不在
  /// 缓存清单里返回 null，由调用方回退到 ICCID 尾号 / 设备名。
  String? cardNameFor(String deviceId, String iccidDisplay) =>
      _overviews[deviceId]?.profileNameFor(iccidDisplay);

  /// 国内实体卡的品牌铭牌。只有网关把这台标成「国内卡」时才返回，其它模组仍走 eSIM 目录。
  String brandNameplateFor(String deviceId) {
    final profiles = _overviews[deviceId]?.profiles;
    if (profiles == null) return '';
    for (final profile in profiles) {
      if (profile.provider.trim() == '国内卡') return '国内卡';
    }
    return '';
  }

  String? enabledCardNameFor(String deviceId) {
    final profiles = _overviews[deviceId]?.profiles;
    if (profiles == null) return null;
    for (final profile in profiles) {
      if (!profile.active) continue;
      final name = profile.name.trim();
      if (name.isEmpty || name == '未命名') return null;
      return name;
    }
    return null;
  }

  /// 按设备名反查 fleet 里的设备 id。短信联系人契约只带 `device_name`，
  /// 同名设备取第一台（与网关 `/api/sms/contacts` 的去重口径一致）。
  String? deviceIdNamed(String name) {
    if (name.isEmpty) return null;
    final devices = _state.lastGoodData?.devices;
    if (devices == null) return null;
    for (final device in devices) {
      if (device.name == name) return device.id;
    }
    return null;
  }

  Future<void> load() => _request();

  Future<void> refresh() => _request();

  Future<void> loadDiscoveredDevices() => _requestDiscovered();

  Future<void> rescanDevices() async {
    final ticket = _rescanSlot.begin();
    try {
      publish(() => _isRescanning = true);
      await _repository.rescanDevices(cancellation: ticket.cancellation);
      if (!ticket.isCurrent) return;
      await loadDiscoveredDevices();
    } catch (error) {
      if (!ticket.isCurrent) return;
      rethrow;
    } finally {
      ticket.end();
      publish(() => _isRescanning = false);
    }
  }

  Future<void> registerDevice({
    required String deviceId,
    required String discoveryKey,
    required String deviceType,
    String? name,
    String? simPin,
  }) async {
    final ticket = _registerSlot.begin();
    try {
      publish(() => _isRegistering = true);
      await _repository.registerDevice(
        deviceId: deviceId,
        discoveryKey: discoveryKey,
        deviceType: deviceType,
        name: name,
        simPin: simPin,
        cancellation: ticket.cancellation,
      );
      if (!ticket.isCurrent) return;
      await Future.wait([
        load(),
        loadDiscoveredDevices(),
      ]);
    } catch (error) {
      if (!ticket.isCurrent) return;
      rethrow;
    } finally {
      ticket.end();
      publish(() => _isRegistering = false);
    }
  }

  Future<void> _request() => runQuery<DeviceFleet>(
    slot: _read,
    current: () => _state,
    set: _setState,
    fetch: (ticket) =>
        _repository.fetchDevices(cancellation: ticket.cancellation),
    isEmpty: (fleet) => fleet.devices.isEmpty,
    onData: (fleet, ticket) async {
      // PERF-P4 T4: overview GETs do not depend on catalog sync (nameplates only).
      if (!ticket.isCurrent) return;
      _loadOverviews(fleet, ticket);
      final sync = _catalogSync;
      if (sync == null) return;
      try {
        await sync();
      } catch (_) {
        // 目录同步失败只影响新型号铭牌，列表本身照常。
      }
    },
  );

  Future<void> _requestDiscovered() => runQuery<List<DiscoveredDevice>>(
    slot: _discoveredRead,
    current: () => _discoveredState,
    set: _setDiscoveredState,
    fetch: (ticket) =>
        _repository.fetchDiscoveredDevices(cancellation: ticket.cancellation),
    isEmpty: (devices) => devices.isEmpty,
  );

  void _loadOverviews(DeviceFleet fleet, RequestTicket fleetTicket) {
    final loader = _overviewLoader;
    if (loader == null) return;
    final ids = fleet.devices.map((device) => device.id).toSet();
    _overviews.removeWhere((id, _) => !ids.contains(id));
    _overviewReads.removeWhere((id, slot) {
      if (ids.contains(id)) return false;
      slot.close();
      return true;
    });
    for (final device in fleet.devices) {
      unawaited(_loadOverviewFor(loader, device.id, fleetTicket));
    }
  }

  Future<void> _loadOverviewFor(
    EuiccOverviewLoader loader,
    String deviceId,
    RequestTicket fleetTicket,
  ) async {
    final slot = _overviewReads.putIfAbsent(
      deviceId,
      () => RequestSlot(_requestRegistry, '$_overviewKeyPrefix$deviceId'),
    );
    final ticket = slot.begin();
    try {
      final result = await loader(deviceId, cancellation: ticket.cancellation);
      // 总览只服务于这一版 fleet：列表又刷了一次就丢掉，等新一轮补读。
      if (!ticket.isCurrent || !fleetTicket.isCurrent) return;
      _overviews[deviceId] = result;
      notifyListeners();
    } catch (_) {
      // 总览读不到只影响铭牌 / 卡名展示，不能把整张列表判失败；保留上一次的值。
    } finally {
      ticket.end();
    }
  }

  void _setState(QueryState<DeviceFleet> next) => publish(() => _state = next);

  void _setDiscoveredState(QueryState<List<DiscoveredDevice>> next) =>
      publish(() => _discoveredState = next);

  @override
  void dispose() {
    super.dispose();
    _overviewReads.clear();
  }
}
