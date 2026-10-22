import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';
import 'package:onewifi_android/features/logs/data/logs_repository.dart';
import 'package:onewifi_android/features/logs/domain/log_entry.dart';
import 'package:onewifi_android/features/logs/state/logs_controller.dart';

/// 每次 notifyListeners 时的 (status, lastGoodData 条数, isStale) 快照。
typedef _Snap = (QueryStatus, int?, bool);

void main() {
  testWidgets(
    'load() defaults to warn/"" , publishes loading→data and opens SSE watch',
    (tester) async {
      final repository = _Repo();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      final log = _record(controller);

      expect(controller.entries.status, QueryStatus.initial);
      expect(controller.entries.key, 'logs.history');
      expect(controller.level, 'warn');
      expect(controller.search, '');

      await controller.load();
      expect(repository.historyCalls, hasLength(1));
      expect(repository.historyCalls.single.level, 'warn');
      expect(repository.historyCalls.single.search, '');
      expect(repository.historyCalls.single.cancellation, isNotNull);
      expect(repository.historyCalls.single.cancellation!.isCancelled, isFalse);
      expect(controller.entries.status, QueryStatus.data);
      expect(controller.entries.lastGoodData, same(_sample));
      expect(controller.entries.isStale, isFalse);
      expect(controller.entries.failure, isNull);
      expect(controller.isLiveStreaming, isTrue);
      expect(repository.streamCalls, hasLength(1));
      expect(repository.streamCalls.single.level, 'warn');
      expect(log, <_Snap>[
        (QueryStatus.loading, null, false),
        (QueryStatus.data, 2, false),
      ]);

      // No 5s history poll while SSE is live (禁双打).
      await tester.pump(const Duration(seconds: 10));
      expect(repository.historyCalls, hasLength(1));
      expect(repository.streamCalls, hasLength(1));

      controller.stopWatching();
      expect(controller.isLiveStreaming, isFalse);
      expect(repository.streamCalls.single.cancellation!.isCancelled, isTrue);
      controller.dispose();
    },
  );

  testWidgets('load(level:, search:) forwards both and remembers them', (
    tester,
  ) async {
    final repository = _Repo();
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await controller.load(level: 'error', search: 'kernel');
    expect(controller.level, 'error');
    expect(controller.search, 'kernel');
    expect(repository.historyCalls.single.level, 'error');
    expect(repository.historyCalls.single.search, 'kernel');
    expect(repository.streamCalls.single.level, 'error');

    await controller.load(level: '');
    expect(controller.level, '');
    expect(controller.search, 'kernel');
    expect(repository.historyCalls.last.level, '');
    expect(repository.historyCalls.last.search, 'kernel');

    await controller.load(search: '');
    expect(controller.level, '');
    expect(controller.search, '');
    expect(repository.historyCalls, hasLength(3));
    expect(repository.historyCalls.last.level, '');
    expect(repository.historyCalls.last.search, '');
    controller.dispose();
  });

  testWidgets('an empty page publishes empty without data and still watches', (
    tester,
  ) async {
    final repository = _Repo()..historyResult = const <LogEntry>[];
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    final log = _record(controller);

    await controller.load();
    expect(controller.entries.status, QueryStatus.empty);
    expect(controller.entries.lastGoodData, isNull);
    expect(controller.entries.isStale, isFalse);
    expect(controller.isLiveStreaming, isTrue);
    expect(log, <_Snap>[
      (QueryStatus.loading, null, false),
      (QueryStatus.empty, null, false),
    ]);

    await tester.pump(const Duration(seconds: 10));
    expect(repository.historyCalls, hasLength(1));
    controller.dispose();
  });

  testWidgets(
    'a failing first load publishes failed without data and never watches',
    (tester) async {
      final repository = _Repo()
        ..historyFailure = const ApiFailure(
          ApiFailureKind.http,
          requestId: 'logs',
          statusCode: 503,
        );
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      final log = _record(controller);

      await controller.load();
      expect(controller.entries.status, QueryStatus.failed);
      expect(controller.entries.lastGoodData, isNull);
      expect(controller.entries.isStale, isFalse);
      expect(controller.entries.failure!.kind, StateFailureKind.unavailable);
      expect(controller.entries.failure!.statusCode, 503);
      expect(controller.isLiveStreaming, isFalse);
      expect(repository.streamCalls, isEmpty);
      expect(log, <_Snap>[
        (QueryStatus.loading, null, false),
        (QueryStatus.failed, null, false),
      ]);

      await tester.pump(const Duration(seconds: 10));
      expect(repository.historyCalls, hasLength(1));
      controller.dispose();
    },
  );

  testWidgets(
    'a failure after data keeps the old list as stale and stops the watch',
    (tester) async {
      final repository = _Repo();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      final log = _record(controller);

      await controller.load();
      expect(controller.isLiveStreaming, isTrue);
      repository.historyFailure = StateError('gateway down');
      await controller.load();
      expect(controller.entries.status, QueryStatus.failed);
      expect(controller.entries.lastGoodData, same(_sample));
      expect(controller.entries.isStale, isTrue);
      expect(controller.entries.failure!.kind, StateFailureKind.generic);
      expect(controller.isLiveStreaming, isFalse);
      expect(log, <_Snap>[
        (QueryStatus.loading, null, false),
        (QueryStatus.data, 2, false),
        (QueryStatus.refreshing, 2, false),
        (QueryStatus.failed, 2, true),
      ]);

      await tester.pump(const Duration(seconds: 10));
      expect(repository.historyCalls, hasLength(2));

      repository.historyFailure = null;
      await controller.load();
      expect(repository.historyCalls, hasLength(3));
      expect(controller.entries.status, QueryStatus.data);
      expect(controller.entries.isStale, isFalse);
      expect(controller.isLiveStreaming, isTrue);
      expect(log.skip(4), <_Snap>[
        (QueryStatus.refreshing, 2, false),
        (QueryStatus.data, 2, false),
      ]);
      controller.dispose();
    },
  );

  testWidgets(
    'SSE onEntry appends without a second history fetch',
    (tester) async {
      final repository = _Repo();
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      await controller.load();
      expect(repository.historyCalls, hasLength(1));
      expect(repository.streamCalls, hasLength(1));

      final live = LogEntry(
        time: DateTime(2026, 9, 6, 8, 7, 5),
        level: 'warn',
        message: 'sse tick',
      );
      repository.emit(live);
      await tester.pump();
      expect(controller.entries.lastGoodData, hasLength(3));
      expect(controller.entries.lastGoodData!.last.message, 'sse tick');
      expect(repository.historyCalls, hasLength(1));

      controller.dispose();
    },
  );

  testWidgets(
    'search filter drops non-matching SSE entries client-side',
    (tester) async {
      final repository = _Repo();
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      await controller.load(search: 'kernel');
      repository.emit(
        LogEntry(
          time: DateTime(2026, 9, 6, 8, 7, 5),
          level: 'warn',
          message: 'unrelated',
        ),
      );
      await tester.pump();
      expect(controller.entries.lastGoodData, same(_sample));

      repository.emit(
        LogEntry(
          time: DateTime(2026, 9, 6, 8, 7, 6),
          level: 'warn',
          message: 'kernel oops',
        ),
      );
      await tester.pump();
      expect(controller.entries.lastGoodData, hasLength(3));
      expect(controller.entries.lastGoodData!.last.message, 'kernel oops');
      controller.dispose();
    },
  );

  testWidgets(
    'startWatching is idempotent before and after load',
    (tester) async {
      final repository = _Repo();
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      controller.startWatching();
      await tester.pump();
      expect(repository.streamCalls, isEmpty);
      expect(controller.entries.status, QueryStatus.initial);

      await controller.load();
      controller.startWatching();
      controller.startWatching();
      expect(repository.streamCalls, hasLength(1));
      await tester.pump(const Duration(seconds: 10));
      expect(repository.historyCalls, hasLength(1));
      controller.dispose();
    },
  );

  testWidgets(
    'a response arriving after dispose is dropped without notifying',
    (tester) async {
      final repository = _Repo()..holdHistory = true;
      final controller = _controller(repository);
      final log = _record(controller);

      final load = controller.load();
      expect(repository.historyCalls, hasLength(1));
      expect(controller.entries.status, QueryStatus.loading);
      expect(log, hasLength(1));

      controller.dispose();
      expect(repository.historyCalls.single.cancellation!.isCancelled, isTrue);

      repository.pendingHistory.single.complete(_sample);
      await load;
      await tester.pump();
      expect(log, hasLength(1));
      expect(controller.entries.status, QueryStatus.loading);
      expect(controller.entries.lastGoodData, isNull);
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );

  testWidgets(
    'two overlapping loads: the first answer is ignored, the second lands',
    (tester) async {
      final repository = _Repo()..holdHistory = true;
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      final log = _record(controller);

      final first = controller.load();
      final second = controller.load(search: 'kernel');
      expect(repository.historyCalls, hasLength(2));
      expect(repository.historyCalls[0].search, '');
      expect(repository.historyCalls[1].search, 'kernel');
      expect(repository.historyCalls[0].cancellation!.isCancelled, isTrue);
      expect(repository.historyCalls[1].cancellation!.isCancelled, isFalse);
      expect(controller.entries.status, QueryStatus.loading);

      repository.pendingHistory[0].complete(_sample);
      await first;
      expect(controller.entries.status, QueryStatus.loading);
      expect(controller.entries.lastGoodData, isNull);

      repository.pendingHistory[1].complete(<LogEntry>[_sample.first]);
      await second;
      expect(controller.entries.status, QueryStatus.data);
      expect(controller.entries.lastGoodData, hasLength(1));
      expect(controller.isLiveStreaming, isTrue);
      expect(log, <_Snap>[
        (QueryStatus.loading, null, false),
        (QueryStatus.loading, null, false),
        (QueryStatus.data, 1, false),
      ]);

      repository.holdHistory = false;
      await tester.pump(const Duration(seconds: 10));
      expect(repository.historyCalls, hasLength(2));
      controller.dispose();
    },
  );

  testWidgets(
    'stopWatching() while load() is in flight keeps the watch off once it lands',
    (tester) async {
      final repository = _Repo()..holdHistory = true;
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      final load = controller.load();
      expect(repository.historyCalls, hasLength(1));
      expect(controller.entries.status, QueryStatus.loading);

      controller.stopWatching();

      repository.pendingHistory.single.complete(_sample);
      await load;
      expect(controller.entries.status, QueryStatus.data);
      expect(controller.entries.lastGoodData, same(_sample));
      expect(controller.isLiveStreaming, isFalse);

      await tester.pump(const Duration(seconds: 10));
      expect(repository.historyCalls, hasLength(1));
      expect(repository.streamCalls, isEmpty);
      controller.dispose();
    },
  );

  testWidgets(
    'startWatching() after a mid-flight stopWatching() still arms the watch',
    (tester) async {
      final repository = _Repo()..holdHistory = true;
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      final load = controller.load();
      expect(repository.historyCalls, hasLength(1));

      controller.stopWatching();
      controller.startWatching();

      repository.pendingHistory.single.complete(_sample);
      await load;
      expect(controller.entries.status, QueryStatus.data);
      expect(controller.isLiveStreaming, isTrue);
      expect(repository.streamCalls, hasLength(1));
      controller.dispose();
    },
  );
}

LogsController _controller(LogsRepository repository) =>
    LogsController(repository: repository, requestRegistry: RequestRegistry());

List<_Snap> _record(LogsController controller) {
  final log = <_Snap>[];
  controller.addListener(() {
    final entries = controller.entries;
    log.add((entries.status, entries.lastGoodData?.length, entries.isStale));
  });
  return log;
}

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

final class _HistoryCall {
  const _HistoryCall(this.level, this.search, this.cancellation);
  final String level;
  final String search;
  final RequestCancellation? cancellation;
}

final class _StreamCall {
  _StreamCall(this.level, this.cancellation);
  final String level;
  final RequestCancellation? cancellation;
  final StreamController<LogEntry> events = StreamController<LogEntry>();
}

final class _Repo implements LogsRepository {
  List<LogEntry> historyResult = _sample;
  Object? historyFailure;

  /// 为 true 时每次 history 调用都挂在一个新的 [Completer] 上。
  bool holdHistory = false;
  final List<_HistoryCall> historyCalls = <_HistoryCall>[];
  final List<Completer<List<LogEntry>>> pendingHistory =
      <Completer<List<LogEntry>>>[];
  final List<_StreamCall> streamCalls = <_StreamCall>[];

  void emit(LogEntry entry) {
    for (final call in streamCalls) {
      if (!(call.cancellation?.isCancelled ?? false)) {
        call.events.add(entry);
      }
    }
  }

  @override
  Future<List<LogEntry>> fetchHistory({
    int lines = 500,
    String level = 'warn',
    String search = '',
    RequestCancellation? cancellation,
  }) {
    historyCalls.add(_HistoryCall(level, search, cancellation));
    if (holdHistory) {
      final gate = Completer<List<LogEntry>>();
      pendingHistory.add(gate);
      return gate.future;
    }
    final error = historyFailure;
    if (error != null) return Future<List<LogEntry>>.error(error);
    return Future<List<LogEntry>>.value(historyResult);
  }

  @override
  Future<void> watchLive({
    String level = 'warn',
    required bool Function(LogEntry entry) onEntry,
    RequestCancellation? cancellation,
  }) async {
    final call = _StreamCall(level, cancellation);
    streamCalls.add(call);
    final sub = call.events.stream.listen((entry) {
      if (!onEntry(entry)) {
        unawaited(call.events.close());
      }
    });
    try {
      await Future.any<void>(<
        Future<void>
      >[
        call.events.done,
        if (cancellation != null) cancellation.whenCancelled,
      ]);
    } finally {
      await sub.cancel();
      if (!call.events.isClosed) {
        await call.events.close();
      }
      if (cancellation?.isCancelled ?? false) {
        throw const ApiFailure(
          ApiFailureKind.cancelled,
          requestId: 'logs-stream',
        );
      }
    }
  }
}
