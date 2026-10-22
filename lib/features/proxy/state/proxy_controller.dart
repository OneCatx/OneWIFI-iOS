import 'dart:async';

import '../../../core/http/http_transport.dart';
import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../data/mihomo_backend_store.dart';
import '../data/proxy_repository.dart';
import '../domain/mihomo_backend.dart';
import '../domain/wifi_call_connection.dart';
import '../domain/wifi_call_group.dart';
import '../domain/wifi_selector_catalog.dart';

/// Manages WiFi calling proxy configuration and connection state.
///
/// This controller handles:
/// - Loading proxy groups (selector-based routing rules)
/// - Selecting proxy nodes within groups
/// - Monitoring live VoWiFi connections
/// - Latency testing (delay probing) for proxy nodes
/// - Backend configuration (Mihomo/Clash Meta integration)
///
/// The controller integrates with a Mihomo backend (if available) to provide
/// connection routing and policy selection for WiFi calling traffic.
final class ProxyController extends RequestNotifier {
  /// Creates a [ProxyController] with the specified dependencies.
  ///
  /// Parameters:
  /// - [repository]: Repository for proxy operations
  /// - [requestRegistry]: Registry for tracking and cancelling requests
  /// - [backendStore]: Optional store for Mihomo backend configuration
  /// - [clock]: Optional clock function for time-based operations
  factory ProxyController({
    required ProxyRepository repository,
    required RequestRegistry requestRegistry,
    MihomoBackendStore? backendStore,
    DateTime Function()? clock,
  }) => ProxyController._(
    repository,
    requestRegistry,
    backendStore,
    clock ?? DateTime.now,
  );

  ProxyController._(
    this._repository,
    RequestRegistry requestRegistry,
    this._backendStore,
    this._clock,
  ) : _read = RequestSlot(requestRegistry, _readKey),
      _connections = RequestSlot(requestRegistry, _connectionsKey),
      _select = RequestSlot(requestRegistry, _selectKey) {
    final store = _backendStore;
    if (store is ObservableMihomoBackendStore) {
      store.addListener(_backendChanged);
    }
  }

  static const String _readKey = 'proxy.wifi.groups';
  static const String _connectionsKey = 'proxy.wifi.connections';
  static const String _selectKey = 'proxy.wifi.select';

  final ProxyRepository _repository;
  final MihomoBackendStore? _backendStore;
  final DateTime Function() _clock;
  final RequestSlot _read;
  final RequestSlot _connections;
  final RequestSlot _select;
  QueryState<List<WifiCallGroup>> _groups = const QueryState.initial(
    key: _readKey,
  );
  QueryState<List<WifiCallConnection>> _liveConnections =
      const QueryState.initial(key: _connectionsKey);
  ActionState _selectAction = const ActionState.idle();
  String? _selectingGroup;
  var _needsConnection = false;
  var _probing = false;
  String? _queuedGroupProbe;
  MihomoBackend? _backend;
  Object _backendToken = Object();
  Object? _snapshotToken;
  RequestCancellation _probeCancellation = RequestCancellation();
  int _probeGeneration = 0;

  /// Captured by the UI when displaying a backend's snapshot; contains no secret.
  Object? get snapshotToken => _snapshotToken;

  bool isSnapshotCurrent(Object? token) =>
      token != null && identical(token, _snapshotToken) && !isDisposed;

  ProxyRepository get _boundRepository {
    final repository = _repository;
    final backend = _backend;
    return repository is DefaultProxyRepository && backend != null
        ? repository.forBackend(backend)
        : repository;
  }

  void _stopProbes() {
    _probeCancellation.cancel();
    _probeCancellation = RequestCancellation();
    _probeGeneration += 1;
    _probing = false;
    _queuedGroupProbe = null;
  }

  void _backendChanged() {
    _replaceBackend(null);
  }

