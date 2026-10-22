import 'dart:convert';

import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../../../core/http/sse_decoder.dart';
import '../domain/log_entry.dart';

final class LogsApi {
  const LogsApi(this._transport);
  final HttpTransport _transport;

  Future<List<LogEntry>> fetchHistory({
    int lines = 500,
    String level = 'warn',
    String search = '',
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.logsHistory,
      queryParameters: <String, String?>{
        'lines': '$lines',
        'level': level.trim().isEmpty ? null : level,
        'search': search.trim().isEmpty ? null : search.trim(),
      },
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return List<LogEntry>.unmodifiable(
      _shape.list(map['logs']).map(_parseEntry),
    );
  }

  /// Live log SSE (`GET GatewayApi.logsStream`). Comment frames (`: keepalive`)
  /// are dropped by [SseDecoder]; `connected` is ignored; only `log` entries
  /// invoke [onEntry]. Return `false` from [onEntry] to stop the reader.
  Future<void> watchStream({
    String level = 'warn',
    required bool Function(LogEntry entry) onEntry,
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendSse(
      method: 'GET',
      routeTemplate: GatewayApi.logsStream,
      queryParameters: <String, String?>{
        'level': level.trim().isEmpty ? null : level,
      },
      cancellation: cancellation,
      onEvent: (SseEvent event) {
        if (event.name == 'connected') return true;
        if (event.name != 'log' && event.name != 'message') return true;
        final trimmed = event.data.trim();
        if (trimmed.isEmpty) return true;
        late final Object? decoded;
        try {
          decoded = jsonDecode(trimmed);
        } on FormatException {
          return true;
        }
        if (decoded is! Map<Object?, Object?>) return true;
        try {
          return onEntry(_parseEntry(decoded));
        } on DtoShapeException {
          return true;
        }
      },
    );
  }

  static LogEntry _parseEntry(Object? value) {
    final map = _shape.map(value);
    return LogEntry(
      time: _shape.dateTime(map['time']).toLocal(),
      level: _shape.string(map['level']).trim(),
      message: _shape.string(map['message']),
    );
  }
}

final class LogsDtoException implements DtoShapeException {
  const LogsDtoException();
}

const _shape = JsonShape(LogsDtoException.new);
