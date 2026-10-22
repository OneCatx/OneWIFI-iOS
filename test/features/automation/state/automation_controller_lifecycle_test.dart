import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/automation/data/automation_repository.dart';
import 'package:onewifi_android/features/automation/domain/automation.dart';
import 'package:onewifi_android/features/automation/state/automation_controller.dart';

void main() {
  const loaded = <String>['fetchTasks', 'fetchRuns'];

  Future<_Harness> loadedHarness() async {
    final h = _Harness();
    await h.controller.load();
    expect(h.repo.calls, loaded);
    expect(h.notifications, 2);
    expect(h.controller.workspace.status, QueryStatus.data);
    expect(h.controller.actionFor(7).status, ActionStatus.idle);
    return h;
  }

  group('after dispose()', () {
    Future<_Harness> disposed() async {
      final h = await loadedHarness();
      h.controller.dispose();
      return h;
    }

    void expectSilent(_Harness h, QueryState<AutomationWorkspace> workspace) {
      expect(h.notifications, 2);
      expect(h.repo.calls, loaded);
      expect(h.controller.workspace, same(workspace));
      expect(h.controller.actionFor(7).status, ActionStatus.idle);
    }

    test('load completes silently', () async {
      final h = await disposed();
      final workspace = h.controller.workspace;
      await expectLater(h.controller.load(), completes);
      expectSilent(h, workspace);
    });

    test('refresh completes silently', () async {
      final h = await disposed();
      final workspace = h.controller.workspace;
      await expectLater(h.controller.refresh(), completes);
      expectSilent(h, workspace);
    });

    test('setEnabled(false) completes silently', () async {
      final h = await disposed();
      final workspace = h.controller.workspace;
      await expectLater(
        h.controller.setEnabled(h.repo.task, enabled: false),
        completes,
      );
      expectSilent(h, workspace);
      expect(h.controller.workspace.lastGoodData!.tasks.single.enabled, isTrue);
    });

    test('deleteTask completes silently', () async {
      final h = await disposed();
      final workspace = h.controller.workspace;
      await expectLater(h.controller.deleteTask(h.repo.task), completes);
      expectSilent(h, workspace);
      expect(h.controller.workspace.lastGoodData!.tasks, hasLength(1));
    });

    test('runNow completes silently', () async {
      final h = await disposed();
      final workspace = h.controller.workspace;
      await expectLater(h.controller.runNow(h.repo.task), completes);
      expectSilent(h, workspace);
      expect(h.controller.workspace.lastGoodData!.runs, isEmpty);
    });
  });

  group('disposed while a request is in flight', () {
    test('load: late fetchTasks success completes silently', () async {
      final h = _Harness();
      h.hold('fetchTasks');
      final pending = h.controller.load();
      expect(h.repo.calls, <String>['fetchTasks']);
      expect(h.notifications, 1);
      h.controller.dispose();
      h.release();
      await expectLater(pending, completes);
      expect(h.notifications, 1);
      expect(h.controller.workspace.status, QueryStatus.loading);
      expect(h.controller.workspace.lastGoodData, isNull);
    });

    test('load: late fetchTasks failure completes silently', () async {
      final h = _Harness();
      h.hold('fetchTasks');
      final pending = h.controller.load();
      expect(h.repo.calls, <String>['fetchTasks']);
      expect(h.notifications, 1);
      h.controller.dispose();
      h.fail();
      h.release();
      await expectLater(pending, completes);
      expect(h.notifications, 1);
      expect(h.repo.calls, <String>['fetchTasks']);
      expect(h.controller.workspace.status, QueryStatus.loading);
    });

    test('load: late fetchTasks success sends no fetchRuns', () async {
      final h = _Harness();
      h.hold('fetchTasks');
      final pending = h.controller.load();
      expect(h.repo.calls, <String>['fetchTasks']);
      expect(h.notifications, 1);
      h.controller.dispose();
      h.release();
      await expectLater(pending, completes);
      expect(h.repo.calls, <String>['fetchTasks']);
      expect(h.notifications, 1);
      expect(h.controller.workspace.status, QueryStatus.loading);
      expect(h.controller.workspace.lastGoodData, isNull);
    });

    test('load: late fetchRuns success completes silently', () async {
      final h = _Harness();
      h.hold('fetchRuns');
      final pending = h.controller.load();
      await pumpEventQueue();
      expect(h.repo.calls, loaded);
      expect(h.notifications, 1);
      h.controller.dispose();
      h.release();
      await expectLater(pending, completes);
      expect(h.notifications, 1);
      expect(h.repo.calls, loaded);
      expect(h.controller.workspace.status, QueryStatus.loading);
      expect(h.controller.workspace.lastGoodData, isNull);
    });

    test('load: late fetchRuns failure completes silently', () async {
      final h = _Harness();
      h.hold('fetchRuns');
      final pending = h.controller.load();
      await pumpEventQueue();
      expect(h.repo.calls, loaded);
      expect(h.notifications, 1);
      h.controller.dispose();
      h.fail();
      h.release();
      await expectLater(pending, completes);
      expect(h.notifications, 1);
      expect(h.repo.calls, loaded);
      expect(h.controller.workspace.status, QueryStatus.loading);
    });

    test('setEnabled: late success completes silently', () async {
      final h = await loadedHarness();
      h.hold('setEnabled');
      final pending = h.controller.setEnabled(h.repo.task, enabled: false);
      expect(h.repo.calls, <String>[...loaded, 'setEnabled']);
      expect(h.notifications, 3);
      expect(h.controller.actionFor(7).status, ActionStatus.submitting);
      h.controller.dispose();
      h.release();
      await expectLater(pending, completes);
      expect(h.notifications, 3);
      expect(h.repo.calls, <String>[...loaded, 'setEnabled']);
      expect(h.controller.workspace.lastGoodData!.tasks.single.enabled, isTrue);
      expect(h.controller.actionFor(7).status, ActionStatus.submitting);
    });

    test('deleteTask: late success completes silently', () async {
      final h = await loadedHarness();
      h.hold('deleteTask');
      final pending = h.controller.deleteTask(h.repo.task);
      expect(h.repo.calls, <String>[...loaded, 'deleteTask']);
      expect(h.notifications, 3);
      expect(h.controller.actionFor(7).status, ActionStatus.submitting);
      h.controller.dispose();
      h.release();
      await expectLater(pending, completes);
      expect(h.notifications, 3);
      expect(h.repo.calls, <String>[...loaded, 'deleteTask']);
      expect(h.controller.workspace.lastGoodData!.tasks, hasLength(1));
      expect(h.controller.actionFor(7).status, ActionStatus.submitting);
    });

    test('runNow: late failure completes silently', () async {
      final h = await loadedHarness();
      h.hold('runNow');
      final pending = h.controller.runNow(h.repo.task);
      expect(h.repo.calls, <String>[...loaded, 'runNow']);
      expect(h.notifications, 3);
      expect(h.controller.actionFor(7).status, ActionStatus.submitting);
      h.controller.dispose();
      h.fail();
      h.release();
      await expectLater(pending, completes);
      expect(h.notifications, 3);
      expect(h.repo.calls, <String>[...loaded, 'runNow']);
      expect(h.controller.workspace.lastGoodData!.runs, isEmpty);
      expect(h.controller.actionFor(7).status, ActionStatus.submitting);
    });
  });

  group('dispose() twice', () {
    test('second dispose() returns normally without a notification', () {
      final h = _Harness();
      h.controller.dispose();
      expect(h.controller.dispose, returnsNormally);
      expect(h.notifications, 0);
    });
  });
}

