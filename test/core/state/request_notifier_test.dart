import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/http/request_slot.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/request_notifier.dart';

void main() {
  group('publish', () {
    test('assigns then notifies exactly once', () {
      final p = _Probe();
      p.bump();
      expect(p.value, 1);
      expect(p.notifications, 1);
    });

    test('is silent after dispose', () {
      final p = _Probe();
      p.dispose();
      p.bump();
      expect(p.value, 0);
      expect(p.notifications, 0);
    });
  });

  group('dispose', () {
    test('closes every slot so live tickets stop being current', () {
      final p = _Probe();
      final read = p.read.begin();
      final write = p.write.begin();
      expect(read.isCurrent, isTrue);
      expect(write.isCurrent, isTrue);
      p.dispose();
      expect(p.isDisposed, isTrue);
      expect(read.isCurrent, isFalse);
      expect(write.isCurrent, isFalse);
      expect(read.cancellation.isCancelled, isTrue);
      expect(write.cancellation.isCancelled, isTrue);
    });

    test('second call returns normally without a notification', () {
      final p = _Probe();
      p.dispose();
      expect(p.dispose, returnsNormally);
      expect(p.notifications, 0);
    });
  });

  group('runQuery', () {
    test('first load goes loading → data and keeps the slot key', () async {
      final p = _Probe();
      final seen = <QueryStatus>[];
      p.addListener(() => seen.add(p.query.status));
      await p.load((_) async => 'alpha');
      expect(seen, <QueryStatus>[QueryStatus.loading, QueryStatus.data]);
      expect(p.query.lastGoodData, 'alpha');
      expect(p.query.key, 'probe.read');
      expect(p.notifications, 2);
    });

    test('reload keeps previous data while refreshing', () async {
      final p = _Probe();
      await p.load((_) async => 'alpha');
      final seen = <QueryState<String>>[];
      p.addListener(() => seen.add(p.query));
      await p.load((_) async => 'beta');
      expect(seen, hasLength(2));
      expect(seen[0].status, QueryStatus.refreshing);
      expect(seen[0].lastGoodData, 'alpha');
      expect(seen[1].status, QueryStatus.data);
      expect(seen[1].lastGoodData, 'beta');
    });

    test('isEmpty maps the value to the empty state', () async {
      final p = _Probe();
      await p.load((_) async => '', isEmpty: (value) => value.isEmpty);
      expect(p.query.status, QueryStatus.empty);
      expect(p.query.lastGoodData, isNull);
      expect(p.query.key, 'probe.read');
    });

    test(
      'failure becomes failedAfter with previous data marked stale',
      () async {
        final p = _Probe();
        await p.load((_) async => 'alpha');
        await p.load((_) async => throw StateError('boom'));
        expect(p.query.status, QueryStatus.failed);
        expect(p.query.lastGoodData, 'alpha');
        expect(p.query.isStale, isTrue);
        expect(p.query.failure, isNotNull);
        expect(p.notifications, 4);
      },
    );

    test('failure without previous data is not stale', () async {
      final p = _Probe();
      await p.load((_) async => throw StateError('boom'));
      expect(p.query.status, QueryStatus.failed);
      expect(p.query.lastGoodData, isNull);
      expect(p.query.isStale, isFalse);
    });

    test('a superseded fetch never writes state', () async {
      final p = _Probe();
      final gate = Completer<String>();
      final first = p.load((_) => gate.future);
      final second = p.load((_) async => 'second');
      await second;
      expect(p.query.lastGoodData, 'second');
      final before = p.notifications;
      gate.complete('first');
      await first;
      expect(p.query.lastGoodData, 'second');
      expect(p.notifications, before);
    });

    test('hands the fetch a ticket whose cancellation is live', () async {
      final p = _Probe();
      RequestTicket? captured;
      await p.load((ticket) async {
        captured = ticket;
        expect(ticket.isCurrent, isTrue);
        expect(ticket.cancellation.isCancelled, isFalse);
        return 'alpha';
      });
      expect(captured, isNotNull);
      expect(captured!.key, 'probe.read');
    });

    test('silent skips pending and swallows failure', () async {
      final p = _Probe();
      await p.load((_) async => 'alpha');
      final before = p.notifications;
      await p.load((_) async => throw StateError('boom'), silent: true);
      expect(p.query.status, QueryStatus.data);
      expect(p.query.lastGoodData, 'alpha');
      expect(p.notifications, before);
      await p.load((_) async => 'beta', silent: true);
      expect(p.query.lastGoodData, 'beta');
      expect(p.notifications, before + 1);
    });

    test('onData runs after the data write and is awaited', () async {
      final p = _Probe();
      final order = <String>[];
      p.addListener(() => order.add('notify:${p.query.status.name}'));
      await p.load(
        (_) async => 'alpha',
        onData: (value, ticket) async {
          order.add('onData:$value:${ticket.isCurrent}');
          await Future<void>.delayed(Duration.zero);
          order.add('onData:done');
        },
      );
      expect(order, <String>[
        'notify:loading',
        'notify:data',
        'onData:alpha:true',
        'onData:done',
      ]);
    });

    test('after dispose the fetch is never called', () async {
      final p = _Probe();
      p.dispose();
      var calls = 0;
      await p.load((_) async {
        calls += 1;
        return 'alpha';
      });
      expect(calls, 0);
      expect(p.notifications, 0);
    });

    test(
      'dispose while in flight leaves the pending state untouched',
      () async {
        final p = _Probe();
        final gate = Completer<String>();
        final pending = p.load((_) => gate.future);
        expect(p.query.status, QueryStatus.loading);
        p.dispose();
        gate.completeError(StateError('late'));
        await expectLater(pending, completes);
        expect(p.query.status, QueryStatus.loading);
        expect(p.notifications, 1);
      },
    );
  });

  group('runAction', () {
    test('default path goes submitting → succeeded and returns true', () async {
      final p = _Probe();
      final seen = <ActionStatus>[];
      p.addListener(() => seen.add(p.action.status));
      final ok = await p.act<int>((_) async => 1);
      expect(ok, isTrue);
      expect(seen, <ActionStatus>[
        ActionStatus.submitting,
        ActionStatus.succeeded,
      ]);
      expect(p.notifications, 2);
    });

    test('refuses to start while already submitting', () async {
      final p = _Probe();
      final gate = Completer<int>();
      final first = p.act<int>((_) => gate.future);
      var secondCalls = 0;
      final second = await p.act<int>((_) async {
        secondCalls += 1;
        return 2;
      });
      expect(second, isFalse);
      expect(secondCalls, 0);
      gate.complete(1);
      expect(await first, isTrue);
    });

    test('onSuccess returning null leaves the state alone', () async {
      final p = _Probe();
      final ok = await p.act<int>((_) async => 1, onSuccess: (_, _) => null);
      expect(ok, isTrue);
      expect(p.action.status, ActionStatus.submitting);
      expect(p.notifications, 1);
    });

    test('onSuccess may return a custom terminal state', () async {
      final p = _Probe();
      final ok = await p.act<int>(
        (_) async => 1,
        onSuccess: (result, _) => ActionState.succeeded(operationId: '$result'),
      );
      expect(ok, isTrue);
      expect(p.action.status, ActionStatus.succeeded);
      expect(p.action.operationId, '1');
    });

    test('an async onSuccess is awaited before the terminal write', () async {
      final p = _Probe();
      final order = <String>[];
      p.addListener(() => order.add('notify:${p.action.status.name}'));
      await p.act<int>(
        (_) async => 1,
        onSuccess: (_, _) async {
          order.add('onSuccess');
          await Future<void>.delayed(Duration.zero);
          return const ActionState.succeeded();
        },
      );
      expect(order, <String>[
        'notify:submitting',
        'onSuccess',
        'notify:succeeded',
      ]);
    });

    test('failure writes fromError then calls onFailure', () async {
      final p = _Probe();
      final order = <String>[];
      p.addListener(() => order.add('notify:${p.action.status.name}'));
      final ok = await p.act<int>(
        (_) async => throw StateError('boom'),
        onFailure: (error) => order.add('onFailure:${error.runtimeType}'),
      );
      expect(ok, isFalse);
      expect(p.action.status, ActionStatus.failed);
      expect(p.action.knownFailure, isNotNull);
      expect(order, <String>[
        'notify:submitting',
        'notify:failed',
        'onFailure:StateError',
      ]);
    });

    test(
      'always runs on success and on failure with the live ticket',
      () async {
        final p = _Probe();
        final keys = <String>[];
        await p.act<int>(
          (_) async => 1,
          always: (ticket) => keys.add(ticket.key),
        );
        await p.act<int>(
          (_) async => throw StateError('boom'),
          always: (ticket) => keys.add(ticket.key),
        );
        expect(keys, <String>['probe.write', 'probe.write']);
      },
    );

    test(
      'dispose in flight: no write, returns false, always still runs',
      () async {
        final p = _Probe();
        final gate = Completer<int>();
        var alwaysCalls = 0;
        final pending = p.act<int>(
          (_) => gate.future,
          always: (_) => alwaysCalls += 1,
        );
        p.dispose();
        gate.complete(1);
        expect(await pending, isFalse);
        expect(p.action.status, ActionStatus.submitting);
        expect(p.notifications, 1);
        expect(alwaysCalls, 1);
      },
    );

    test('custom key and submitting state are honoured', () async {
      final p = _Probe();
      String? seenKey;
      ActionState? seenSubmitting;
      p.addListener(() => seenSubmitting ??= p.action);
      await p.act<int>(
        (ticket) async {
          seenKey = ticket.key;
          return 1;
        },
        key: 'probe.write:custom',
        submitting: const ActionState.submitting(operationId: 'op-1'),
      );
      expect(seenKey, 'probe.write:custom');
      expect(seenSubmitting?.operationId, 'op-1');
    });

    test('void requests work with the default terminal state', () async {
      final p = _Probe();
      final ok = await p.act<void>((_) async {});
      expect(ok, isTrue);
      expect(p.action.status, ActionStatus.succeeded);
    });
  });
}

