import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/sms/data/sms_repository.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/state/sms_controller.dart';

const ApiFailure _lateFailure = ApiFailure(
  ApiFailureKind.timeout,
  requestId: 'late',
);

const SmsSendResult _delivered = SmsSendResult(
  outcome: SmsSendOutcome.delivered,
  partsTotal: 1,
  partsAccepted: 1,
  retrySafe: false,
);

void main() {
  group('after dispose()', () {
    test('loadContacts() completes silently', () async {
      final h = await _Harness.selected();
      h.dispose();

      await expectLater(h.controller.loadContacts(), completes);

      h.expectSilent();
      expect(h.controller.contacts.status, QueryStatus.data);
    });

    test(
      'selectContact() completes silently and keeps the selection',
      () async {
        final h = await _Harness.selected();
        h.dispose();

        await expectLater(
          h.controller.selectContact(h.repo.contactB),
          completes,
        );

        h.expectSilent();
        expect(h.controller.selectedContact, same(h.repo.contactA));
        expect(h.controller.thread.status, QueryStatus.data);
      },
    );

    test(
      'loadEarlier() with more pages available completes silently',
      () async {
        final h = await _Harness.selected();
        expect(h.controller.thread.lastGoodData?.hasMore, isTrue);
        h.dispose();

        await expectLater(h.controller.loadEarlier(), completes);

        h.expectSilent();
        expect(h.controller.thread.status, QueryStatus.data);
        expect(h.controller.thread.lastGoodData?.messages.length, 1);
      },
    );

    test('sendMessage() with a selected contact completes silently', () async {
      final h = await _Harness.selected();
      h.dispose();

      await expectLater(h.controller.sendMessage('hello'), completes);

      h.expectSilent();
      expect(h.controller.sendAction.status, ActionStatus.idle);
      expect(h.controller.lastSendResult, isNull);
    });

    test(
      'deleteSelectedThread() with a selected contact completes silently',
      () async {
        final h = await _Harness.selected();
        h.dispose();

        await expectLater(h.controller.deleteSelectedThread(), completes);

        h.expectSilent();
        expect(h.controller.deleteAction.status, ActionStatus.idle);
        expect(h.controller.selectedContact, same(h.repo.contactA));
      },
    );
  });

  group('disposed while a request is in flight', () {
    test('loadContacts: late success completes silently', () async {
      final h = _Harness();
      h.repo.contactsGate = Completer<List<SmsContact>>();
      final pending = h.controller.loadContacts();
      expect(h.repo.calls, <String>['fetchContacts']);
      expect(h.controller.contacts.status, QueryStatus.loading);
      h.dispose();

      h.repo.contactsGate!.complete(<SmsContact>[h.repo.contactA]);
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.contacts.status, QueryStatus.loading);
    });

    test('selectContact: late thread page completes silently', () async {
      final h = _Harness();
      await h.controller.loadContacts();
      h.repo.threadGate = Completer<SmsThreadPage>();
      final pending = h.controller.selectContact(h.repo.contactA);
      expect(h.repo.calls, contains('fetchThread'));
      expect(h.controller.thread.status, QueryStatus.loading);
      h.dispose();

      h.repo.threadGate!.complete(
        SmsThreadPage(
          messages: <SmsMessage>[_message(2, 'late')],
          hasMore: false,
        ),
      );
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.thread.status, QueryStatus.loading);
    });

    test('sendMessage: late success completes silently', () async {
      final h = await _Harness.selected();
      h.repo.sendGate = Completer<SmsSendResult>();
      final pending = h.controller.sendMessage('hello');
      expect(h.controller.sendAction.status, ActionStatus.submitting);
      h.dispose();

      h.repo.sendGate!.complete(_delivered);
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.sendAction.status, ActionStatus.submitting);
      expect(h.controller.lastSendResult, isNull);
    });

    test('sendMessage: late failure completes silently', () async {
      final h = await _Harness.selected();
      h.repo.sendGate = Completer<SmsSendResult>();
      final pending = h.controller.sendMessage('hello');
      expect(h.controller.sendAction.status, ActionStatus.submitting);
      h.dispose();

      h.repo.sendGate!.completeError(_lateFailure);
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.sendAction.status, ActionStatus.submitting);
      expect(h.controller.lastSendResult, isNull);
    });

    test('deleteSelectedThread: late success completes silently', () async {
      final h = await _Harness.selected();
      h.repo.deleteGate = Completer<int>();
      final pending = h.controller.deleteSelectedThread();
      expect(h.controller.deleteAction.status, ActionStatus.submitting);
      h.dispose();

      h.repo.deleteGate!.complete(1);
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.deleteAction.status, ActionStatus.submitting);
      expect(h.controller.selectedContact, same(h.repo.contactA));
    });

    test('deleteSelectedThread: late failure completes silently', () async {
      final h = await _Harness.selected();
      h.repo.deleteGate = Completer<int>();
      final pending = h.controller.deleteSelectedThread();
      expect(h.controller.deleteAction.status, ActionStatus.submitting);
      h.dispose();

      h.repo.deleteGate!.completeError(_lateFailure);
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.deleteAction.status, ActionStatus.submitting);
    });
  });

  group('dispose() twice', () {
    test('second dispose() returns normally without a notification', () async {
      final h = await _Harness.selected();
      h.dispose();

      expect(h.controller.dispose, returnsNormally);
      await pumpEventQueue();

      h.expectSilent();
    });
  });
}

