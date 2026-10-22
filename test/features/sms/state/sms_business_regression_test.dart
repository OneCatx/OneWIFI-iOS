import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/glass_dialog.dart';
import 'package:onewifi_android/features/sms/data/sms_repository.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/presentation/sms_screen.dart';
import 'package:onewifi_android/features/sms/presentation/widgets/sms_contact_button.dart';
import 'package:onewifi_android/features/sms/state/sms_controller.dart';

const _delivered = SmsSendResult(
  outcome: SmsSendOutcome.delivered,
  partsTotal: 1,
  partsAccepted: 1,
  retrySafe: false,
);

void main() {
  test('a late send result belongs to its original conversation', () async {
    final repo = _Repo()..sendGate = Completer<SmsSendResult>();
    final controller = _controller(repo);
    addTearDown(controller.dispose);
    await controller.selectContact(repo.a);
    final sending = controller.sendMessage('for A');
    await controller.selectContact(repo.b);
    expect(controller.sendAction.status, ActionStatus.idle);
    expect(controller.isSending, isTrue);
    expect(await controller.sendMessage('for B'), isNull);
    repo.sendGate!.complete(_delivered);
    expect(await sending, same(_delivered));
    expect(controller.lastSendResult, isNull);
    expect(controller.sendAction.status, ActionStatus.idle);
    expect(controller.isSending, isFalse);
    expect(controller.thread.lastGoodData?.messages.single.body, 'thread-b');
    expect(repo.sent, ['a:for A']);
  });

  for (final deleting in [false, true]) {
    testWidgets(
      '${deleting ? 'delete' : 'send'} confirmation cannot retarget after selection changes',
      (tester) async {
        final repo = _Repo();
        final controller = _controller(repo);
        addTearDown(controller.dispose);
        await _mountScreen(tester, controller, repo.a);
        final field = find.byKey(SmsScreen.messageFieldKey);
        if (!deleting) {
          await tester.ensureVisible(field);
          await tester.enterText(field, 'for A');
          await tester.pump();
        }
        final action = deleting
            ? find.byKey(SmsScreen.deleteThreadKey)
            : find.widgetWithText(FilledButton, 'ÂèëÈÄ?);
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await controller.selectContact(repo.b);
        await tester.pump();
        await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
        await tester.pumpAndSettle();
        expect(repo.sent, isEmpty);
        expect(repo.deleted, isEmpty);
        expect(controller.selectedContact, same(repo.b));
      },
    );
  }

  testWidgets(
    'editing a new draft while the successful send refreshes preserves it',
    (tester) async {
      final repo = _Repo()..sendGate = Completer<SmsSendResult>();
      final controller = _controller(repo);
      addTearDown(controller.dispose);
      await _mountScreen(tester, controller, repo.a);
      final field = find.byKey(SmsScreen.messageFieldKey);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'sent text');
      await tester.pump();
      final send = find.widgetWithText(FilledButton, 'ÂèëÈÄ?);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      repo.threadGate = Completer<SmsThreadPage>();
      repo.sendGate!.complete(_delivered);
      await tester.pump();
      expect(controller.sendAction.status, ActionStatus.succeeded);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'new draft');
      await tester.pump();
      // A version check, not just text equality: even rewriting the old text is
      // a new editing action and must not be cleared by the old completion.
      await tester.enterText(field, 'sent text');
      repo.threadGate!.complete(SmsThreadPage(messages: [], hasMore: false));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'sent text');
      expect(repo.sent, ['a:sent text']);
    },
  );

  test(
    'control: pending send blocks another send without reselection',
    () async {
      final repo = _Repo()..sendGate = Completer<SmsSendResult>();
      final controller = _controller(repo);
      addTearDown(controller.dispose);
      await controller.selectContact(repo.a);
      final first = controller.sendMessage('same message');
      final second = controller.sendMessage('same message');
      final beforeCompletion = repo.sent.length;
      repo.sendGate!.complete(_delivered);
      await Future.wait([first, second]);
      expect(beforeCompletion, 1);
    },
  );

  test(
    'SMS-SEND-07: reselecting the same contact must not allow duplicate submit',
    () async {
      final repo = _Repo()..sendGate = Completer<SmsSendResult>();
      final controller = _controller(repo);
      addTearDown(controller.dispose);
      await controller.selectContact(repo.a);
      final first = controller.sendMessage('same message');
      await controller.selectContact(repo.a);
      final second = controller.sendMessage('same message');
      final beforeCompletion = repo.sent.length;
      repo.sendGate!.complete(_delivered);
      await Future.wait([first, second]);
      expect(beforeCompletion, 1);
    },
  );

  test('control: deleting the still-selected contact clears it', () async {
    final repo = _Repo()..deleteGate = Completer<int>();
    final controller = _controller(repo);
    addTearDown(controller.dispose);
    await controller.selectContact(repo.a);
    final deleting = controller.deleteSelectedThread();
    repo.deleteGate!.complete(1);
    await deleting;
    expect(controller.selectedContact, isNull);
    expect(repo.deleted, ['a']);
  });

  test(
    'SMS-DELETE-09: late deletion of A must retain the currently selected B',
    () async {
      final repo = _Repo()..deleteGate = Completer<int>();
      final controller = _controller(repo);
      addTearDown(controller.dispose);
      await controller.selectContact(repo.a);
      final deleting = controller.deleteSelectedThread();
      await controller.selectContact(repo.b);
      repo.deleteGate!.complete(1);
      await deleting;
      expect(repo.deleted, ['a']);
      expect(controller.selectedContact, same(repo.b));
      expect(controller.thread.lastGoodData?.messages.single.body, 'thread-b');
    },
  );

  testWidgets(
    'SMS-DRAFT-08: late send completion for A must not erase new B draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 4200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _Repo()..sendGate = Completer<SmsSendResult>();
      final controller = _controller(repo);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          home: Scaffold(body: SmsScreen(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      Finder contact(String key) => find.byWidgetPredicate(
        (widget) =>
            widget is SmsContactButton && widget.contact.watchKey == key,
      );
      final field = find.byKey(SmsScreen.messageFieldKey);
      await tester.ensureVisible(contact('a'));
      await tester.tap(contact('a'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field);
      await tester.enterText(field, 'message for A');
      await tester.pump();
      final send = find.widgetWithText(FilledButton, 'ÂèëÈÄ?);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(repo.sent, ['a:message for A']);

      // Do not pumpAndSettle while the pending-send progress is animating.
      await tester.ensureVisible(contact('b'));
      await tester.tap(contact('b'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field);
      await tester.enterText(field, 'unsent draft for B');
      await tester.pump();
      expect(
        tester.widget<TextField>(field).controller!.text,
        'unsent draft for B',
      );

      repo.sendGate!.complete(_delivered);
      await tester.pumpAndSettle();
      expect(controller.selectedContact, same(repo.b));
      expect(
        tester.widget<TextField>(field).controller!.text,
        'unsent draft for B',
      );
    },
  );
}

SmsController _controller(_Repo repo) =>
    SmsController(repository: repo, requestRegistry: RequestRegistry());

Future<void> _mountScreen(
  WidgetTester tester,
  SmsController controller,
  SmsContact selected,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 4200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: OneTheme.light(),
      home: Scaffold(body: SmsScreen(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
  await controller.selectContact(selected);
  await tester.pumpAndSettle();
}

final class _Target implements SmsContactTarget {
  const _Target(this.key);
  final String key;
}

SmsContact _contact(String key) => SmsContact(
  peerDisplay: 'Contact $key',
  localPhoneDisplay: 'masked',
  iccidDisplay: 'masked',
  deviceName: 'Modem',
  preview: 'preview-$key',
  messageCount: 1,
  unreadCount: 0,
  lastTimestamp: DateTime.utc(2026, 9, 20),
  target: _Target(key),
  inboxKey: key,
);

final class _Repo implements SmsRepository {
  final a = _contact('a');
  final b = _contact('b');
  final sent = <String>[];
  final deleted = <String>[];
  Completer<SmsSendResult>? sendGate;
  Completer<int>? deleteGate;
  Completer<SmsThreadPage>? threadGate;

  @override
  Future<List<SmsContact>> fetchContacts({
    RequestCancellation? cancellation,
  }) async => [a, b];

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) async {
    if (threadGate case final gate?) return gate.future;
    final key = (target as _Target).key;
    return SmsThreadPage(
      messages: [
        SmsMessage(
          stableId: key,
          numericId: key == 'a' ? 1 : 2,
          senderDisplay: key,
          body: 'thread-$key',
          direction: SmsDirection.inbound,
          timestamp: DateTime.utc(2026, 9, 20),
        ),
      ],
      hasMore: false,
    );
  }

  @override
  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) {
    sent.add('${(target as _Target).key}:$message');
    return sendGate?.future ?? Future.value(_delivered);
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
    deleted.add((target as _Target).key);
    return deleteGate?.future ?? Future.value(1);
  }
}
