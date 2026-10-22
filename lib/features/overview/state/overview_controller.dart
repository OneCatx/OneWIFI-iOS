import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../../../core/state/state_failure.dart';
import '../data/overview_repository.dart';
import '../domain/overview.dart';

final class OverviewSnapshot {
  const OverviewSnapshot({
    this.host,
    this.devices,
    this.hostFailure,
    this.devicesFailure,
    this.hostStale = false,
    this.devicesStale = false,
  });

  final HostOverview? host;
  final List<DeviceOverview>? devices;
  final StateFailure? hostFailure;
  final StateFailure? devicesFailure;
  final bool hostStale;
  final bool devicesStale;

  bool get hasMeaningfulContent =>
      (host?.hasMeaningfulContent ?? false) || (devices?.isNotEmpty ?? false);
}

final class OverviewController extends RequestNotifier {
  factory OverviewController({
    required OverviewRepository repository,
    required RequestRegistry requestRegistry,
  }) => OverviewController._(repository, requestRegistry);

  OverviewController._(this._repository, RequestRegistry requestRegistry)
    : _read = RequestSlot(requestRegistry, _requestKey);

  static const String _requestKey = 'overview.dashboard';

  final OverviewRepository _repository;
  final RequestSlot _read;
  QueryState<OverviewSnapshot> _state = const QueryState.initial(
    key: _requestKey,
  );

  QueryState<OverviewSnapshot> get state => _state;

  @override
  List<RequestSlot> get slots => <RequestSlot>[_read];

  Future<void> load() => _request();

  Future<void> refresh() => _request();

  Future<void> _request() async {
    if (isDisposed) return;
    final ticket = _read.begin();
    final previous = _state.lastGoodData;
    _setState(QueryState.pending(previous: previous, key: _requestKey));

    final hostPending = _capture(
      _repository.fetchHost(cancellation: ticket.cancellation),
    );
    final devicesPending = _capture(
      _repository.fetchDevices(cancellation: ticket.cancellation),
    );
    try {
      final results = await Future.wait<_Outcome<Object>>(
        <Future<_Outcome<Object>>>[hostPending, devicesPending],
      );
      if (!ticket.isCurrent) return;

      final hostOutcome = results[0];
      final devicesOutcome = results[1];
      final hostFailure = hostOutcome.failure;
      final devicesFailure = devicesOutcome.failure;
      final host = hostOutcome.value as HostOverview? ?? previous?.host;
      final devices =
          devicesOutcome.value as List<DeviceOverview>? ?? previous?.devices;
      final hostStale = hostFailure != null && previous?.host != null;
      final devicesStale = devicesFailure != null && previous?.devices != null;
      final snapshot = OverviewSnapshot(
        host: host,
        devices: devices,
        hostFailure: hostFailure,
        devicesFailure: devicesFailure,
        hostStale: hostStale,
        devicesStale: devicesStale,
      );

      if (hostFailure != null || devicesFailure != null) {
        _setState(
          QueryState.failed(
            failure: hostFailure ?? devicesFailure!,
            lastGoodData: snapshot,
            isStale: hostStale || devicesStale,
            key: _requestKey,
          ),
        );
      } else if (!snapshot.hasMeaningfulContent) {
        _setState(const QueryState.empty(key: _requestKey));
      } else {
        _setState(QueryState.data(data: snapshot, key: _requestKey));
      }
    } finally {
      ticket.end();
    }
  }

  void _setState(QueryState<OverviewSnapshot> next) =>
      publish(() => _state = next);

  static Future<_Outcome<Object>> _capture(Future<Object> pending) async {
    try {
      return _Outcome<Object>.success(await pending);
    } catch (error) {
      return _Outcome<Object>.failed(StateFailure.fromError(error));
    }
  }
}

final class _Outcome<T> {
  const _Outcome.success(T this.value) : failure = null;

  const _Outcome.failed(StateFailure this.failure) : value = null;

  final T? value;
  final StateFailure? failure;
}
