import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';
import 'package:onewifi_android/features/automation/data/automation_repository.dart';
import 'package:onewifi_android/features/automation/domain/automation.dart';
import 'package:onewifi_android/features/automation/state/automation_controller.dart';

void main() {
  test(
    'failed delete reconciliation stays stale and a later write recovers it',
    () async {
      final repository = _Repository()
        ..total = 41
        ..totalAfterDelete = 37
        ..otherTask = _task(8);
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await controller.load();
      final failing = Completer<AutomationRunPage>();
      repository.nextRuns = failing;
      final deleting = controller.deleteTask(repository.task);
      await pumpEventQueue();
      failing.completeError(StateError('offline'));
      await deleting;
      expect(controller.workspace.status, QueryStatus.failed);
      expect(controller.workspace.isStale, isTrue);
      expect(controller.workspace.lastGoodData!.tasks.single.id, 8);
      await controller.setEnabled(repository.otherTask!, enabled: false);
      expect(controller.workspace.status, QueryStatus.data);
      expect(controller.workspace.lastGoodData!.runTotal, 37);
    },
  );

  test('disposed delete reconciliation ignores its late response', () async {
    final repository = _Repository()
      ..total = 41
      ..totalAfterDelete = 37;
    final controller = _controller(repository);
    await controller.load();
    final pending = Completer<AutomationRunPage>();
    repository.nextRuns = pending;
    final deleting = controller.deleteTask(repository.task);
    await pumpEventQueue();
    controller.dispose();
    final before = controller.workspace;
    pending.complete(const AutomationRunPage(runs: [], total: 37));
    await deleting;
    expect(controller.workspace, same(before));
  });
  for (final runNow in [false, true]) {
    test(
      'delete total reload survives another task ${runNow ? 'run' : 'toggle'}',
      () async {
        final repository = _Repository()
          ..total = 41
          ..totalAfterDelete = 37;
        repository.otherTask = _task(8);
        final controller = _controller(repository);
        addTearDown(controller.dispose);
        await controller.load();
        final stale = Completer<AutomationRunPage>();
        repository.nextRuns = stale;
        final deleting = controller.deleteTask(repository.task);
        await pumpEventQueue();
        if (runNow) {
          await controller.runNow(repository.otherTask!);
        } else {
          await controller.setEnabled(repository.otherTask!, enabled: false);
        }
        stale.complete(const AutomationRunPage(runs: [], total: 37));
        await deleting;
        expect(controller.workspace.lastGoodData!.runTotal, runNow ? 38 : 37);
        expect(controller.workspace.lastGoodData!.tasks.single.id, 8);
        if (!runNow) {
          expect(
            controller.workspace.lastGoodData!.tasks.single.enabled,
            isFalse,
          );
        }
        if (runNow) {
          expect(controller.workspace.lastGoodData!.runs.single.id, 91);
        }
      },
    );
  }
  for (final deleting in [false, true]) {
    test(
      'late refresh cannot undo a successful ${deleting ? 'delete' : 'toggle'}',
      () async {
        final repository = _Repository();
        final controller = _controller(repository);
        addTearDown(controller.dispose);
        await controller.load();
        final gate = Completer<AutomationRunPage>();
        repository.nextRuns = gate;
        final refreshing = controller.refresh();
        await pumpEventQueue();
        if (deleting) {
          await controller.deleteTask(repository.task);
        } else {
          await controller.setEnabled(repository.task, enabled: false);
        }
        gate.complete(const AutomationRunPage(runs: [], total: 0));
        await refreshing;
        final tasks = controller.workspace.lastGoodData?.tasks ?? [];
        if (deleting) {
          expect(tasks, isEmpty);
        } else {
          expect(tasks.single.enabled, isFalse);
        }
      },
    );
  }

  test(
    'delete reloads authoritative run total instead of counting the page',
    () async {
      final repository =
          _Repository(
              runs: [
                _run(90, AutomationRunStatus.success),
                _run(89, AutomationRunStatus.success, taskId: 8),
              ],
            )
            ..total = 41
            ..totalAfterDelete = 37;
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.deleteTask(repository.task);
      expect(controller.workspace.lastGoodData?.runTotal, 37);
      expect(controller.workspace.lastGoodData!.tasks, isEmpty);
    },
  );

  test(
    'run-now is single-flight and durable evidence reaches success',
    () async {
      final repository = _Repository(blockRun: true);
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await controller.load();

      final pending = controller.runNow(repository.task);
      controller.runNow(repository.task);
      expect(repository.runCalls, 1);
      expect(controller.actionFor(7).status, ActionStatus.submitting);

      repository.runCompleter.complete(_run(91, AutomationRunStatus.queued));
      await pending;
      expect(controller.actionFor(7).operationId, '91');
      expect(controller.actionFor(7).reconciling, isTrue);
      await controller.runNow(repository.task);
      expect(repository.runCalls, 1);

      repository.runs = <AutomationRun>[_run(91, AutomationRunStatus.success)];
      await controller.refresh();
      expect(controller.actionFor(7).status, ActionStatus.succeeded);
      expect(
        controller.workspace.lastGoodData!.runs.single.status,
        AutomationRunStatus.success,
      );
    },
  );

  test('409 is known while timeout remains unknown without retry', () async {
    final repository = _Repository(
      runs: <AutomationRun>[_run(90, AutomationRunStatus.success)],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await controller.load();

    repository.toggleFailure = const ApiFailure(
      ApiFailureKind.http,
      requestId: 'safe-conflict',
      statusCode: 409,
    );
    await controller.setEnabled(repository.task, enabled: false);
    expect(
      controller.actionFor(7).knownFailure?.kind,
      StateFailureKind.conflict,
    );

    repository.toggleFailure = null;
    repository.runFailure = const ApiFailure(
      ApiFailureKind.timeout,
      requestId: 'safe-timeout',
    );
    await controller.runNow(repository.task);
    expect(controller.actionFor(7).isUnknownOutcome, isTrue);
    expect(repository.runCalls, 1);

    await controller.refresh();
    expect(controller.actionFor(7).isUnknownOutcome, isTrue);

    repository.runFailure = const ApiFailure(
      ApiFailureKind.network,
      requestId: 'safe-network',
    );
    await controller.runNow(repository.task);
    expect(controller.actionFor(7).isUnknownOutcome, isTrue);
    expect(repository.runCalls, 2);

    repository.runs = <AutomationRun>[
      _run(92, AutomationRunStatus.running),
      _run(90, AutomationRunStatus.success),
    ];
    await controller.refresh();
    expect(controller.actionFor(7).operationId, '92');
    expect(controller.actionFor(7).reconciling, isTrue);
  });

  test('session load restores queued, running, and finished states', () async {
    final repository = _Repository(
      runs: <AutomationRun>[_run(93, AutomationRunStatus.failed)],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.actionFor(7).status, ActionStatus.failed);

    repository.runs = <AutomationRun>[
      _run(94, AutomationRunStatus.queued),
      _run(93, AutomationRunStatus.failed),
    ];
    await controller.refresh();
    expect(controller.actionFor(7).status, ActionStatus.submitting);
    expect(controller.actionFor(7).operationId, '94');
  });

  test('dispose cancels a write and ignores its late response', () async {
    final repository = _Repository(blockRun: true);
    final controller = _controller(repository);
    await controller.load();
    final pending = controller.runNow(repository.task);
    await Future<void>.delayed(Duration.zero);

    controller.dispose();
    expect(repository.runCancellation!.isCancelled, isTrue);
    repository.runCompleter.complete(_run(91, AutomationRunStatus.queued));
    await pending;
    expect(controller.actionFor(7).operationId, isNull);
  });
}

AutomationController _controller(AutomationRepository repository) =>
    AutomationController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );

