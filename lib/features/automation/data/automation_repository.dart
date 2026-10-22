import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/automation.dart';
import 'automation_api.dart';

abstract interface class AutomationRepository {
  Future<List<AutomationTask>> fetchTasks({RequestCancellation? cancellation});

  Future<AutomationRunPage> fetchRuns({
    required int limit,
    required int offset,
    RequestCancellation? cancellation,
  });

  Future<AutomationTask> setEnabled(
    AutomationTaskTarget target, {
    required bool enabled,
    RequestCancellation? cancellation,
  });

  Future<void> deleteTask(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  });

  Future<AutomationRun> runNow(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  });
}

final class DefaultAutomationRepository implements AutomationRepository {
  const DefaultAutomationRepository(this._api);

  final AutomationApi _api;

  @override
  Future<List<AutomationTask>> fetchTasks({
    RequestCancellation? cancellation,
  }) => _translate(() => _api.fetchTasks(cancellation: cancellation));

  @override
  Future<AutomationRunPage> fetchRuns({
    required int limit,
    required int offset,
    RequestCancellation? cancellation,
  }) => _translate(
    () => _api.fetchRuns(
      limit: limit,
      offset: offset,
      cancellation: cancellation,
    ),
  );

  @override
  Future<AutomationTask> setEnabled(
    AutomationTaskTarget target, {
    required bool enabled,
    RequestCancellation? cancellation,
  }) => _translate(
    () => _api.setEnabled(target, enabled: enabled, cancellation: cancellation),
  );

  @override
  Future<void> deleteTask(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) => _translate(() => _api.deleteTask(target, cancellation: cancellation));

  @override
  Future<AutomationRun> runNow(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) => _translate(() => _api.runNow(target, cancellation: cancellation));

  Future<T> _translate<T>(Future<T> Function() operation) async {
    return guardShape('local-automation-response', () async {
      return await operation();
    });
  }
}
