import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/sms/data/sms_api.dart';
import 'package:onewifi_android/features/sms/data/sms_repository.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/state/sms_controller.dart';

void main() {
  for (final hasHistory in [false, true]) {
    test(
      'newer empty poll supersedes stale contacts with ${hasHistory ? 'last-good history' : 'no history'}',
      () async {
        final retained = _contact('retained', '111111', 1, id: 1);
        final repo = _Repo()..snapshot = hasHistory ? [retained] : [];
        final sink = _Sink();
        final controller = _controller(repo, sink);
        addTearDown(controller.dispose);
        await controller.pollOtpInbox(seed: true);
        final staleContacts = Completer<List<SmsContact>>();
        repo.nextGate = staleContacts;
        final loading = controller.loadContacts();
        expect(
          controller.contacts.status,
          hasHistory ? QueryStatus.refreshing : QueryStatus.loading,
        );

        repo.snapshot = [];
        await controller.pollOtpInbox();
        final settledStatus = controller.contacts.status;
        final settledContacts = controller.contacts.lastGoodData;
        staleContacts.complete([_contact('stale', '222222', 2, id: 2)]);
        await loading;

        expect(sink.codes, isEmpty);
        expect(controller.lastOtpHit, isNull);
        expect(
          settledStatus,
          hasHistory ? QueryStatus.data : QueryStatus.empty,
        );
        expect(controller.contacts.status, settledStatus);
        if (hasHistory) {
          expect(settledContacts, [same(retained)]);
          expect(controller.contacts.lastGoodData, [same(retained)]);
        } else {
          expect(settledContacts, isNull);
          expect(controller.contacts.lastGoodData, isNull);
        }
      },
    );
  }

  test(
    'watch startup does not reseed after an earlier contacts load primes it',
    () async {
      final repo = _Repo();
      final sink = _Sink();
      final controller = _controller(repo, sink);
      addTearDown(controller.dispose);
      final initialContacts = Completer<List<SmsContact>>();
      final watchContacts = Completer<List<SmsContact>>();
      repo.nextGate = initialContacts;
      final loading = controller.loadContacts();
      repo.nextGate = watchContacts;
      controller.startOtpWatch();
      final polling = controller.pollOtpInbox();

      initialContacts.complete([_contact('a', '111111', 1, id: 1)]);
      await loading;
      expect(sink.codes, isEmpty);
      watchContacts.complete([_contact('a', '222222', 2, id: 2)]);
      await polling;
      expect(sink.codes, ['222222']);
      expect(controller.lastOtpHit?.code, '222222');
    },
  );

  test(
    'explicit delivery refusal does not publish success or repeatedly prompt',
    () async {
      final repo = _Repo();
      final sink = _DeliverySink()..accepted = false;
      final controller = SmsController(
        repository: repo,
        requestRegistry: RequestRegistry(),
        otpSink: sink,
      );
      addTearDown(controller.dispose);
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '111111', 1)];
      await controller.pollOtpInbox();
      await controller.pollOtpInbox();
      expect(sink.codes, ['111111']);
      expect(controller.lastOtpHit, isNull);
    },
  );

  test(
    'disposing a pending delivery cancels it and ignores its late success',
    () async {
      final repo = _Repo();
      final sink = _DeliverySink()..gate = Completer<bool>();
      final controller = SmsController(
        repository: repo,
        requestRegistry: RequestRegistry(),
        otpSink: sink,
      );
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '111111', 1), _contact('b', '222222', 2)];
      final polling = controller.pollOtpInbox();
      await sink.entered.future;
      controller.dispose();
      expect(sink.cancelCount, 1);
      sink.gate!.complete(true);
      await polling;
      expect(sink.codes, ['111111']);
      expect(controller.lastOtpHit, isNull);
    },
  );

  test(
    'off/on cannot revive an old batch or overwrite the new baseline',
    () async {
      final repo = _Repo();
      final sink = _Sink()..blockFirst = Completer<void>();
      final controller = _controller(repo, sink);
      addTearDown(controller.dispose);
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '111111', 1), _contact('b', '222222', 2)];
      final oldPoll = controller.pollOtpInbox();
      await sink.firstEntered.future;
      controller.setOtpWatchEnabled(false);
      repo.snapshot = [_contact('a', '333333', 3)];
      controller.setOtpWatchEnabled(true);
      await controller.pollOtpInbox();
      sink.blockFirst!.complete();
      await oldPoll;
      await controller.pollOtpInbox();
      expect(sink.codes, ['111111']);
      expect(controller.lastOtpHit, isNull);
      repo.snapshot = [_contact('a', '444444', 4)];
      await controller.pollOtpInbox();
      expect(sink.codes, ['111111', '444444']);
    },
  );

  test('control: a single new code is presented once', () async {
    final repo = _Repo()..snapshot = [_contact('a', '111111', 1)];
    final sink = _Sink();
    final controller = _controller(repo, sink);
    addTearDown(controller.dispose);
    await controller.pollOtpInbox(seed: true);
    expect(sink.hits, isEmpty);
    repo.snapshot = [_contact('a', '222222', 2)];
    await controller.pollOtpInbox();
    await controller.pollOtpInbox();
    expect(sink.codes, ['222222']);
  });

  test('SMS-ORDER-01: batch final code must be the newest', () async {
    final repo = _Repo();
    final sink = _Sink();
    final controller = _controller(repo, sink);
    addTearDown(controller.dispose);
    await controller.pollOtpInbox(seed: true);
    repo.snapshot = [_contact('a', '222222', 2), _contact('b', '111111', 1)];
    await controller.pollOtpInbox();
    expect(sink.hits, hasLength(2));
    expect(controller.lastOtpHit?.code, '222222');
    expect(sink.codes.last, '222222');
  });

  test(
    'SMS-COUNT-05: deleting older history must not replay the unchanged last code',
    () async {
      final repo = _Repo()..snapshot = [_contact('a', '111111', 1, count: 2)];
      final sink = _Sink();
      final controller = _controller(repo, sink);
      addTearDown(controller.dispose);
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '111111', 1, count: 1)];
      await controller.pollOtpInbox();
      expect(sink.codes, isEmpty);
    },
  );

  test(
    'SMS-OUTBOUND-06: sent code must not be presented as received OTP',
    () async {
      var seeded = false;
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': [
              {
                'device_id': 'test-device',
                'device_name': 'Test modem',
                'peer': '10086',
                'local_phone': '',
                'iccid': '',
                'imsi': '',
                'last_content': seeded ? '验证�?222222' : 'hello',
                'last_timestamp': seeded
                    ? '2026-09-20T08:02:00Z'
                    : '2026-09-20T08:01:00Z',
                'direction': seeded ? 'outbound' : 'inbound',
                'last_sms_id': seeded ? 2 : 1,
                'message_count': seeded ? 2 : 1,
                'unread_count': 0,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final sink = _Sink();
      final controller = SmsController(
        repository: DefaultSmsRepository(
          SmsApi(
            HttpTransport(
              client: client,
              originProvider: () async => Uri.parse('https://example.test'),
              tokenProvider: (_) async => 'synthetic-test-token',
            ),
          ),
        ),
        requestRegistry: RequestRegistry(),
        otpSink: sink,
      );
      addTearDown(controller.dispose);
      addTearDown(client.close);
      await controller.pollOtpInbox(seed: true);
      seeded = true;
      await controller.pollOtpInbox();
      expect(controller.contacts.lastGoodData?.single.preview, '验证�?222222');
      expect(sink.codes, isEmpty);
    },
  );

  test('SMS-STALE-02: old contacts response must not replay OTPs', () async {
    final old = _contact('a', '111111', 1);
    final fresh = _contact('a', '222222', 2);
    final repo = _Repo()..snapshot = [old];
    final sink = _Sink();
    final controller = _controller(repo, sink);
    addTearDown(controller.dispose);
    await controller.pollOtpInbox(seed: true);
    final oldGate = Completer<List<SmsContact>>();
    repo.nextGate = oldGate;
    final oldLoad = controller.loadContacts();
    repo.snapshot = [fresh];
    await controller.pollOtpInbox();
    oldGate.complete([old]);
    await oldLoad;
    await controller.pollOtpInbox();
    expect(sink.codes, ['222222']);
    expect(controller.contacts.lastGoodData?.single.preview, '验证�?222222');
  });

  test('an obsolete snapshot cannot introduce an unseen old contact', () async {
    final repo = _Repo()..snapshot = [_contact('a', '111111', 1)];
    final sink = _Sink();
    final controller = _controller(repo, sink);
    addTearDown(controller.dispose);
    await controller.pollOtpInbox(seed: true);
    final gate = Completer<List<SmsContact>>();
    repo.nextGate = gate;
    final loading = controller.loadContacts();
    repo.snapshot = [_contact('a', '222222', 2)];
    await controller.pollOtpInbox();
    gate.complete([_contact('b', '333333', 1)]);
    await loading;
    expect(sink.codes, ['222222']);
  });

  test(
    'legacy same-timestamp revisions do not replay after a rollback',
    () async {
      final repo = _Repo()..snapshot = [_contact('a', '111111', 1)];
      final sink = _Sink();
      final controller = _controller(repo, sink);
      addTearDown(controller.dispose);
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '222222', 1)];
      await controller.pollOtpInbox();
      repo.snapshot = [_contact('a', '111111', 1)];
      await controller.pollOtpInbox();
      repo.snapshot = [_contact('a', '222222', 1)];
      await controller.pollOtpInbox();
      expect(sink.codes, ['222222']);
    },
  );

  test(
    'SMS-CANCEL-03: disabling during present cancels later batch entries',
    () async {
      final repo = _Repo();
      final sink = _Sink()..blockFirst = Completer<void>();
      final controller = _controller(repo, sink);
      addTearDown(controller.dispose);
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '222222', 2), _contact('b', '111111', 1)];
      final polling = controller.pollOtpInbox();
      await sink.firstEntered.future;
      controller.setOtpWatchEnabled(false);
      sink.blockFirst!.complete();
      await polling;
      expect(controller.otpWatchEnabled, isFalse);
      // Oldest-first delivery is required by SMS-ORDER-01; only its first item
      // may have entered the sink before the watch was cancelled.
      expect(sink.codes, ['111111']);
      expect(controller.lastOtpHit, isNull);
    },
  );

  testWidgets(
    'SMS-POLL-04: a successful 9s response must not starve under 8s polling',
    (tester) async {
      final repo = _Repo()..snapshot = [_contact('a', '111111', 1)];
      final sink = _Sink();
      final controller = _controller(repo, sink);
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '222222', 2)];
      repo.delay = const Duration(seconds: 9);
      controller.startOtpWatch();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      final duringMonitoring = List<String>.of(sink.codes);
      controller.dispose();
      await tester.pump(const Duration(seconds: 10));
      expect(duringMonitoring, ['222222']);
    },
  );

  testWidgets('control: a 7s response completes under 8s polling', (
    tester,
  ) async {
    final repo = _Repo()..snapshot = [_contact('a', '111111', 1)];
    final sink = _Sink();
    final controller = _controller(repo, sink);
    await controller.pollOtpInbox(seed: true);
    repo.snapshot = [_contact('a', '222222', 2)];
    repo.delay = const Duration(seconds: 7);
    controller.startOtpWatch();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final duringMonitoring = List<String>.of(sink.codes);
    controller.dispose();
    await tester.pump(const Duration(seconds: 10));
    expect(duringMonitoring, ['222222']);
  });

  test(
    'server message ids never regress when snapshots go backwards',
    () async {
      final repo = _Repo()..snapshot = [_contact('a', '111111', 1, id: 10)];
      final sink = _Sink();
      final controller = _controller(repo, sink);
      addTearDown(controller.dispose);
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '222222', 2, id: 12)];
      await controller.pollOtpInbox();
      repo.snapshot = [_contact('a', '333333', 3, id: 11)];
      await controller.pollOtpInbox();
      repo.snapshot = [_contact('a', '222222', 2, id: 12)];
      await controller.pollOtpInbox();
      expect(sink.codes, ['222222']);
    },
  );

  test(
    'different message ids with identical time and text are new messages',
    () async {
      final repo = _Repo()..snapshot = [_contact('a', '111111', 1, id: 10)];
      final sink = _Sink();
      final controller = _controller(repo, sink);
      addTearDown(controller.dispose);
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '111111', 1, id: 11)];
      await controller.pollOtpInbox();
      expect(sink.codes, ['111111']);
    },
  );

  test(
    'a failed delivery leaves its batch retryable in chronological order',
    () async {
      final repo = _Repo();
      final sink = _Sink()..failCodeOnce = '111111';
      final controller = _controller(repo, sink);
      addTearDown(controller.dispose);
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '222222', 2), _contact('b', '111111', 1)];
      await controller.pollOtpInbox();
      expect(sink.codes, isEmpty);
      await controller.pollOtpInbox();
      expect(sink.codes, ['111111', '222222']);
    },
  );

  test(
    'simultaneous reads serialize delivery without duplicating a code',
    () async {
      final repo = _Repo();
      final sink = _Sink()..blockFirst = Completer<void>();
      final controller = _controller(repo, sink);
      addTearDown(controller.dispose);
      await controller.pollOtpInbox(seed: true);
      repo.snapshot = [_contact('a', '111111', 1)];
      final polling = controller.pollOtpInbox();
      await sink.firstEntered.future;
      final loading = controller.loadContacts();
      sink.blockFirst!.complete();
      await Future.wait([polling, loading]);
      expect(sink.codes, ['111111']);
    },
  );
}

