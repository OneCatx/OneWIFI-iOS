import 'dart:convert';

import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../../../core/security/redaction.dart';
import '../domain/automation.dart';

part 'automation_dto.dart';

final class AutomationApi {
  const AutomationApi(this._transport);

  final HttpTransport _transport;

  Future<List<AutomationTask>> fetchTasks({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.automaticTasks,
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return List<AutomationTask>.unmodifiable(
      _shape.list(map['tasks']).map(_parseTask),
    );
  }

  Future<AutomationRunPage> fetchRuns({
    required int limit,
    required int offset,
    RequestCancellation? cancellation,
  }) async {
    if (limit <= 0 || offset < 0) throw const AutomationDtoException();
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.automaticTaskRuns,
      queryParameters: <String, String?>{
        'limit': '$limit',
        'offset': '$offset',
      },
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return AutomationRunPage(
      runs: List<AutomationRun>.unmodifiable(
        _shape.list(map['runs']).map(_parseRun),
      ),
      total: _shape.nonNegativeInt(map['total']),
    );
  }

  Future<AutomationTask> setEnabled(
    AutomationTaskTarget target, {
    required bool enabled,
    RequestCancellation? cancellation,
  }) async {
    final raw = _target(target);
    final body = Map<String, Object?>.of(raw._writeBody)..['enabled'] = enabled;
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.automaticTask,
      pathParameters: <String, String>{'id': '${raw._id}'},
      body: body,
      cancellation: cancellation,
    );
    return _parseTask(data);
  }

  Future<void> deleteTask(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) async {
    final raw = _target(target);
    final data = await _transport.sendJson(
      method: 'DELETE',
      routeTemplate: GatewayApi.automaticTask,
      pathParameters: <String, String>{'id': '${raw._id}'},
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    if (map['deleted'] != true) throw const AutomationDtoException();
  }

  Future<AutomationRun> runNow(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) async {
    final raw = _target(target);
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.automaticTaskRun,
      pathParameters: <String, String>{'id': '${raw._id}'},
      body: const <String, Object?>{},
      cancellation: cancellation,
    );
    return _parseRun(data);
  }

  static _AutomationTaskTarget _target(AutomationTaskTarget target) {
    if (target is! _AutomationTaskTarget) {
      throw StateError('Invalid automation task target.');
    }
    return target;
  }
}
