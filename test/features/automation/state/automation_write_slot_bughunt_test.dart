import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/features/automation/data/automation_repository.dart';
import 'package:onewifi_android/features/automation/domain/automation.dart';
import 'package:onewifi_android/features/automation/state/automation_controller.dart';

// B1-05：删除任务后 `_writes` 仍按 task.id 持有 RequestSlot，登录期内只增不减。
void main() {
  test('deleteTask 成功后，该任务的写入请求线不应继续留在 slots 里', () async {
    final repo = _Repo(tasks: <AutomationTask>[_task(7), _task(8)]);
    final controller = AutomationController(
      repository: repo,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    // ignore: invalid_use_of_protected_member
    final before = controller.slots.length;
    await controller.deleteTask(_task(7));
    expect(controller.actionFor(7).status, ActionStatus.idle);
    expect(controller.workspace.lastGoodData!.tasks.map((t) => t.id), <int>[8]);

    // ignore: invalid_use_of_protected_member
    final after = controller.slots.length;
    expect(after, before);
  });
}

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

final class _Repo implements AutomationRepository {
  _Repo({required this.tasks});

  List<AutomationTask> tasks;

  @override
  Future<List<AutomationTask>> fetchTasks({
    RequestCancellation? cancellation,
  }) async => tasks;

  @override
  Future<AutomationRunPage> fetchRuns({
    required int limit,
    required int offset,
    RequestCancellation? cancellation,
  }) async => const AutomationRunPage(runs: <AutomationRun>[], total: 0);

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
  }) async => throw UnimplementedError();
}
