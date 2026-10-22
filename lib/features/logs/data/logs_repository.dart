import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/log_entry.dart';
import 'logs_api.dart';

abstract interface class LogsRepository {
  Future<List<LogEntry>> fetchHistory({
    int lines,
    String level,
    String search,
    RequestCancellation? cancellation,
  });

  /// Incremental live stream. Must not run alongside a 5s history poll.
  Future<void> watchLive({
    String level,
    required bool Function(LogEntry entry) onEntry,
    RequestCancellation? cancellation,
  });
}

final class DefaultLogsRepository implements LogsRepository {
  const DefaultLogsRepository(this._api);
  final LogsApi _api;

  @override
  Future<List<LogEntry>> fetchHistory({
    int lines = 500,
    String level = 'warn',
    String search = '',
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-logs-response', () async {
      return await _api.fetchHistory(
        lines: lines,
        level: level,
        search: search,
        cancellation: cancellation,
      );
    });
  }

  @override
  Future<void> watchLive({
    String level = 'warn',
    required bool Function(LogEntry entry) onEntry,
    RequestCancellation? cancellation,
  }) {
    return _api.watchStream(
      level: level,
      onEntry: onEntry,
      cancellation: cancellation,
    );
  }
}