final class _Target implements SmsContactTarget {
  const _Target(this.name);
  final String name;
  @override
  String toString() => 'SmsContactTarget($name)';
}

final class _Cursor implements SmsThreadCursor {
  const _Cursor();
}

SmsContact _contact(String suffix) => SmsContact(
  peerDisplay: '•••�?12$suffix',
  localPhoneDisplay: '•••�?9999',
  iccidDisplay: '•••�?8888',
  deviceName: 'Modem $suffix',
  preview: 'Preview $suffix',
  messageCount: 1,
  unreadCount: 0,
  lastTimestamp: DateTime.utc(2026, 9, 2),
  target: _Target(suffix),
);

SmsMessage _message(int id, String body) => SmsMessage(
  stableId: 'message-$id',
  numericId: id,
  senderDisplay: '•••�?1234',
  body: body,
  direction: SmsDirection.inbound,
  timestamp: DateTime.utc(2026, 9, 2, 8, id),
);

final class _Harness {
  _Harness() {
    controller = SmsController(
      repository: repo,
      requestRegistry: RequestRegistry(),
    );
    controller.addListener(() => notifications++);
    addTearDown(controller.dispose);
  }

  static Future<_Harness> selected() async {
    final h = _Harness();
    await h.controller.loadContacts();
    await h.controller.selectContact(h.repo.contactA);
    expect(h.controller.contacts.status, QueryStatus.data);
    expect(h.controller.selectedContact, same(h.repo.contactA));
    expect(h.controller.thread.status, QueryStatus.data);
    return h;
  }

  final _Repository repo = _Repository();
  late final SmsController controller;
  int notifications = 0;

  void dispose() {
    controller.dispose();
    notifications = 0;
    repo.calls.clear();
  }

  void expectSilent() {
    expect(notifications, 0);
    expect(repo.calls, isEmpty);
  }
}

final class _Repository implements SmsRepository {
  final SmsContact contactA = _contact('34');
  final SmsContact contactB = _contact('56');
  final List<String> calls = <String>[];
  Completer<List<SmsContact>>? contactsGate;
  Completer<SmsThreadPage>? threadGate;
  Completer<SmsSendResult>? sendGate;
  Completer<int>? deleteGate;

  @override
  Future<List<SmsContact>> fetchContacts({RequestCancellation? cancellation}) {
    calls.add('fetchContacts');
    final gate = contactsGate;
    if (gate != null) return gate.future;
    return Future<List<SmsContact>>.value(<SmsContact>[contactA, contactB]);
  }

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) {
    calls.add('fetchThread');
    final gate = threadGate;
    if (gate != null) return gate.future;
    return Future<SmsThreadPage>.value(
      SmsThreadPage(
        messages: <SmsMessage>[_message(2, 'newer')],
        nextCursor: const _Cursor(),
        hasMore: true,
      ),
    );
  }

  @override
  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) {
    calls.add('sendMessage');
    final gate = sendGate;
    if (gate != null) return gate.future;
    return Future<SmsSendResult>.value(_delivered);
  }

  @override
  Future<int> deleteThread(
    SmsContactTarget target, {
    RequestCancellation? cancellation,
  }
  @override
  Future<bool> deleteMessage(
    int messageId, {
    RequestCancellation? cancellation,
  }) async => true;) {
    calls.add('deleteThread');
    final gate = deleteGate;
    if (gate != null) return gate.future;
    return Future<int>.value(1);
  }
}