SmsController _controller(_Repo repo, _Sink sink) => SmsController(
  repository: repo,
  requestRegistry: RequestRegistry(),
  otpSink: sink,
);

final class _Target implements SmsContactTarget {
  const _Target();
}

SmsContact _contact(
  String key,
  String code,
  int minute, {
  int? count,
  int? id,
}) => SmsContact(
  peerDisplay: 'sender-$key',
  localPhoneDisplay: 'masked',
  iccidDisplay: 'masked',
  deviceName: 'modem-$key',
  preview: '验证�?$code',
  messageCount: count ?? minute,
  unreadCount: 1,
  lastTimestamp: DateTime.utc(2026, 9, 20, 8, minute),
  target: const _Target(),
  inboxKey: key,
  lastSmsId: id,
);

final class _Sink implements SmsOtpSink {
  final hits = <SmsOtpHit>[];
  final firstEntered = Completer<void>();
  Completer<void>? blockFirst;
  String? failCodeOnce;
  List<String> get codes => hits.map((hit) => hit.code).toList();

  @override
  Future<void> present(SmsOtpHit hit) async {
    if (failCodeOnce == hit.code) {
      failCodeOnce = null;
      throw StateError('synthetic delivery failure');
    }
    hits.add(hit);
    if (hits.length == 1) {
      firstEntered.complete();
      if (blockFirst case final gate?) await gate.future;
    }
  }
}

final class _DeliverySink implements SmsOtpDeliverySink {
  final codes = <String>[];
  final entered = Completer<void>();
  bool accepted = true;
  int cancelCount = 0;
  Completer<bool>? gate;

  @override
  Future<void> present(SmsOtpHit hit) async => deliver(hit);

  @override
  Future<bool> deliver(SmsOtpHit hit) async {
    codes.add(hit.code);
    if (!entered.isCompleted) entered.complete();
    return gate?.future ?? accepted;
  }

  @override
  Future<void> cancelPending() async => cancelCount += 1;
}

final class _Repo implements SmsRepository {
  List<SmsContact> snapshot = [];
  Completer<List<SmsContact>>? nextGate;
  Duration delay = Duration.zero;

  @override
  Future<List<SmsContact>> fetchContacts({RequestCancellation? cancellation}) {
    final gate = nextGate;
    nextGate = null;
    if (gate != null) return gate.future;
    final captured = List<SmsContact>.of(snapshot);
    if (delay != Duration.zero) {
      return Future<List<SmsContact>>.delayed(delay, () => captured);
    }
    return Future<List<SmsContact>>.value(captured);
  }

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) async => SmsThreadPage(messages: [], hasMore: false);

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