  Object _replaceBackend(MihomoBackend? backend) {
    final token = Object();
    if (isDisposed) return token;
    _read.cancel();
    _connections.cancel();
    _select.cancel();
    _stopProbes();
    publish(() {
      _backendToken = token;
      _snapshotToken = null;
      _backend = backend;
      _connectionStamp = null;
      _groups = const QueryState.initial(key: _readKey);
      _liveConnections = const QueryState.initial(key: _connectionsKey);
      _selectAction = const ActionState.idle();
      _selectingGroup = null;
    });
    return token;
  }

  bool _isBackendCurrent(Object? token) =>
      !isDisposed && token != null && identical(token, _backendToken);

  Future<Object?> _syncBackend() async {
    if (isDisposed) return null;
    final store = _backendStore;
    if (store == null) return _backendToken;
    var token = _backendToken;
    final backend = await store.read();
    if (!_isBackendCurrent(token)) return null;
    if (backend?.origin != _backend?.origin ||
        backend?.secret != _backend?.secret) {
      token = _replaceBackend(backend);
    }
    if (!_isBackendCurrent(token)) return null;
    if (backend == null) {
      publish(() {
        _needsConnection = true;
        _groups = const QueryState.empty(key: _readKey);
        _liveConnections = const QueryState.empty(key: _connectionsKey);
      });
      return null;
    }
    if (_needsConnection) publish(() => _needsConnection = false);
    return token;
  }

  QueryState<List<WifiCallGroup>> get groups => _groups;
  QueryState<List<WifiCallConnection>> get connections => _liveConnections;
  ActionState get selectAction => _selectAction;
  String? get selectingGroup => _selectingGroup;
  bool get needsConnection => _needsConnection;
  bool get probing => _probing;

  @override
  List<RequestSlot> get slots => <RequestSlot>[_read, _connections, _select];

  Future<void> load() => _request(refreshConnections: true);

  Future<void> refresh() => _request(refreshConnections: true);

  Future<void> _request({required bool refreshConnections}) async {
    final token = await _syncBackend();
    if (!_isBackendCurrent(token)) return;
    final repository = _boundRepository;
    await Future.wait<void>(<Future<void>>[
      runQuery<List<WifiCallGroup>>(
        slot: _read,
        current: () => _groups,
        set: _setGroups,
        fetch: (ticket) =>
            repository.fetchWifiCallGroups(cancellation: ticket.cancellation),
        isEmpty: (groups) => groups.isEmpty,
      ),
      if (refreshConnections && _isBackendCurrent(token))
        _requestConnections(repository),
    ]);
    if (isDisposed || !identical(token, _backendToken)) return;
    await probeCurrents();
  }

  Future<void> probeCurrents({
    List<String>? countryCodes,
    Object? snapshotToken,
  }) async {
    final token = snapshotToken ?? _snapshotToken;
    if (!_isBackendCurrent(await _syncBackend()) ||
        !isSnapshotCurrent(token) ||
        _probing) {
      return;
    }
    final loaded = _groups.lastGoodData;
    if (loaded == null || loaded.isEmpty) return;
    final probe = _captureProbe();
    publish(() => _probing = true);
    try {
      final pinned = countryCodes == null
          ? WifiSelectorCatalog.pinnedOf(loaded)
          : WifiSelectorCatalog.pinnedBy(loaded, countryCodes);
      final targets = pinned.isEmpty ? loaded : pinned;
      await _probeJobs(probe, <_ProbeJob>[
        for (final group in targets) _currentProbe(group),
      ]);
    } finally {
      if (_isProbeCurrent(probe)) {
        publish(() => _probing = false);
        await _drainQueuedProbe();
      }
    }
  }

  Future<void> _requestConnections(
    ProxyRepository repository, {
    bool silent = false,
  }) {
    return runQuery<List<WifiCallConnection>>(
      slot: _connections,
      current: () => _liveConnections,
      set: _setConnections,
      silent: silent,
      fetch: (ticket) => repository.fetchConnections(
        cancellation: ticket.cancellation,
        previous: _liveConnections.lastGoodData,
        previousAt: _connectionStamp,
        now: _clock(),
      ),
      isEmpty: (rows) => rows.isEmpty,
      onData: (_, ticket) {
        if (ticket.isCurrent) _connectionStamp = _clock();
      },
    );
  }