final class _Harness {
  _Harness() {
    controller = AutomationController(
      repository: repo,
      requestRegistry: RequestRegistry(),
    );
    controller.addListener(() => notifications += 1);
    addTearDown(controller.dispose);
  }

  final _Repository repo = _Repository();
  int notifications = 0;
  late final AutomationController controller;

  void hold(String name) => repo.gates[name] = Completer<void>();

  void release() {
    for (final gate in repo.gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  void fail() => repo.failure = StateError('boom');
}

final class _Target implements AutomationTaskTarget {
  const _Target();
}

AutomationTask _task() => AutomationTask(
  id: 7,
  name: 'Daily SMS',
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

AutomationRun _run(int id, AutomationRunStatus status) => AutomationRun(
  id: id,
  taskId: 7,
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
  final AutomationTask task = _task();
  final Map<String, Completer<void>> gates = <String, Completer<void>>{};
  Object? failure;
  final List<String> calls = <String>[];

  Future<T> _respond<T>(String name, T Function() result) async {
    calls.add(name);
    final gate = gates[name];
    if (gate != null) await gate.future;
    final error = failure;
    if (error != null) throw error;
    return result();
  }

  @override
  Future<List<AutomationTask>> fetchTasks({
    RequestCancellation? cancellation,
  }) => _respond<List<AutomationTask>>(
    'fetchTasks',
    () => <AutomationTask>[task],
  );

  @override
  Future<AutomationRunPage> fetchRuns({
    required int limit,
    required int offset,
    RequestCancellation? cancellation,
  }) => _respond<AutomationRunPage>(
    'fetchRuns',
    () => const AutomationRunPage(runs: <AutomationRun>[], total: 0),
  );

  @override
  Future<AutomationTask> setEnabled(
    AutomationTaskTarget target, {
    required bool enabled,
    RequestCancellation? cancellation,
  }) => _respond<AutomationTask>(
    'setEnabled',
    () => task.copyWith(enabled: enabled),
  );

  @override
  Future<void> deleteTask(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) => _respond<void>('deleteTask', () {});

  @override
  Future<AutomationRun> runNow(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) => _respond<AutomationRun>(
    'runNow',
    () => _run(91, AutomationRunStatus.queued),
  );
}