final class _Probe extends RequestNotifier {
  _Probe() : this._(RequestRegistry());

  _Probe._(RequestRegistry registry)
    : read = RequestSlot(registry, 'probe.read'),
      write = RequestSlot(registry, 'probe.write') {
    addListener(() => notifications += 1);
  }

  final RequestSlot read;
  final RequestSlot write;
  QueryState<String> query = const QueryState<String>.initial(
    key: 'probe.read',
  );
  ActionState action = const ActionState.idle();
  int value = 0;
  int notifications = 0;

  @override
  List<RequestSlot> get slots => <RequestSlot>[read, write];

  void bump() => publish(() => value += 1);

  Future<void> load(
    Future<String> Function(RequestTicket ticket) fetch, {
    bool Function(String value)? isEmpty,
    FutureOr<void> Function(String value, RequestTicket ticket)? onData,
    bool silent = false,
  }) => runQuery<String>(
    slot: read,
    current: () => query,
    set: (next) => publish(() => query = next),
    fetch: fetch,
    isEmpty: isEmpty,
    onData: onData,
    silent: silent,
  );

  Future<bool> act<T>(
    Future<T> Function(RequestTicket ticket) request, {
    String? key,
    ActionState submitting = const ActionState.submitting(),
    FutureOr<ActionState?> Function(T result, RequestTicket ticket)? onSuccess,
    void Function(Object error)? onFailure,
    void Function(RequestTicket ticket)? always,
  }) => runAction<T>(
    slot: write,
    current: () => action,
    set: (next) => publish(() => action = next),
    request: request,
    key: key,
    submitting: submitting,
    onSuccess: onSuccess,
    onFailure: onFailure,
    always: always,
  );
}