  DateTime? _connectionStamp;

  Future<bool> selectNode({
    required String group,
    required String name,
    Object? snapshotToken,
  }) async {
    final token = snapshotToken ?? _snapshotToken;
    if (!_isBackendCurrent(await _syncBackend()) ||
        !isSnapshotCurrent(token) ||
        _selectAction.status == ActionStatus.submitting ||
        _nodeNamed(group, name) == null) {
      return false;
    }
    final repository = _boundRepository;
    _cancelGroupRead();
    if (!isSnapshotCurrent(token)) return false;
    _stopProbes();
    publish(() => _selectingGroup = group);
    if (!isSnapshotCurrent(token)) return false;
    final ok = await runAction<void>(
      slot: _select,
      current: () => _selectAction,
      set: _setSelectAction,
      request: (ticket) => repository.selectNode(
        group: group,
        name: name,
        cancellation: ticket.cancellation,
      ),
      onSuccess: (_, ticket) {
        _cancelGroupRead();
        if (!ticket.isCurrent || !isSnapshotCurrent(token)) return null;
        _stopProbes();
        final current = _groups.lastGoodData;
        if (current != null && ticket.isCurrent) {
          _setGroups(
            QueryState<List<WifiCallGroup>>.data(
              data: List<WifiCallGroup>.unmodifiable(
                current.map(
                  (item) => item.groupName == group ? item.withNow(name) : item,
                ),
              ),
              key: _readKey,
            ),
          );
        }
        return const ActionState.succeeded();
      },
    );
    if (!isSnapshotCurrent(token)) return false;
    if (_selectingGroup == group) {
      publish(() => _selectingGroup = null);
    }
    if (ok) {
      final selected = _nodeNamed(group, name);
      if (selected != null) {
        await _probeJobs(_captureProbe(), <_ProbeJob>[_nodeProbe(selected)]);
      }
    }
    return ok && isSnapshotCurrent(token);
  }

  void _cancelGroupRead() {
    _read.cancel();
    final previous = _groups.lastGoodData;
    if (previous != null) {
      _setGroups(QueryState.data(data: previous, key: _readKey));
    }
  }

  WifiCallNode? _nodeNamed(String groupName, String nodeName) {
    final groups = _groups.lastGoodData;
    if (groups == null) return null;
    for (final group in groups) {
      if (group.groupName != groupName) continue;
      for (final node in group.nodes) {
        if (node.name == nodeName || node.delayTarget == nodeName) return node;
      }
    }
    return null;
  }

  Future<void> probeGroup(String groupName, {Object? snapshotToken}) async {
    final token = snapshotToken ?? _snapshotToken;
    if (!_isBackendCurrent(await _syncBackend()) || !isSnapshotCurrent(token)) {
      return;
    }
    if (_probing) {
      _queuedGroupProbe = groupName;
      return;
    }
    final groups = _groups.lastGoodData;
    if (groups == null) return;
    WifiCallGroup? group;
    for (final item in groups) {
      if (item.groupName == groupName) {
        group = item;
        break;
      }
    }
    if (group == null) return;
    final probe = _captureProbe();
    publish(() => _probing = true);
    try {
      final delays = await probe.repository.probeGroupDelay(
        name: group.groupName,
        cancellation: probe.cancellation,
      );
      if (!_isProbeCurrent(probe)) return;
      if (delays != null) {
        await _applyDelays(probe, group.groupName, delays);
      } else {
        await _probeJobs(probe, <_ProbeJob>[
          for (final node in group.nodes) _nodeProbe(node),
        ]);
      }
    } finally {
      if (_isProbeCurrent(probe)) {
        publish(() => _probing = false);
        await _drainQueuedProbe();
      }
    }
  }

  Future<void> _drainQueuedProbe() async {
    final queued = _queuedGroupProbe;
    _queuedGroupProbe = null;
    if (queued == null || queued.isEmpty || isDisposed) return;
    await probeGroup(queued);
  }

