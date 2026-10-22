import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../data/upstream_repository.dart';
import '../domain/upstream_proxy.dart';

final class UpstreamController extends RequestNotifier {
  UpstreamController({
    required this.repository,
    required this.requestRegistry,
  }) : _read = RequestSlot(requestRegistry, _loadKey),
       _mutate = RequestSlot(requestRegistry, _mutateKey);

  static const String _loadKey = 'upstream.list';
  static const String _mutateKey = 'upstream.mutate';

  final UpstreamRepository repository;
  final RequestRegistry requestRegistry;
  final RequestSlot _read;
  final RequestSlot _mutate;

  QueryState<List<UpstreamProxy>> _items =
      const QueryState<List<UpstreamProxy>>.initial(key: _loadKey);
  ActionState _action = const ActionState.idle();
  String _busyId = '';

  QueryState<List<UpstreamProxy>> get items => _items;
  ActionState get action => _action;
  String get busyId => _busyId;

  @override
  List<RequestSlot> get slots => <RequestSlot>[_read, _mutate];

  Future<void> load() => runQuery<List<UpstreamProxy>>(
    slot: _read,
    current: () => _items,
    set: (next) => publish(() => _items = next),
    fetch: (ticket) => repository.list(cancellation: ticket.cancellation),
    isEmpty: (list) => list.isEmpty,
  );

  Future<void> refresh() => load();

  Future<void> toggle(UpstreamProxy item) async {
    publish(() => _busyId = item.id);
    final ok = await runAction<void>(
      slot: _mutate,
      current: () => _action,
      set: (next) => publish(() => _action = next),
      request: (ticket) => repository.setEnabled(
        item.id,
        !item.enabled,
        cancellation: ticket.cancellation,
      ),
      always: (_) => publish(() => _busyId = ''),
    );
    if (ok) await load();
  }

  Future<void> probe(UpstreamProxy item) async {
    publish(() => _busyId = item.id);
    await runAction<void>(
      slot: _mutate,
      current: () => _action,
      set: (next) => publish(() => _action = next),
      request: (ticket) =>
          repository.probe(item.id, cancellation: ticket.cancellation),
      always: (_) => publish(() => _busyId = ''),
    );
  }
}
