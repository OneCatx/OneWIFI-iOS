import '../../../core/http/http_transport.dart';
import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../../../core/state/state_failure.dart';
import '../data/automation_repository.dart';
import '../domain/automation.dart';

enum _AutomationActionSource { write, run }

final class AutomationController extends RequestNotifier {
  AutomationController({
    required this.repository,
    required this.requestRegistry,
  }) : _read = RequestSlot(requestRegistry, _loadKey);

  static const String _loadKey = 'automation.load';
  static const int _runPageSize = 20;

  final AutomationRepository repository;
  final RequestRegistry requestRegistry;
  final RequestSlot _read;
  bool _runsNeedReload = false;
  QueryState<AutomationWorkspace> _workspace =
      const QueryState<AutomationWorkspace>.initial(key: _loadKey);
  final Map<int, ActionState> _actions = <int, ActionState>{};
  final Map<int, _AutomationActionSource> _actionSources =
      <int, _AutomationActionSource>{};
  final Map<int, int> _minimumRunIds = <int, int>{};
  final Map<int, RequestSlot> _writes = <int, RequestSlot>{};

  QueryState<AutomationWorkspace> get workspace => _workspace;

  ActionState actionFor(int taskId) =>
      _actions[taskId] ?? const ActionState.idle();

  @override
  List<RequestSlot> get slots => <RequestSlot>[_read, ..._writes.values];

  Future<void> load() async {
    if (isDisposed) return;
    final ticket = _read.begin();
    final previous = _workspace.lastGoodData;
    _setWorkspace(QueryState.pending(previous: previous, key: _loadKey));
    try {
      final tasks = await repository.fetchTasks(
        cancellation: ticket.cancellation,
      );
      if (!ticket.isCurrent) return;
      final page = await repository.fetchRuns(
        limit: _runPageSize,
        offset: 0,
        cancellation: ticket.cancellation,
      );
      if (!ticket.isCurrent) return;
      final value = AutomationWorkspace(
        tasks: List<AutomationTask>.unmodifiable(tasks),
        runs: List<AutomationRun>.unmodifiable(page.runs),
        runTotal: page.total,
      );
      _runsNeedReload = false;
      _reconcileRuns(value);
      _setWorkspace(
        tasks.isEmpty && page.runs.isEmpty
            ? const QueryState<AutomationWorkspace>.empty(key: _loadKey)
            : QueryState<AutomationWorkspace>.data(data: value, key: _loadKey),
      );
    } catch (error) {
      if (!ticket.isCurrent) return;
      _setWorkspace(
        QueryState.failedAfter(error, previous: previous, key: _loadKey),
      );
    } finally {
      ticket.end();
    }
  }

  Future<void> refresh() => load();

  Future<void> setEnabled(AutomationTask task, {required bool enabled}) =>
      _write<AutomationTask>(
        task,
        source: _AutomationActionSource.write,
        operation: (cancellation) => repository.setEnabled(
          task.target,
          enabled: enabled,
          cancellation: cancellation,
        ),
        onSuccess: (updated) {
          _replaceTask(task.id, updated);
          _actions[task.id] = const ActionState.succeeded();
        },
      );

  Future<void> deleteTask(AutomationTask task) => _write<void>(
    task,
    source: _AutomationActionSource.write,
    operation: (cancellation) =>
        repository.deleteTask(task.target, cancellation: cancellation),
    onSuccess: (_) {
      _runsNeedReload = true;
      _removeTask(task.id);
    },
  );

  Future<void> _reloadRuns() async {
    final previous = _workspace.lastGoodData;
    if (previous == null || isDisposed) return;
    final ticket = _read.begin();
    _setWorkspace(QueryState.pending(previous: previous, key: _loadKey));
    try {
      final page = await repository.fetchRuns(
        limit: _runPageSize,
        offset: 0,
        cancellation: ticket.cancellation,
      );
      if (!ticket.isCurrent) return;
      final value = AutomationWorkspace(
        tasks: previous.tasks,
        runs: List<AutomationRun>.unmodifiable(page.runs),
        runTotal: page.total,
      );
      _runsNeedReload = false;
      _reconcileRuns(value);
      _setWorkspace(
        value.tasks.isEmpty && page.total == 0
            ? const QueryState<AutomationWorkspace>.empty(key: _loadKey)
            : QueryState.data(data: value, key: _loadKey),
      );
    } catch (error) {
      if (!ticket.isCurrent) return;
      _setWorkspace(
        QueryState.failedAfter(error, previous: previous, key: _loadKey),
      );
    } finally {
      ticket.end();
    }
  }

  Future<void> runNow(AutomationTask task) {
    if (isDisposed || actionFor(task.id).status == ActionStatus.submitting) {
      return Future<void>.value();
    }
    final currentRuns =
        _workspace.lastGoodData?.runs ?? const <AutomationRun>[];
    final latestId = currentRuns
        .where((run) => run.taskId == task.id)
        .fold<int>(0, (latest, run) => run.id > latest ? run.id : latest);
    _minimumRunIds[task.id] = latestId + 1;
    return _write<AutomationRun>(
      task,
      source: _AutomationActionSource.run,
      operation: (cancellation) =>
          repository.runNow(task.target, cancellation: cancellation),
      onSuccess: (run) {
        _minimumRunIds[task.id] = run.id;
        _upsertRun(run);
        _actions[task.id] = _actionForRun(run);
      },
    );
  }