  _ProbeJob _currentProbe(WifiCallGroup group) {
    WifiCallNode? current;
    for (final node in group.nodes) {
      if (node.name == group.now || node.delayTarget == group.now) {
        current = node;
        break;
      }
    }
    return _ProbeJob(
      applyAs: group.groupName,
      name: group.groupName,
      altName: current?.delayTarget,
    );
  }

  _ProbeJob _nodeProbe(WifiCallNode node) {
    final target = node.delayTarget;
    return _ProbeJob(
      applyAs: target,
      name: target,
      altName: target == node.name ? null : node.name,
    );
  }

  _ProbeContext _captureProbe() => _ProbeContext(
    _backendToken,
    _probeGeneration,
    _boundRepository,
    _probeCancellation,
  );

  bool _isProbeCurrent(_ProbeContext probe) =>
      !isDisposed &&
      identical(probe.token, _backendToken) &&
      probe.generation == _probeGeneration &&
      !probe.cancellation.isCancelled;

  Future<void> _probeJobs(_ProbeContext probe, List<_ProbeJob> jobs) async {
    final targets = jobs
        .where((job) => job.name.trim().isNotEmpty)
        .toList(growable: false);
    if (targets.isEmpty) return;
    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        if (!_isProbeCurrent(probe)) return;
        final index = cursor;
        cursor += 1;
        if (index >= targets.length) return;
        final job = targets[index];
        final delay = await probe.repository.probeDelay(
          name: job.name,
          altName: job.altName,
          cancellation: probe.cancellation,
        );
        if (!_isProbeCurrent(probe)) return;
        await _applyDelay(probe, job.applyAs, delay);
      }
    }

    final workers = targets.length < 4 ? targets.length : 4;
    await Future.wait<void>(<Future<void>>[
      for (var i = 0; i < workers; i++) worker(),
    ]);
  }

  Future<void> _applyDelay(_ProbeContext probe, String name, WifiDelay delay) {
    return _commitGroups(probe, (groups) {
      return <WifiCallGroup>[
        for (final group in groups) group.withProbedDelay(name, delay),
      ];
    });
  }

  Future<void> _applyDelays(
    _ProbeContext probe,
    String groupName,
    Map<String, WifiDelay> delays,
  ) {
    return _commitGroups(probe, (groups) {
      return <WifiCallGroup>[
        for (final group in groups)
          group.groupName == groupName ? group.withProbedDelays(delays) : group,
      ];
    });
  }

  Future<void> _commitGroups(
    _ProbeContext probe,
    List<WifiCallGroup> Function(List<WifiCallGroup> groups) update,
  ) {
    final next = _probeTail.then((_) {
      if (!_isProbeCurrent(probe)) return;
      final groups = _groups.lastGoodData;
      if (groups == null) return;
      _setGroups(
        QueryState<List<WifiCallGroup>>.data(
          data: List<WifiCallGroup>.unmodifiable(update(groups)),
          key: _readKey,
        ),
      );
    });
    _probeTail = next;
    return next;
  }

  Future<void> _probeTail = Future<void>.value();

  void _setGroups(QueryState<List<WifiCallGroup>> next) {
    publish(() {
      _groups = next;
      _snapshotToken = next.lastGoodData?.isNotEmpty == true
          ? _backendToken
          : null;
    });
  }

  void _setConnections(QueryState<List<WifiCallConnection>> next) {
    publish(() => _liveConnections = next);
  }

  void _setSelectAction(ActionState next) {
    publish(() => _selectAction = next);
  }

  @override
  void dispose() {
    final store = _backendStore;
    if (store is ObservableMihomoBackendStore) {
      store.removeListener(_backendChanged);
    }
    _probeCancellation.cancel();
    super.dispose();
  }
}

final class _ProbeContext {
  const _ProbeContext(
    this.token,
    this.generation,
    this.repository,
    this.cancellation,
  );
  final Object token;
  final int generation;
  final ProxyRepository repository;
  final RequestCancellation cancellation;
}

final class _ProbeJob {
  const _ProbeJob({required this.applyAs, required this.name, this.altName});

  final String applyAs;
  final String name;
  final String? altName;
}
