import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/sms/data/sms_repository.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/state/sms_controller.dart';

void main() {
  test('silent OTP failure does not fail an in-flight contacts load', () async {
    final contactsGate = Completer<void>();
    final repo = _Repo()..contactsGate = contactsGate;
    final controller = SmsController(
      repository: repo,
      requestRegistry: RequestRegistry(),
      otpSink: _Sink(),
    );
    addTearDown(controller.dispose);

    final loading = controller.loadContacts();
    await Future<void>.delayed(Duration.zero);
    expect(controller.contacts.status, QueryStatus.loading);

    repo.failNext = true;
    await controller.pollOtpInbox();
    expect(controller.contacts.status, QueryStatus.loading);

    contactsGate.complete();
    await loading;
    expect(controller.contacts.status, QueryStatus.data);
  });

  test('silent OTP empty result does not wipe last-good contacts', () async {
    final repo = _Repo();
    final controller = SmsController(
      repository: repo,
      requestRegistry: RequestRegistry(),
      otpSink: _Sink(),
    );
    addTearDown(controller.dispose);

    await controller.loadContacts();
    expect(controller.contacts.status, QueryStatus.data);
    expect(controller.contacts.lastGoodData, isNotEmpty);

    repo.contacts = const <SmsContact>[];
    await controller.pollOtpInbox();
    expect(controller.contacts.status, QueryStatus.data);
    expect(controller.contacts.lastGoodData, isNotEmpty);
  });
}

final class _Sink implements SmsOtpSink {
  @override
  Future<void> present(SmsOtpHit hit) async {}
}

final class _Target implements SmsContactTarget {
  const _Target();
}

final class _Repo implements SmsRepository {
  Completer<void>? contactsGate;
  bool failNext = false;
  List<SmsContact> contacts = <SmsContact>[
    SmsContact(
      peerDisplay: '•••�?1234',
      localPhoneDisplay: '•••�?9999',
      iccidDisplay: '•••�?8888',
      deviceName: 'Travel modem',
      preview: 'hello',
      messageCount: 1,
      unreadCount: 0,
      lastTimestamp: DateTime.utc(2026, 9, 10, 8),
      target: const _Target(),
      inboxKey: 'modem-a',
    ),
  ];

  @override
  Future<List<SmsContact>> fetchContacts({
    RequestCancellation? cancellation,
  }) async {
    if (failNext) {
      failNext = false;
      throw const ApiFailure(ApiFailureKind.timeout, requestId: 'otp-timeout');
    }
    final gate = contactsGate;
    if (gate != null) await gate.future;
    return contacts;
  }

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) async => SmsThreadPage(messages: const <SmsMessage>[], hasMore: false);

  @override
  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) async => throw UnimplementedError();

  @override
  Future<int> deleteThread(
    SmsContactTarget target, {
    RequestCancellation? cancellation,
  }
  @override
  Future<bool> deleteMessage(
    int messageId, {
    RequestCancellation? cancellation,
  }) async => true;) async => 0;
}
