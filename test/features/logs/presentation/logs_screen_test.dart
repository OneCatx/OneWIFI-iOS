import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/one_status_hero.dart';
import 'package:onewifi_android/features/logs/data/logs_repository.dart';
import 'package:onewifi_android/features/logs/domain/log_entry.dart';
import 'package:onewifi_android/features/logs/presentation/logs_screen.dart';
import 'package:onewifi_android/features/logs/state/logs_controller.dart';

void main() {
  testWidgets(
    'first frame calls load() once; loading shows progress and disables 刷新',
    (tester) async {
      await _tall(tester);
      final repository = _Repo()..hold = true;
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(controller));
      expect(repository.calls, hasLength(1));
      expect(repository.calls.single.level, 'warn');
      expect(repository.calls.single.search, '');
      expect(controller.entries.status, QueryStatus.loading);

      await tester.pump();
      expect(find.text('问题日志'), findsOneWidget);
      expect(find.text('历史记录。失败后不会自动重试，点刷新再拉。'), findsOneWidget);
      expect(find.text('过滤'), findsOneWidget);
      expect(find.text('记录'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('警告及以上'), findsOneWidget);
      expect(find.text('仅错误'), findsOneWidget);
      expect(find.text('搜索'), findsOneWidget);
      expect(find.byKey(LogsScreen.searchFieldKey), findsOneWidget);
      expect(_chip(tester, '警告及以上').selected, isTrue);
      expect(_chip(tester, '全部').selected, isFalse);
      expect(_chip(tester, '仅错误').selected, isFalse);
      expect(_progress, findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(_refresh(tester).onPressed, isNull);
      expect(find.text('没有匹配的日志'), findsNothing);
      expect(find.text('日志不可用'), findsNothing);

      repository.pending.single.complete(_sample);
      await tester.pump();
      expect(repository.calls, hasLength(1));
      expect(_progress, findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(_refresh(tester).onPressed, isNotNull);
      expect(find.text('modem reset'), findsOneWidget);
    },
  );

  testWidgets('entries render LEVEL · local time and message, newest first', (
    tester,
  ) async {
    await _tall(tester);
    final controller = _controller(_Repo());
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.text('WARN · 2026-09-06 08:05:03'), findsOneWidget);
    expect(find.text('dhcp lease renewed'), findsOneWidget);
    expect(find.text('ERROR · 2026-09-06 08:06:04'), findsOneWidget);
    expect(find.text('modem reset'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('modem reset')).dy,
      lessThan(tester.getTopLeft(find.text('dhcp lease renewed')).dy),
    );
    expect(find.text('没有匹配的日志'), findsNothing);
    expect(find.text('日志不可用'), findsNothing);
    expect(find.byType(OneStatusHero), findsNothing);
  });

  testWidgets('an empty result shows the 没有匹配的日志 hero', (tester) async {
    await _tall(tester);
    final controller = _controller(_Repo()..result = const <LogEntry>[]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(controller.entries.status, QueryStatus.empty);
    expect(find.text('没有匹配的日志'), findsOneWidget);
    expect(find.text('换过滤条件或稍后再刷新。'), findsOneWidget);
    expect(find.text('注意'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('处理中'), findsOneWidget);
    expect(find.text('就绪'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(_refresh(tester).onPressed, isNotNull);
  });

  testWidgets(
    'search submit, level chips and 刷新 all go through load(); typing alone does not',
    (tester) async {
      await _tall(tester);
      final repository = _Repo();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pump();
      expect(repository.calls, hasLength(1));

      await tester.enterText(find.byKey(LogsScreen.searchFieldKey), 'kernel');
      await tester.pump();
      expect(repository.calls, hasLength(1));
      expect(controller.search, '');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(repository.calls, hasLength(2));
      expect(repository.calls.last.level, 'warn');
      expect(repository.calls.last.search, 'kernel');
      expect(controller.search, 'kernel');

      await tester.tap(find.text('仅错误'));
      await tester.pump();
      expect(repository.calls, hasLength(3));
      expect(repository.calls.last.level, 'error');
      expect(repository.calls.last.search, 'kernel');
      expect(controller.level, 'error');
      expect(_chip(tester, '仅错误').selected, isTrue);
      expect(_chip(tester, '警告及以上').selected, isFalse);

      await tester.tap(find.text('全部'));
      await tester.pump();
      expect(repository.calls, hasLength(4));
      expect(repository.calls.last.level, '');
      expect(_chip(tester, '全部').selected, isTrue);

      await tester.tap(find.text('刷新'));
      await tester.pump();
      expect(repository.calls, hasLength(5));
      expect(repository.calls.last.level, '');
      expect(repository.calls.last.search, 'kernel');
    },
  );

  testWidgets('a failed first load shows the 日志不可用 hero and re-enables 刷新', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repo()
      ..failure = const ApiFailure(
        ApiFailureKind.http,
        requestId: 'logs',
        statusCode: 503,
      );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(controller.entries.status, QueryStatus.failed);
    expect(find.text('日志不可用'), findsOneWidget);
    expect(find.text('这次读取失败。点刷新再试，不要自动连打。'), findsOneWidget);
    expect(find.text('注意'), findsOneWidget);
    expect(find.text('没有匹配的日志'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(_refresh(tester).onPressed, isNotNull);

    await tester.pump(const Duration(seconds: 10));
    expect(repository.calls, hasLength(1));
  });

  testWidgets('a failed refresh hides the stale list behind the hero', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repo();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    expect(find.text('modem reset'), findsOneWidget);

    repository.failure = StateError('gateway down');
    await tester.tap(find.text('刷新'));
    await tester.pump();
    expect(repository.calls, hasLength(2));
    expect(controller.entries.status, QueryStatus.failed);
    expect(controller.entries.isStale, isTrue);
    expect(controller.entries.lastGoodData, same(_sample));
    expect(find.text('日志不可用'), findsOneWidget);
    expect(find.text('modem reset'), findsNothing);
    expect(find.text('dhcp lease renewed'), findsNothing);
    expect(_refresh(tester).onPressed, isNotNull);

    await tester.pump(const Duration(seconds: 10));
    expect(repository.calls, hasLength(2));
  });

  testWidgets(
    'SSE watch arms while mounted and cancels once the screen is gone',
    (tester) async {
      await _tall(tester);
      final repository = _Repo();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pump();
      expect(repository.calls, hasLength(1));
      expect(controller.isLiveStreaming, isTrue);
      expect(find.text('modem reset'), findsOneWidget);

      // No 5s history poll while SSE is live (禁双打).
      await tester.pump(const Duration(seconds: 10));
      expect(repository.calls, hasLength(1));
      expect(controller.isLiveStreaming, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(controller.isLiveStreaming, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(repository.calls, hasLength(1));
      expect(controller.entries.status, QueryStatus.data);
    },
  );

  testWidgets(
    'unmounting while the first load() is in flight leaves no watch behind',
    (tester) async {
      await _tall(tester);
      final repository = _Repo()..hold = true;
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      expect(repository.calls, hasLength(1));
      expect(controller.entries.status, QueryStatus.loading);

      await tester.pumpWidget(const SizedBox());
      expect(find.byType(LogsScreen), findsNothing);

      repository.pending.single.complete(_sample);
      await tester.pump();
      expect(controller.entries.status, QueryStatus.data);

      repository.hold = false;
      await tester.pump(const Duration(seconds: 5));
      expect(repository.calls, hasLength(1));
      await tester.pump(const Duration(seconds: 5));
      expect(repository.calls, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('screen scrolls at 320dp and 200 percent text in both themes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final controller = _controller(_Repo());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          darkTheme: OneTheme.dark(),
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              // 同一用例里换控制器再 pump 时必须换 State：屏幕只在 initState
              // 发首屏 load()，且旧 ListView 会带着滚到底的偏移量留下来。
              body: LogsScreen(
                key: ObjectKey(controller),
                controller: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('问题日志'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('dhcp lease renewed'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('dhcp lease renewed'), findsOneWidget);
      expect(find.text('modem reset'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

Widget _app(LogsController controller) => MaterialApp(
  theme: OneTheme.light(),
  darkTheme: OneTheme.dark(),
  home: Scaffold(body: LogsScreen(controller: controller)),
);

Future<void> _tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

LogsController _controller(LogsRepository repository) =>
    LogsController(repository: repository, requestRegistry: RequestRegistry());

OutlinedButton _refresh(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '刷新'));

FilterChip _chip(WidgetTester tester, String label) =>
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));

/// 框的 Semantics 会把进度标签并进整块瓷片，故按控件而非语义标签找。
final Finder _progress = find.byWidgetPredicate(
  (widget) => widget is OneStatusProgress && widget.label == '正在加载日志',
);

// 直接按本地时区构造，`_format` 里的 toLocal() 就是恒等，文案与机器时区无关。
final List<LogEntry> _sample = <LogEntry>[
  LogEntry(
    time: DateTime(2026, 9, 6, 8, 5, 3),
    level: 'warn',
    message: 'dhcp lease renewed',
  ),
  LogEntry(
    time: DateTime(2026, 9, 6, 8, 6, 4),
    level: 'error',
    message: 'modem reset',
  ),
];

final class _Call {
  const _Call(this.level, this.search);
  final String level;
  final String search;
}

final class _Repo implements LogsRepository {
  List<LogEntry> result = _sample;
  Object? failure;
  bool hold = false;
  final List<_Call> calls = <_Call>[];
  final List<Completer<List<LogEntry>>> pending = <Completer<List<LogEntry>>>[];

  @override
  Future<List<LogEntry>> fetchHistory({
    int lines = 500,
    String level = 'warn',
    String search = '',
    RequestCancellation? cancellation,
  }) {
    calls.add(_Call(level, search));
    if (hold) {
      final gate = Completer<List<LogEntry>>();
      pending.add(gate);
      return gate.future;
    }
    final error = failure;
    if (error != null) return Future<List<LogEntry>>.error(error);
    return Future<List<LogEntry>>.value(result);
  }

  @override
  Future<void> watchLive({
    String level = 'warn',
    required bool Function(LogEntry entry) onEntry,
    RequestCancellation? cancellation,
  }) async {
    if (cancellation != null) {
      await cancellation.whenCancelled;
      throw const ApiFailure(
        ApiFailureKind.cancelled,
        requestId: 'logs-stream',
      );
    }
    await Completer<void>().future;
  }
}