  Future<void> _write<T>(
    AutomationTask task, {
    required _AutomationActionSource source,
    required Future<T> Function(RequestCancellation cancellation) operation,
    required void Function(T value) onSuccess,
  }) async {
    if (isDisposed || actionFor(task.id).status == ActionStatus.submitting) {
      return;
    }
    final slot = _writes.putIfAbsent(
      task.id,
      () => RequestSlot(requestRegistry, 'automation.write.${task.id}'),
    );
    _actionSources[task.id] = source;
    var accepted = false;
    await runAction<T>(
      slot: slot,
      current: () => actionFor(task.id),
      set: (next) => _setAction(task.id, next),
      request: (ticket) => operation(ticket.cancellation),
      onSuccess: (result, _) {
        accepted = true;
        // A read started before this accepted mutation cannot restore its old snapshot.
        _read.cancel();
        publish(() => onSuccess(result));
        return null;
      },
    );
    // Every accepted write invalidates older reads. If a delete left totals
    // unsettled, replace the cancelled reconciliation with a fresh read.
    if (accepted && _runsNeedReload && !isDisposed) await _reloadRuns();
  }

  void _reconcileRuns(AutomationWorkspace value) {
    final latest = <int, AutomationRun>{};
    for (final run in value.runs) {
      final current = latest[run.taskId];
      if (current == null || run.id > current.id) latest[run.taskId] = run;
    }
    for (final task in value.tasks) {
      final run = latest[task.id];
      final current = actionFor(task.id);
      final source = _actionSources[task.id];
      final minimum = _minimumRunIds[task.id];
      final qualifying = run != null && (minimum == null || run.id >= minimum);
      if (!qualifying) {
        // 首页 20 条对不上正在对账的 run（被挤出或只剩更旧记录）时解锁，
        // 不碰 in-flight 写入（!reconciling）和失败/未知终态。
        if (current.status == ActionStatus.submitting && current.reconciling) {
          _actions[task.id] = const ActionState.idle();
        }
        continue;
      }
      if (current.status != ActionStatus.idle &&
          source != _AutomationActionSource.run) {
        continue;
      }
      _actionSources[task.id] = _AutomationActionSource.run;
      _minimumRunIds[task.id] = run.id;
      _actions[task.id] = _actionForRun(run);
    }
  }

  static ActionState _actionForRun(AutomationRun run) => switch (run.status) {
    AutomationRunStatus.queued || AutomationRunStatus.running =>
      ActionState.submitting(operationId: '${run.id}', reconciling: true),
    AutomationRunStatus.success => const ActionState.succeeded(),
    AutomationRunStatus.failed => ActionState.failed(
      knownFailure: const StateFailure(StateFailureKind.generic),
    ),
  };

  void _replaceTask(int id, AutomationTask updated) {
    final current = _workspace.lastGoodData;
    if (current == null) return;
    final value = AutomationWorkspace(
      tasks: List<AutomationTask>.unmodifiable(
        current.tasks.map((task) => task.id == id ? updated : task),
      ),
      runs: current.runs,
      runTotal: current.runTotal,
    );
    _workspace = QueryState<AutomationWorkspace>.data(
      data: value,
      key: _loadKey,
    );
  }

  void _removeTask(int id) {
    final current = _workspace.lastGoodData;
    if (current == null) return;
    final tasks = current.tasks.where((task) => task.id != id).toList();
    final runs = current.runs.where((run) => run.taskId != id).toList();
    final value = AutomationWorkspace(
      tasks: List<AutomationTask>.unmodifiable(tasks),
      runs: List<AutomationRun>.unmodifiable(runs),
      // Keep the last known total until the authoritative runs page is reloaded.
      runTotal: current.runTotal,
    );
    _actions.remove(id);
    _actionSources.remove(id);
    _minimumRunIds.remove(id);
    _writes.remove(id)?.close();
    _workspace = QueryState<AutomationWorkspace>.data(
      data: value,
      key: _loadKey,
    );
  }

  void _upsertRun(AutomationRun run) {
    final current = _workspace.lastGoodData;
    if (current == null) return;
    final runs = <AutomationRun>[
      run,
      ...current.runs.where((item) => item.id != run.id),
    ];
    _workspace = QueryState<AutomationWorkspace>.data(
      data: AutomationWorkspace(
        tasks: current.tasks,
        runs: List<AutomationRun>.unmodifiable(runs),
        runTotal: current.runs.any((item) => item.id == run.id)
            ? current.runTotal
            : current.runTotal + 1,
      ),
      key: _loadKey,
    );
  }

  void _setWorkspace(QueryState<AutomationWorkspace> value) =>
      publish(() => _workspace = value);

  void _setAction(int taskId, ActionState value) =>
      publish(() => _actions[taskId] = value);

  @override
  void dispose() {
    super.dispose();
    _writes.clear();
  }
}