final class _Target implements AutomationTaskTarget {
  const _Target(this.id);
  final int id;
}

AutomationTask _task([int id = 7]) => AutomationTask(
  id: id,
  name: 'Daily SMS',
  enabled: true,
  deviceId: 'device-a',
  profileDisplay: '•••• 1234',
  taskType: AutomationTaskType.sms,
  environment: AutomationEnvironment.vowifi,
  intervalDays: 1,
  runTime: '08:30',
  nextRunAt: DateTime.utc(2026, 9, 3),
  target: _Target(id),
);

AutomationRun _run(int id, AutomationRunStatus status, {int taskId = 7}) =>
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

final class _Repository implements AutomationRepository {
  _Repository({this.blockRun = false, List<AutomationRun>? runs})
    : runs = runs ?? <AutomationRun>[];

  final bool blockRun;
  final AutomationTask task = _task();
  AutomationTask? otherTask;
  final Completer<AutomationRun> runCompleter = Completer<AutomationRun>();
  List<AutomationRun> runs;
  Object? runFailure;
  Object? toggleFailure;
  int runCalls = 0;
  RequestCancellation? runCancellation;
  Completer<AutomationRunPage>? nextRuns;
  int? total;
  int? totalAfterDelete;

  @override
  Future<List<AutomationTask>> fetchTasks({
    RequestCancellation? cancellation,
  }) async => <AutomationTask>[task, ?otherTask];

  @override
  Future<AutomationRunPage> fetchRuns({
    required int limit,
    required int offset,
    RequestCancellation? cancellation,
  }) {
    final pending = nextRuns;
    nextRuns = null;
    return pending?.future ??
        Future.value(
          AutomationRunPage(runs: runs, total: total ?? runs.length),
        );
  }

  @override
  Future<AutomationTask> setEnabled(
    AutomationTaskTarget target, {
    required bool enabled,
    RequestCancellation? cancellation,
  }) {
    final failure = toggleFailure;
    if (failure != null) return Future<AutomationTask>.error(failure);
    final selected = (target as _Target).id == task.id ? task : otherTask!;
    return Future<AutomationTask>.value(selected.copyWith(enabled: enabled));
  }

  @override
  Future<void> deleteTask(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) async {
    total = totalAfterDelete ?? total;
    runs = runs.where((run) => run.taskId != task.id).toList();
  }

  @override
  Future<AutomationRun> runNow(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) {
    runCalls += 1;
    runCancellation = cancellation;
    final failure = runFailure;
    if (failure != null) return Future<AutomationRun>.error(failure);
    if (blockRun && !runCompleter.isCompleted) return runCompleter.future;
    final run = _run(
      91,
      AutomationRunStatus.queued,
      taskId: (target as _Target).id,
    );
    runs = [run, ...runs];
    if (total != null) total = total! + 1;
    return Future<AutomationRun>.value(run);
  }
}
