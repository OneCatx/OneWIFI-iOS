import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/console_layout.dart';
import 'package:onewifi_android/design/widgets/glass_dialog.dart';
import 'package:onewifi_android/features/automation/data/automation_repository.dart';
import 'package:onewifi_android/features/automation/domain/automation.dart';
import 'package:onewifi_android/features/automation/presentation/automation_screen.dart';
import 'package:onewifi_android/features/automation/state/automation_controller.dart';

void main() {
  testWidgets('run-now confirms, queues once, and disables same-task writes', (
    tester,
  ) async {
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(AutomationScreen(controller: controller)));
    await tester.pumpAndSettle();

    await _reveal(tester, _action('立即执行'));
    await tester.tap(_action('立即执行'));
    await tester.pumpAndSettle();
    expect(find.byType(OneGlassDialog), findsOneWidget);
    expect(repository.runCalls, 0);
    await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
    await tester.pumpAndSettle();

    expect(repository.runCalls, 1);
    expect(find.text('已排队 · 等待记录回来'), findsOneWidget);
    expect(tester.widget<GlassActionButton>(_action('立即执行')).onPressed, isNull);
    expect(tester.widget<GlassActionButton>(_action('删除')).onPressed, isNull);
  });

  testWidgets('toggle and delete require confirmation', (tester) async {
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(AutomationScreen(controller: controller)));
    await tester.pumpAndSettle();

    await _reveal(tester, find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(OneGlassDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.toggleCalls, 0);

    await _reveal(tester, _action('删除'));
    await tester.tap(_action('删除'));
    await tester.pumpAndSettle();
    expect(find.byType(OneGlassDialog), findsOneWidget);
    await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 1);
  });

  testWidgets('tasks without a schedule or profile still render', (
    tester,
  ) async {
    final repository = _Repository(
      task: AutomationTask(
        id: 8,
        name: 'Legacy',
        enabled: false,
        deviceId: 'device-a',
        profileDisplay: '—',
        taskType: AutomationTaskType.call,
        environment: AutomationEnvironment.cellular,
        intervalDays: 0,
        runTime: '',
        nextRunAt: null,
        target: const _Target(),
      ),
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(AutomationScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('Legacy'), findsOneWidget);
    expect(find.text('ICCID —'), findsOneWidget);
    expect(find.text('已停用'), findsOneWidget);
    expect(find.text('拨打电话（已下线）'), findsOneWidget);
    expect(find.text('立即执行'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('run history and actions remain reachable at 320dp and 200%', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Repository(
      runs: <AutomationRun>[
        _run(90, AutomationRunStatus.success),
        _run(89, AutomationRunStatus.failed),
      ],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 760),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(body: AutomationScreen(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final delete = find.widgetWithText(
      GlassActionButton,
      '删除',
      skipOffstage: false,
    );
    await _reveal(tester, delete);
    expect(delete.hitTestable(), findsOneWidget);
    await _reveal(tester, find.text('Run #90', skipOffstage: false));
    expect(find.text('Run #90'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _action(String label) => find.widgetWithText(GlassActionButton, label);

/// 列表懒构建，先滚到目标再点；不在树里就一屏一屏往下翻。
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Widget _app(Widget child) => MaterialApp(
  theme: OneTheme.light(),
  darkTheme: OneTheme.dark(),
  home: Scaffold(body: child),
);

AutomationController _controller(AutomationRepository repository) =>
    AutomationController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );

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
  startedAt: DateTime.utc(2026, 9, 2, 1, 0, 2),
  finishedAt:
      status == AutomationRunStatus.success ||
          status == AutomationRunStatus.failed
      ? DateTime.utc(2026, 9, 2, 1, 1)
      : null,
  status: status,
  attempts: 1,
  output: status == AutomationRunStatus.success ? 'completed' : '',
  error: status == AutomationRunStatus.failed ? 'failed safely' : '',
);

final class _Repository implements AutomationRepository {
  _Repository({List<AutomationRun>? runs, AutomationTask? task})
    : runs = runs ?? <AutomationRun>[],
      task = task ?? _task();

  final AutomationTask task;
  List<AutomationRun> runs;
  int runCalls = 0;
  int deleteCalls = 0;
  int toggleCalls = 0;

  @override
  Future<List<AutomationTask>> fetchTasks({
    RequestCancellation? cancellation,
  }) async => <AutomationTask>[task];

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
  }) async {
    toggleCalls += 1;
    return task.copyWith(enabled: enabled);
  }

  @override
  Future<void> deleteTask(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) async {
    deleteCalls += 1;
  }

  @override
  Future<AutomationRun> runNow(
    AutomationTaskTarget target, {
    RequestCancellation? cancellation,
  }) async {
    runCalls += 1;
    return AutomationRun(
      id: 91,
      taskId: 7,
      deviceId: 'device-a',
      scheduledAt: DateTime.now().toUtc(),
      startedAt: null,
      finishedAt: null,
      status: AutomationRunStatus.queued,
      attempts: 0,
      output: '',
      error: '',
    );
  }
}
