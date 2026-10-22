import 'dart:async';

import '../../../core/http/http_transport.dart';
import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../data/logs_repository.dart';
import '../domain/log_entry.dart';

final class LogsController extends RequestNotifier {
  LogsController({required this.repository, required this.requestRegistry})
    : _read = RequestSlot(requestRegistry, _loadKey);

  static const String _loadKey = 'logs.history';
  static const int _maxLiveEntries = 500;

  final LogsRepository repository;
  final RequestRegistry requestRegistry;
  final RequestSlot _read;
  QueryState<List<LogEntry>> _entries =
      const QueryState<List<LogEntry>>.initial(key: _loadKey);
  String _level = 'warn';
  String _search = '';
  RequestCancellation? _streamCancellation;
  bool _watchStopped = false;

  QueryState<List<LogEntry>> get entries => _entries;
  String get level => _level;
  String get search => _search;

  /// True while an SSE live stream is armed (no 5s history Timer).
  bool get isLiveStreaming => _streamCancellation != null;

  @override
  List<RequestSlot> get slots => <RequestSlot>[_read];

  Future<void> load({String? level, String? search}) async {
    if (isDisposed) return;
    stopWatching();
    _watchStopped = false;
    if (level != null) _level = level;
    if (search != null) _search = search;
    await _fetch();
    _syncWatch();
  }

  void startWatching() {
    _watchStopped = false;
    if (isDisposed || _streamCancellation != null) return;
    if (_entries.status != QueryStatus.data &&
        _entries.status != QueryStatus.empty) {
      return;
    }
    _openStream();
  }

  void stopWatching() {
    _watchStopped = true;
    final live = _streamCancellation;
    _streamCancellation = null;
    live?.cancel();
  }

  Future<void> _fetch() => runQuery<List<LogEntry>>(
    slot: _read,
    current: () => _entries,
    set: (next) {
      if (next.status == QueryStatus.failed) stopWatching();
      _setEntries(next);
    },
    fetch: (ticket) => repository.fetchHistory(
      level: _level,
      search: _search,
      cancellation: ticket.cancellation,
    ),
    isEmpty: (logs) => logs.isEmpty,
  );

  void _syncWatch() {
    if (_watchStopped) return;
    if (_entries.status == QueryStatus.data ||
        _entries.status == QueryStatus.empty) {
      startWatching();
    }
  }

  void _openStream() {
    final cancellation = RequestCancellation();
    _streamCancellation = cancellation;
    unawaited(_consumeStream(cancellation));
  }

  Future<void> _consumeStream(RequestCancellation cancellation) async {
    try {
      await repository.watchLive(
        level: _level,
        cancellation: cancellation,
        onEntry: (entry) {
          if (isDisposed || _watchStopped) return false;
          if (!_matchesSearch(entry)) return true;
          _appendEntry(entry);
          return true;
        },
      );
    } on ApiFailure catch (error) {
      if (error.kind == ApiFailureKind.cancelled) return;
      if (!isDisposed && !_watchStopped) stopWatching();
    } catch (_) {
      if (!isDisposed && !_watchStopped) stopWatching();
    } finally {
      if (identical(_streamCancellation, cancellation)) {
        _streamCancellation = null;
      }
    }
  }

  bool _matchesSearch(LogEntry entry) {
    final needle = _search.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return entry.message.toLowerCase().contains(needle);
  }

  void _appendEntry(LogEntry entry) {
    if (isDisposed) return;
    final current = _entries.lastGoodData ?? const <LogEntry>[];
    final next = List<LogEntry>.of(current)..add(entry);
    while (next.length > _maxLiveEntries) {
      next.removeAt(0);
    }
    _setEntries(
      QueryState<List<LogEntry>>.data(
        data: List<LogEntry>.unmodifiable(next),
        key: _loadKey,
      ),
    );
  }

  void _setEntries(QueryState<List<LogEntry>> next) =>
      publish(() => _entries = next);

  @override
  void dispose() {
    if (isDisposed) return;
    stopWatching();
    super.dispose();
  }
}
