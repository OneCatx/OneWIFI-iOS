import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';
import 'package:onewifi_android/features/sms/data/sms_repository.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/state/sms_controller.dart';

void main() {
  test('loads contacts and prepends one real before-id page', () async {
    final repository = _Repository();
    final controller = SmsController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.loadContacts();
    await controller.selectContact(repository.contactA);
    expect(controller.contacts.status, QueryStatus.data);
    expect(controller.thread.lastGoodData!.messages.single.body, 'newer');
    expect(controller.thread.lastGoodData!.hasMore, isTrue);

    await controller.loadEarlier();

    expect(repository.threadCursors, <SmsThreadCursor?>[
      null,
      repository.cursor,
    ]);
    expect(
      controller.thread.lastGoodData!.messages.map((message) => message.body),
      <String>['older', 'newer'],
    );
    expect(controller.thread.lastGoodData!.hasMore, isFalse);
  });

  test('selection cancellation ignores a late thread response', () async {
    final repository = _Repository(blockFirstThread: true);
    final controller = SmsController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.loadContacts();

    final first = controller.selectContact(repository.contactA);
    await Future<void>.delayed(Duration.zero);
    final second = controller.selectContact(repository.contactB);
    await second;
    expect(repository.firstCancellation!.isCancelled, isTrue);
    repository.firstThread.complete(
      SmsThreadPage(
        messages: <SmsMessage>[_message(9, 'late')],
        hasMore: false,
      ),
    );
    await first;

    expect(controller.selectedContact, same(repository.contactB));
    expect(controller.thread.lastGoodData!.messages.single.body, 'current');
  });

  test(
    'send is single-flight and separates conflict from unknown outcome',
    () async {
      final repository = _Repository(blockSend: true);
      final controller = SmsController(
        repository: repository,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);
      await controller.loadContacts();
      await controller.selectContact(repository.contactA);

      final pending = controller.sendMessage('hello');
      controller.sendMessage('duplicate');
      expect(repository.sendCalls, 1);
      expect(controller.sendAction.status, ActionStatus.submitting);
      repository.sendResult.complete(
        const SmsSendResult(
          outcome: SmsSendOutcome.acceptedUnconfirmed,
          partsTotal: 1,
          partsAccepted: 1,
          retrySafe: false,
        ),
      );
      await pending;
      expect(controller.sendAction.status, ActionStatus.succeeded);
      expect(
        controller.lastSendResult?.outcome,
        SmsSendOutcome.acceptedUnconfirmed,
      );

      repository.sendFailure = const ApiFailure(
        ApiFailureKind.http,
        requestId: 'safe-conflict',
        statusCode: 409,
      );
      await controller.sendMessage('conflict');
      expect(
        controller.sendAction.knownFailure?.kind,
        StateFailureKind.conflict,
      );

      repository.sendFailure = const ApiFailure(
        ApiFailureKind.timeout,
        requestId: 'safe-timeout',
      );
      await controller.sendMessage('timeout');
      expect(controller.sendAction.isUnknownOutcome, isTrue);
      expect(repository.sendCalls, 3);
    },
  );

  test('delete thread is single-flight and clears the selection', () async {
    final repository = _Repository();
    final controller = SmsController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.loadContacts();
    await controller.selectContact(repository.contactA);
    expect(controller.selectedContact, isNotNull);

    await controller.deleteSelectedThread();
    controller.deleteSelectedThread();

    expect(repository.deleteCalls, 1);
    expect(controller.selectedContact, isNull);
    expect(controller.deleteAction.status, ActionStatus.succeeded);
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

final class _Repository implements SmsRepository {
  _Repository({this.blockFirstThread = false, this.blockSend = false});

  final bool blockFirstThread;
  final bool blockSend;
  final SmsContact contactA = _contact('34');
  final SmsContact contactB = _contact('56');
  final SmsThreadCursor cursor = const _Cursor();
  final Completer<SmsThreadPage> firstThread = Completer<SmsThreadPage>();
  final Completer<SmsSendResult> sendResult = Completer<SmsSendResult>();
  final List<SmsThreadCursor?> threadCursors = <SmsThreadCursor?>[];
  RequestCancellation? firstCancellation;
  Object? sendFailure;
  int sendCalls = 0;
  int deleteCalls = 0;

  @override
  Future<List<SmsContact>> fetchContacts({
    RequestCancellation? cancellation,
  }) async => <SmsContact>[contactA, contactB];

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) {
    threadCursors.add(cursor);
    if (blockFirstThread &&
        identical(target, contactA.target) &&
        !firstThread.isCompleted) {
      firstCancellation = cancellation;
      return firstThread.future;
    }
    if (identical(target, contactB.target)) {
      return Future<SmsThreadPage>.value(
        SmsThreadPage(
          messages: <SmsMessage>[_message(7, 'current')],
          hasMore: false,
        ),
      );
    }
    if (cursor == null) {
      return Future<SmsThreadPage>.value(
        SmsThreadPage(
          messages: <SmsMessage>[_message(2, 'newer')],
          nextCursor: this.cursor,
          hasMore: true,
        ),
      );
    }
    return Future<SmsThreadPage>.value(
      SmsThreadPage(
        messages: <SmsMessage>[_message(1, 'older')],
        hasMore: false,
      ),
    );
  }

  @override
  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) {
    sendCalls += 1;
    final failure = sendFailure;
    if (failure != null) return Future<SmsSendResult>.error(failure);
    if (blockSend && !sendResult.isCompleted) return sendResult.future;
    return Future<SmsSendResult>.value(
      const SmsSendResult(
        outcome: SmsSendOutcome.delivered,
        partsTotal: 1,
        partsAccepted: 1,
        retrySafe: false,
      ),
    );
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
  }) async => true;) async {
    deleteCalls += 1;
    return 2;
  }
}
