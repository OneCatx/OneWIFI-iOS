import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/features/automation/data/automation_repository.dart';
import 'package:onewifi_android/features/automation/domain/automation.dart';
import 'package:onewifi_android/features/automation/state/automation_controller.dart';

// B1-02：`runNow` / `load` 把 queued|running 映射成
// `ActionState.submitting(reconciling: true)`，解除路径只有 `_reconcileRuns`
// 在首页 20 条里再次看到 id ≥ minimum 的记录。记录被挤出首页，或首页只剩
// 更旧的 run 时，`continue` 让任务永久停在 submitting；卡片开关 / 立即执行 /
// 删除全部禁用到重启。
//
// 产品裁定：刷新后首页没有合格记录 → 回退 idle，允许再操作。
void main() {
  test('刷新后首页已无该任务运行记录时，不得继续 submitting', () async {
    final repo = _Repo(
      tasks: <AutomationTask>[_task(7), _task(8)],
      runs: <AutomationRun>[_run(91, AutomationRunStatus.running, taskId: 7)],
    );
    final controller = _controller(repo);
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.actionFor(7).status, ActionStatus.submitting);
    expect(controller.actionFor(7).reconciling, isTrue);

    repo.runs = List<AutomationRun>.generate(
      20,
      (i) => _run(200 + i, AutomationRunStatus.success, taskId: 8),
    );
    await controller.refresh();
    expect(
      controller.workspace.lastGoodData!.runs.any((r) => r.taskId == 7),
      isFalse,
    );
    expect(controller.actionFor(7).status, ActionStatus.idle);

    await controller.runNow(_task(7));
    expect(repo.runCalls, 1);
  });

  test('立即执行后首页只剩更旧记录时，不得继续 submitting', () async {
    final repo = _Repo(
      tasks: <AutomationTask>[_task(7)],
      runs: <AutomationRun>[_run(90, AutomationRunStatus.success, taskId: 7)],
    );
    final controller = _controller(repo);
    addTearDown(controller.dispose);
    await controller.load();

    await controller.runNow(_task(7));
    expect(controller.actionFor(7).status, ActionStatus.submitting);
    expect(controller.actionFor(7).reconciling, isTrue);
    expect(controller.actionFor(7).operationId, '91');

    await controller.refresh();
    expect(controller.actionFor(7).status, ActionStatus.idle);
    expect(controller.actionFor(7).isUnknownOutcome, isFalse);
  });
}

AutomationController _controller(_Repo repo) =>
    AutomationController(repository: repo, requestRegistry: RequestRegistry());

final class _Target implements AutomationTaskTarget {
  const _Target();
}

AutomationTask _task(int id) => AutomationTask(
  id: id,
  name: 'Task $id',
  enabled: true,
  deviceId: 'device-a',
  profileDisplay: '•••• 1234',
  taskType: AutomationTaskType.sms,
  environment: AutomationEnvironment.vowifi,
  intervalDays: 1,
  runTime: '08:30',
  nextRunAt: DateTime.utc(2026, 9, 3),
  target: const _Target(),
);

AutomationRun _run(int id, AutomationRunStatus status, {required int taskId}) =>
    AutomationRun(
      id: id,
      taskId: taskId,
      deviceId: 'device-a',
      scheduledAt: DateTime.utc(2026, 9, 2, 1),
      startedAt: status == AutomationRunStatus.queued
          ? null
          : DateTime.utc(2026, 9, 2, 1, 0, 2),
      finishedAt:
          status == AutomationRunStatus.success ||
              status == AutomationRunStatus.failed
          ? DateTime.utc(2026, 9, 2, 1, 1)
          : null,
      status: status,
      attempts: status == AutomationRunStatus.queued ? 0 : 1,
      output: status == AutomationRunStatus.success ? 'completed' : '',
      error: status == AutomationRunStatus.failed ? 'failed safely' : '',
    );

final class _Repo implements AutomationRepository {
  _Repo({required this.tasks, List<AutomationRun>? runs})
    : runs = runs ?? <AutomationRun>[];

  List<AutomationTask> tasks;
  List<AutomationRun> runs;
  int runCalls = 0;

  @override
  Future<List<AutomationTask>> fetchTasks({
    RequestCancellation? cancellation,
  }) async => tasks;

  @override
  Future<AutomationRunPage> fetchRuns({
    required int limit,
    required int offset,
    RequestCancellation? cancellation,
  }) async => AutomationRunPage(runs: runs, total: runs.length);

  @override
  Future<AutomationTask> setEnabled(
    AutomationTaskTarget target, {
    required bool enabled,
    RequestCancellation? cancellation,
  }) async => tasks.first.copyWith(enabled: enabled);

  @override
  Future<void> deleteTask(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<AutomationRun> runNow(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) async {
    runCalls += 1;
    return _run(91, AutomationRunStatus.queued, taskId: 7);
  }
}
