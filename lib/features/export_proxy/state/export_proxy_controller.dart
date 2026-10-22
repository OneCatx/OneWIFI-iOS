import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../data/export_proxy_repository.dart';
import '../domain/export_proxy.dart';

final class ExportProxyController extends RequestNotifier {
  ExportProxyController({
    required this.repository,
    required this.requestRegistry,
  }) : _read = RequestSlot(requestRegistry, _loadKey);

  static const String _loadKey = 'export-proxy.list';

  final ExportProxyRepository repository;
  final RequestRegistry requestRegistry;
  final RequestSlot _read;

  QueryState<List<ExportProxyConfig>> _items =
      const QueryState<List<ExportProxyConfig>>.initial(key: _loadKey);

  QueryState<List<ExportProxyConfig>> get items => _items;

  @override
  List<RequestSlot> get slots => <RequestSlot>[_read];

  Future<void> load() => runQuery<List<ExportProxyConfig>>(
    slot: _read,
    current: () => _items,
    set: (next) => publish(() => _items = next),
    fetch: (ticket) async {
      final configs = await repository.list(
        cancellation: ticket.cancellation,
      );
      try {
        final running = await repository.status(
          cancellation: ticket.cancellation,
        );
        final byId = <String, ExportProxyConfig>{
          for (final c in running) c.id: c,
        };
        return List<ExportProxyConfig>.unmodifiable(
          configs.map((c) {
            final live = byId[c.id];
            if (live == null) return c;
            return ExportProxyConfig(
              id: c.id,
              name: c.name,
              mode: c.mode,
              listenHost: c.listenHost,
              listenPort: c.listenPort,
              enabled: c.enabled,
              deviceId: c.deviceId,
              running: live.running,
            );
          }),
        );
      } catch (_) {
        return configs;
      }
    },
    isEmpty: (list) => list.isEmpty,
  );

  Future<void> refresh() => load();
}
