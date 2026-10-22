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

/// P4 短信旧黄金路径：contacts → thread → send → delete；401 鉴权映射。
void main() {
  group('contacts', () {
    test('loads under the stable sms.contacts key', () async {
      final repo = _Repo(contacts: <SmsContact>[_contact('a')]);
      final controller = SmsController(
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      await controller.loadContacts();

      expect(controller.contacts.status, QueryStatus.data);
      expect(controller.contacts.key, 'sms.contacts');
      expect(controller.contacts.lastGoodData?.single.peerDisplay, '•••• 12a');
    });

    test('maps contacts 401 as authentication without fabricating empty', () async {
      final controller = SmsController(
        repository: _Repo(
          contactsError: const ApiFailure(
            ApiFailureKind.http,
            requestId: 'sms-contacts-401',
            statusCode: 401,
            backendCode: 'unauthorized',
          ),
        ),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      await controller.loadContacts();

      expect(controller.contacts.status, QueryStatus.failed);
      expect(controller.contacts.failure?.kind, StateFailureKind.authentication);
      expect(controller.contacts.failure?.statusCode, 401);
      expect(controller.contacts.lastGoodData, isNull);
    });
  });

  group('thread', () {
    test('selectContact lands thread data for the chosen peer', () async {
      final repo = _Repo(contacts: <SmsContact>[_contact('a')]);
      final controller = SmsController(
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      await controller.loadContacts();
      await controller.selectContact(repo.contacts.single);

      expect(controller.selectedContact, same(repo.contacts.single));
      expect(controller.thread.status, QueryStatus.data);
      expect(controller.thread.lastGoodData?.messages.single.body, 'hello');
    });
  });

  group('send', () {
    test('send is single-flight and succeeds', () async {
      final repo = _Repo(
        contacts: <SmsContact>[_contact('a')],
        blockSend: true,
      );
      final controller = SmsController(
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      await controller.loadContacts();
      await controller.selectContact(repo.contacts.single);

      final pending = controller.sendMessage('ping');
      unawaited(controller.sendMessage('dup'));
      expect(repo.sendCalls, 1);
      expect(controller.sendAction.status, ActionStatus.submitting);

      repo.sendGate.complete(
        const SmsSendResult(
          outcome: SmsSendOutcome.delivered,
          partsTotal: 1,
          partsAccepted: 1,
          retrySafe: false,
        ),
      );
      await pending;

      expect(controller.sendAction.status, ActionStatus.succeeded);
      expect(controller.lastSendResult?.outcome, SmsSendOutcome.delivered);
      expect(repo.sendBodies, <String>['ping']);
    });
  });

  group('delete', () {
    test('deleteSelectedThread clears selection after success', () async {
      final repo = _Repo(contacts: <SmsContact>[_contact('a')]);
      final controller = SmsController(
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      await controller.loadContacts();
      await controller.selectContact(repo.contacts.single);
      await controller.deleteSelectedThread();

      expect(repo.deleteCalls, 1);
      expect(controller.selectedContact, isNull);
      expect(controller.deleteAction.status, ActionStatus.succeeded);
    });
  });
}

final class _Target implements SmsContactTarget {
  const _Target(this.name);
  final String name;
}

SmsContact _contact(String suffix) => SmsContact(
  peerDisplay: '•••• 12$suffix',
  localPhoneDisplay: '•••• 9999',
  iccidDisplay: '•••• 8888',
  deviceName: 'Modem $suffix',
  preview: 'Preview $suffix',
  messageCount: 1,
  unreadCount: 0,
  lastTimestamp: DateTime.utc(2026, 10, 20),
  target: _Target(suffix),
  inboxKey: 'inbox-$suffix',
);

SmsMessage _message(String body) => SmsMessage(
  stableId: 'message-1',
  numericId: 1,
  senderDisplay: '•••• 1234',
  body: body,
  direction: SmsDirection.inbound,
  timestamp: DateTime.utc(2026, 10, 20, 9),
);

final class _Repo implements SmsRepository {
  _Repo({
    List<SmsContact>? contacts,
    this.contactsError,
    this.blockSend = false,
  }) : contacts = contacts ?? const <SmsContact>[];

  final List<SmsContact> contacts;
  final Object? contactsError;
  final bool blockSend;
  final Completer<SmsSendResult> sendGate = Completer<SmsSendResult>();
  final List<String> sendBodies = <String>[];
  int sendCalls = 0;
  int deleteCalls = 0;

  @override
  Future<List<SmsContact>> fetchContacts({
    RequestCancellation? cancellation,
  }) async {
    final error = contactsError;
    if (error != null) throw error;
    return contacts;
  }

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) async {
    return SmsThreadPage(
      messages: <SmsMessage>[_message('hello')],
      hasMore: false,
    );
  }

  @override
  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) async {
    sendCalls += 1;
    sendBodies.add(message);
    if (blockSend) return sendGate.future;
    return const SmsSendResult(
      outcome: SmsSendOutcome.delivered,
      partsTotal: 1,
      partsAccepted: 1,
      retrySafe: false,
    );
  }

  @override
  Future<int> deleteThread(
    SmsContactTarget target, {
    RequestCancellation? cancellation,
  }) async {
    deleteCalls += 1;
    return 1;
  }

  @override
  Future<bool> deleteMessage(
    int messageId, {
    RequestCancellation? cancellation,
  }) async => true;
}
