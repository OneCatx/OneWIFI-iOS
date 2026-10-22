import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/logs/data/logs_repository.dart';
import 'package:onewifi_android/features/logs/domain/log_entry.dart';
import 'package:onewifi_android/features/logs/state/logs_controller.dart';

void main() {
  group('after dispose()', () {
    Future<_Harness> disposed() async {
      final h = _Harness();
      await h.controller.load();
      expect(h.repo.calls, contains('fetchHistory'));
      expect(h.repo.calls, contains('watchLive'));
      expect(h.notifications, greaterThanOrEqualTo(2));
      expect(h.controller.entries.status, QueryStatus.data);
      final notifications = h.notifications;
      h.controller.dispose();
      h.notificationsAtDispose = notifications;
      return h;
    }

    void expectSilent(_Harness h, QueryState<List<LogEntry>> entries) {
      expect(h.notifications, h.notificationsAtDispose);
      expect(h.controller.entries, same(entries));
      expect(h.controller.level, 'warn');
      expect(h.controller.search, '');
    }

    testWidgets('load completes silently and arms no watch', (tester) async {
      final h = await disposed();
      final entries = h.controller.entries;
      await expectLater(h.controller.load(), completes);
      await tester.pump(const Duration(seconds: 10));
      expectSilent(h, entries);
    });

    testWidgets('load with filters completes silently and keeps them', (
      tester,
    ) async {
      final h = await disposed();
      final entries = h.controller.entries;
      await expectLater(
        h.controller.load(level: 'error', search: 'x'),
        completes,
      );
      await tester.pump(const Duration(seconds: 10));
      expectSilent(h, entries);
    });

    testWidgets('startWatching returns normally and arms no watch', (
      tester,
    ) async {
      final h = await disposed();
      final entries = h.controller.entries;
      expect(h.controller.startWatching, returnsNormally);
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expectSilent(h, entries);
    });

    test('stopWatching returns normally', () async {
      final h = await disposed();
      final entries = h.controller.entries;
      expect(h.controller.stopWatching, returnsNormally);
      await pumpEventQueue();
      expectSilent(h, entries);
    });
  });

  group('disposed while a request is in flight', () {
    testWidgets('load: late failure completes silently', (tester) async {
      final h = _Harness();
      h.hold();
      final pending = h.controller.load();
      expect(h.repo.calls, <String>['fetchHistory']);
      expect(h.notifications, 1);
      h.controller.dispose();
      h.fail();
      h.release();
      await expectLater(pending, completes);
      await tester.pump(const Duration(seconds: 10));
      expect(h.notifications, 1);
      expect(h.repo.calls, <String>['fetchHistory']);
      expect(h.controller.entries.status, QueryStatus.loading);
      expect(h.controller.entries.lastGoodData, isNull);
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
    controller = LogsController(
      repository: repo,
      requestRegistry: RequestRegistry(),
    );
    controller.addListener(() => notifications += 1);
    addTearDown(controller.dispose);
  }

  final _Repository repo = _Repository();
  int notifications = 0;
  int notificationsAtDispose = 0;
  late final LogsController controller;
  Completer<void>? _gate;

  void hold() {
    final gate = Completer<void>();
    _gate = gate;
    repo.gate = gate;
  }

  void release() => _gate?.complete();

  void fail() => repo.failure = StateError('boom');
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

final class _Repository implements LogsRepository {
  Completer<void>? gate;
  Object? failure;
  final List<String> calls = <String>[];

  @override
  Future<List<LogEntry>> fetchHistory({
    int lines = 500,
    String level = 'warn',
    String search = '',
    RequestCancellation? cancellation,
  }) async {
    calls.add('fetchHistory');
    final pending = gate;
    if (pending != null) await pending.future;
    final error = failure;
    if (error != null) throw error;
    return _sample;
  }

  @override
  Future<void> watchLive({
    String level = 'warn',
    required bool Function(LogEntry entry) onEntry,
    RequestCancellation? cancellation,
  }) async {
    calls.add('watchLive');
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
