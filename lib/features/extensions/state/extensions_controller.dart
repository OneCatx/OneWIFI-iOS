import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../data/extensions_repository.dart';
import '../domain/gateway_extension.dart';

final class ExtensionsController extends RequestNotifier {
  ExtensionsController({
    required this.repository,
    required this.requestRegistry,
  }) : _read = RequestSlot(requestRegistry, _loadKey),
       _mutate = RequestSlot(requestRegistry, _mutateKey);

  static const String _loadKey = 'extensions.list';
  static const String _mutateKey = 'extensions.mutate';

  final ExtensionsRepository repository;
  final RequestRegistry requestRegistry;
  final RequestSlot _read;
  final RequestSlot _mutate;

  QueryState<List<GatewayExtension>> _items =
      const QueryState<List<GatewayExtension>>.initial(key: _loadKey);
  ActionState _action = const ActionState.idle();
  String _busyId = '';

  QueryState<List<GatewayExtension>> get items => _items;
  ActionState get action => _action;
  String get busyId => _busyId;

  @override
  List<RequestSlot> get slots => <RequestSlot>[_read, _mutate];

  Future<void> load() => runQuery<List<GatewayExtension>>(
    slot: _read,
    current: () => _items,
    set: (next) => publish(() => _items = next),
    fetch: (ticket) => repository.list(cancellation: ticket.cancellation),
    isEmpty: (list) => list.isEmpty,
  );

  Future<void> refresh() => load();

  Future<void> installFromUrl(String url, {String sha256 = ''}) async {
    if (url.trim().isEmpty) return;
    final ok = await runAction<void>(
      slot: _mutate,
      current: () => _action,
      set: (next) => publish(() => _action = next),
      request: (ticket) => repository.installFromUrl(
        url,
        sha256: sha256,
        cancellation: ticket.cancellation,
      ),
    );
    if (ok) await load();
  }

  Future<void> toggle(GatewayExtension item) async {
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

  Future<void> remove(GatewayExtension item) async {
    publish(() => _busyId = item.id);
    final ok = await runAction<void>(
      slot: _mutate,
      current: () => _action,
      set: (next) => publish(() => _action = next),
      request: (ticket) =>
          repository.delete(item.id, cancellation: ticket.cancellation),
      always: (_) => publish(() => _busyId = ''),
    );
    if (ok) await load();
  }
}
