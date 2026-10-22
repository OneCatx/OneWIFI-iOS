import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/glass_dialog.dart';
import 'package:onewifi_android/features/sms/data/sms_otp_sink.dart';
import 'package:onewifi_android/features/sms/data/sms_repository.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/presentation/sms_screen.dart';
import 'package:onewifi_android/features/sms/presentation/widgets/remote_otp_pairing_tile.dart';
import 'package:onewifi_android/features/sms/presentation/widgets/sms_contact_button.dart';
import 'package:onewifi_android/features/sms/presentation/widgets/sms_otp_watch_tile.dart';
import 'package:onewifi_android/features/sms/state/sms_controller.dart';

void main() {
  testWidgets('SMS page has no backend pairing or activity test entry', (
    tester,
  ) async {
    final controller = SmsController(
      repository: _Repository(),
      requestRegistry: RequestRegistry(),
      otpSink: NativeSmsOtpSink(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(SmsScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteOtpPairingTile), findsNothing);
    expect(find.byKey(RemoteOtpPairingTile.activityTestKey), findsNothing);
    expect(find.text('验证码推�?), findsOneWidget);
  });

  testWidgets('thread stays masked and send requires one confirmation', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(SmsScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text(repository.rawPeer), findsNothing);
    expect(find.text('可选模�?), findsOneWidget);
    expect(find.text('全部设备'), findsWidgets);
    expect(find.text('•••�?1234'), findsWidgets);
    final contact = find
        .ancestor(of: find.text('•••�?1234'), matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(contact);
    await tester.pumpAndSettle();
    await tester.tap(contact);
    await tester.pumpAndSettle();
    expect(find.text('A safe visible message'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.byKey(SmsScreen.messageFieldKey),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(SmsScreen.messageFieldKey), 'reply text');
    await tester.pump();
    final sendButton = find.widgetWithText(FilledButton, '发�?);
    await tester.ensureVisible(sendButton);
    await tester.pumpAndSettle();
    await tester.tap(sendButton);
    await tester.pumpAndSettle();
    expect(find.byType(OneGlassDialog), findsOneWidget);
    expect(repository.sendCalls, 0);
    await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
    await tester.pumpAndSettle();

    expect(repository.sendCalls, 1);
    expect(find.text('已受理，送达未确�?), findsOneWidget);
    expect(find.text(repository.rawPeer), findsNothing);
  });

  testWidgets('screen scrolls at 320dp and 200 percent text in both themes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final controller = _controller(_Repository());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          darkTheme: OneTheme.dark(),
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 760),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(body: SmsScreen(controller: controller)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('短信检�?, skipOffstage: false), findsOneWidget);
      expect(find.byKey(RemoteOtpPairingTile.cardKey), findsNothing);
      expect(find.text('远程验证�?), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('delete thread requires confirmation and does not retry', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(SmsScreen(controller: controller)));
    await tester.pumpAndSettle();
    final contact = find
        .ancestor(of: find.text('•••�?1234'), matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(contact);
    await tester.pumpAndSettle();
    await tester.tap(contact);
    await tester.pumpAndSettle();
    expect(find.text('删除会话'), findsOneWidget);
    await tester.tap(find.byKey(SmsScreen.deleteThreadKey));
    await tester.pumpAndSettle();
    expect(find.byType(OneGlassDialog), findsOneWidget);
    expect(repository.deleteCalls, 0);
    await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 1);
    expect(find.byKey(SmsScreen.deleteThreadKey), findsNothing);
    expect(find.text('A safe visible message'), findsWidgets);
  });

  testWidgets('otp watch switch is only shown when a sink is attached', (
    tester,
  ) async {
    await _tall(tester);
    final withoutSink = _controller(_Repository());
    addTearDown(withoutSink.dispose);
    await tester.pumpWidget(_app(SmsScreen(controller: withoutSink)));
    await tester.pumpAndSettle();
    expect(find.text('验证码推�?), findsNothing);

    final withSink = SmsController(
      repository: _Repository(),
      requestRegistry: RequestRegistry(),
      otpSink: _OtpSink(),
    );
    addTearDown(withSink.dispose);
    await tester.pumpWidget(_app(SmsScreen(controller: withSink)));
    await tester.pumpAndSettle();
    expect(find.text('验证码推�?), findsOneWidget);
    await tester.tap(find.byKey(SmsOtpWatchTile.switchKey));
    await tester.pump();
    expect(withSink.otpWatchEnabled, isFalse);
  });

  testWidgets('reloading contacts keeps the selected highlight', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(SmsScreen(controller: controller)));
    await tester.pumpAndSettle();
    final contact = find
        .ancestor(of: find.text('•••�?1234'), matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(contact);
    await tester.pumpAndSettle();
    await tester.tap(contact);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SmsContactButton>(find.byType(SmsContactButton).first)
          .selected,
      isTrue,
    );

    await controller.loadContacts();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SmsContactButton>(find.byType(SmsContactButton).first)
          .selected,
      isTrue,
    );
  });
}

Future<void> _tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _app(Widget child) => MaterialApp(
  theme: OneTheme.light(),
  darkTheme: OneTheme.dark(),
  home: Scaffold(body: child),
);

SmsController _controller(SmsRepository repository) =>
    SmsController(repository: repository, requestRegistry: RequestRegistry());

final class _OtpSink implements SmsOtpSink {
  @override
  Future<void> present(SmsOtpHit hit) async {}
}

final class _Target implements SmsContactTarget {
  const _Target();
}

final class _Repository implements SmsRepository {
  final String rawPeer = List<String>.generate(
    12,
    (index) => ((index + 3) % 10).toString(),
  ).join();
  int sendCalls = 0;
  int deleteCalls = 0;

  SmsContact get contact => SmsContact(
    peerDisplay: '•••�?1234',
    localPhoneDisplay: '•••�?7777',
    iccidDisplay: '•••�?9999',
    deviceName: 'Travel modem',
    preview: 'A safe visible message',
    messageCount: 1,
    unreadCount: 1,
    lastTimestamp: DateTime.utc(2026, 9, 2, 8, 30),
    target: const _Target(),
    inboxKey: 'modem-a',
  );

  @override
  Future<List<SmsContact>> fetchContacts({
    RequestCancellation? cancellation,
  }) async => <SmsContact>[contact];

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) async => SmsThreadPage(
    messages: <SmsMessage>[
      SmsMessage(
        stableId: 'message-1',
        numericId: 1,
        senderDisplay: '•••�?1234',
        body: 'A safe visible message',
        direction: SmsDirection.inbound,
        timestamp: DateTime.utc(2026, 9, 2, 8, 30),
      ),
    ],
    hasMore: false,
  );

  @override
  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) async {
    sendCalls += 1;
    return const SmsSendResult(
      outcome: SmsSendOutcome.acceptedUnconfirmed,
      partsTotal: 1,
      partsAccepted: 1,
      retrySafe: false,
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
    return 1;
  }
}
