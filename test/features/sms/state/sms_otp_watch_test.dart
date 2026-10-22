import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/features/sms/data/ios_apns_bridge.dart';
import 'package:onewifi_android/features/sms/data/ios_push_endpoint_client.dart';
import 'package:onewifi_android/features/sms/data/remote_otp_pairing_store.dart';
import 'package:onewifi_android/features/sms/data/remote_otp_stream_client.dart';
import 'package:onewifi_android/features/sms/data/sms_repository.dart';
import 'package:onewifi_android/features/sms/domain/remote_otp_pairing.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/state/remote_otp_controller.dart';
import 'package:onewifi_android/features/sms/state/sms_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'persisted same-origin pairing suppresses delayed polling before restore',
    () async {
      final h = _PairedHarness();
      addTearDown(h.close);
      await h.controller.pollOtpInbox();
      await h.store.write(_endpoint());
      expect(h.remote.state.paired, isFalse);
      h.repo.contact = _numberedOtp(11);

      await h.controller.pollOtpInbox();

      expect(h.controller.contacts.lastGoodData!.single.lastSmsId, 11);
      expect(h.sink.hits, isEmpty);
      expect(h.controller.lastOtpHit, isNull);
    },
  );

  test('a different paired gateway keeps local polling alerts', () async {
    final h = _PairedHarness();
    addTearDown(h.close);
    await h.store.write(_endpoint('https://other-gateway.test'));
    await h.controller.pollOtpInbox();
    h.repo.contact = _numberedOtp(11);
    await h.controller.pollOtpInbox();
    await h.controller.pollOtpInbox();
    expect(h.sink.hits.single.code, '100011');
  });

  test('same-origin pairing still owns alerts while SSE retries', () async {
    final h = _PairedHarness();
    addTearDown(h.close);
    h.mockApns();
    await h.controller.pollOtpInbox();
    await h.store.write(_endpoint());
    await h.remote.restore();
    await _until(() => h.client.events.hasListener);
    h.client.events.addError(StateError('offline'));
    await _until(() => h.remote.state.status == RemoteOtpStatus.retrying);
    h.repo.contact = _numberedOtp(11);
    await h.controller.pollOtpInbox();
    expect(h.sink.hits, isEmpty);
    expect(h.controller.contacts.lastGoodData!.single.lastSmsId, 11);
  });

  test('disconnect seeds old snapshot then delivers the next new ID', () async {
    final h = _PairedHarness();
    addTearDown(h.close);
    await h.store.write(_endpoint());
    await h.controller.pollOtpInbox();
    h.repo.contact = _numberedOtp(11);
    await h.controller.pollOtpInbox();
    await h.remote.disconnect();
    // An older disconnect snapshot must not roll back the paired cursor.
    h.repo.contact = _numberedOtp(10);
    await h.controller.pollOtpInbox();
    h.repo.contact = _numberedOtp(11);
    await h.controller.pollOtpInbox();
    expect(h.sink.hits, isEmpty);
    h.repo.contact = _numberedOtp(12);
    await h.controller.pollOtpInbox();
    expect(h.sink.hits.single.code, '100012');
  });

  test(
    'disconnect while polling paused seeds unseen history on resume',
    () async {
      final h = _PairedHarness();
      addTearDown(h.close);
      h.mockApns();
      await h.store.write(_endpoint());
      await h.controller.pollOtpInbox();
      h.controller.stopOtpWatch();
      await h.remote.disconnect();
      h.repo.contact = _numberedOtp(11);
      h.controller.startOtpWatch();
      await h.controller.pollOtpInbox();
      expect(h.sink.hits, isEmpty);
      h.repo.contact = _numberedOtp(12);
      await h.controller.pollOtpInbox();
      expect(h.sink.hits.single.code, '100012');
    },
  );

  for (final source in ['store', 'origin']) {
    test(
      '$source read failure leaves ingestion retryable and unconsumed',
      () async {
        final h = _PairedHarness();
        addTearDown(h.close);
        // An unrelated pairing ensures the origin provider is consulted while
        // local notifications remain the owner after recovery.
        await h.store.write(_endpoint('https://other-gateway.test'));
        await h.controller.pollOtpInbox();
        h.repo.contact = _numberedOtp(11);
        if (source == 'store') {
          h.store.error = StateError('storage unavailable');
        } else {
          h.originError = StateError('origin unavailable');
        }
        await h.controller.pollOtpInbox();
        expect(h.sink.hits, isEmpty);
        expect(h.controller.contacts.lastGoodData!.single.lastSmsId, 11);
        h.store.error = null;
        h.originError = null;
        await h.controller.pollOtpInbox();
        await h.controller.pollOtpInbox();
        expect(h.sink.hits.single.code, '100011');
      },
    );

    for (final lifecycle in ['stop', 'dispose']) {
      test('pending $source query cannot mutate after $lifecycle', () async {
        final h = _PairedHarness();
        addTearDown(h.close);
        await h.store.write(_endpoint('https://other-gateway.test'));
        await h.controller.pollOtpInbox();
        h.repo.contact = _numberedOtp(11);
        final entered = Completer<void>();
        final release = Completer<void>();
        if (source == 'store') {
          h.store.readOverride = () async {
            entered.complete();
            await release.future;
            return _endpoint();
          };
        } else {
          h.originOverride = () async {
            entered.complete();
            await release.future;
            return Uri.parse('https://other-gateway.test');
          };
        }
        final polling = h.controller.pollOtpInbox();
        await entered.future;
        if (lifecycle == 'stop') {
          h.controller.stopOtpWatch();
        } else {
          h.controller.dispose();
          h.disposed = true;
        }
        release.complete();
        await polling;
        expect(h.sink.hits, isEmpty);
        expect(h.controller.lastOtpHit, isNull);
        if (lifecycle == 'stop') {
          h.store.readOverride = null;
          h.originOverride = null;
          // Stale query must neither consume ID 11 nor change ownership to
          // remote (which would incorrectly seed this fresh local snapshot).
          await h.controller.pollOtpInbox();
          expect(h.sink.hits.single.code, '100011');
        }
      });
    }
  }

  test(
    'pairing during pending delivery suppresses later batch items',
    () async {
      final h = _PairedHarness();
      addTearDown(h.close);
      await h.controller.pollOtpInbox();
      h.repo.snapshot = [
        _numberedOtp(11),
        _numberedOtp(12, inboxKey: 'modem-b'),
      ];
      final pending = Completer<bool>();
      h.sink.pending = pending;
      final polling = h.controller.pollOtpInbox();
      await _until(() => h.sink.hits.isNotEmpty);
      await h.store.write(_endpoint());
      pending.complete(true);
      await polling;
      expect(h.sink.hits.map((hit) => hit.code), ['100011']);
      await h.remote.disconnect();
      h.sink.pending = null;
      await h.controller.pollOtpInbox();
      h.repo.snapshot = [_numberedOtp(13, inboxKey: 'modem-b')];
      await h.controller.pollOtpInbox();
      expect(h.sink.hits.map((hit) => hit.code), ['100011', '100013']);
    },
  );

  test('unpaired controller retries failed local delivery', () async {
    final h = _PairedHarness();
    addTearDown(h.close);
    await h.controller.pollOtpInbox();
    h.repo.contact = _numberedOtp(11);
    h.sink.error = StateError('sink unavailable');
    await h.controller.pollOtpInbox();
    expect(h.controller.lastOtpHit, isNull);
    h.sink.error = null;
    await h.controller.pollOtpInbox();
    await h.controller.pollOtpInbox();
    expect(h.sink.hits, hasLength(2));
    expect(h.controller.lastOtpHit?.code, '100011');
  });

  test('existing OTP on the first snapshot is not pushed', () async {
    final sink = _Sink();
    final repo = _Repo(
      _otpContact(
        preview: '【京东】验证码�?23456�?分钟内有效�?,
        at: DateTime.utc(2026, 9, 10, 8),
      ),
    );
    final controller = SmsController(
      repository: repo,
      requestRegistry: RequestRegistry(),
      otpSink: sink,
    );
    addTearDown(controller.dispose);

    await controller.pollOtpInbox(seed: true);

    expect(sink.hits, isEmpty);
    expect(controller.lastOtpHit, isNull);
  });

  test('a newer OTP after seed is presented once', () async {
    final sink = _Sink();
    final repo = _Repo(
      _otpContact(preview: 'hello', at: DateTime.utc(2026, 9, 10, 8)),
    );
    final controller = SmsController(
      repository: repo,
      requestRegistry: RequestRegistry(),
      otpSink: sink,
    );
    addTearDown(controller.dispose);

    await controller.pollOtpInbox(seed: true);
    repo.contact = _otpContact(
      preview: '【京东】验证码�?54321�?分钟内有效�?,
      at: DateTime.utc(2026, 9, 10, 8, 1),
    );
    await controller.pollOtpInbox();
    await controller.pollOtpInbox();

    expect(sink.hits, hasLength(1));
    expect(sink.hits.single.code, '654321');
    expect(sink.hits.single.senderDisplay, '•••�?1234');
    expect(controller.lastOtpHit?.code, '654321');
  });

  test('plain SMS after seed is ignored', () async {
    final sink = _Sink();
    final repo = _Repo(
      _otpContact(preview: 'hello', at: DateTime.utc(2026, 9, 10, 8)),
    );
    final controller = SmsController(
      repository: repo,
      requestRegistry: RequestRegistry(),
      otpSink: sink,
    );
    addTearDown(controller.dispose);

    await controller.pollOtpInbox(seed: true);
    repo.contact = _otpContact(
      preview: '您的包裹已签�?,
      at: DateTime.utc(2026, 9, 10, 8, 1),
    );
    await controller.pollOtpInbox();

    expect(sink.hits, isEmpty);
  });

  test('disabled watch does not present', () async {
    final sink = _Sink();
    final repo = _Repo(
      _otpContact(preview: 'hello', at: DateTime.utc(2026, 9, 10, 8)),
    );
    final controller = SmsController(
      repository: repo,
      requestRegistry: RequestRegistry(),
      otpSink: sink,
    );
    addTearDown(controller.dispose);

    await controller.pollOtpInbox(seed: true);
    controller.setOtpWatchEnabled(false);
    repo.contact = _otpContact(
      preview: '验证�?111222',
      at: DateTime.utc(2026, 9, 10, 8, 1),
    );
    await controller.pollOtpInbox();

    expect(sink.hits, isEmpty);
    expect(controller.otpWatchEnabled, isFalse);
  });

  test(
    'turning watch off, reloading contacts, then on does not present history',
    () async {
      final sink = _Sink();
      final repo = _Repo(
        _otpContact(
          preview: '【京东】验证码�?23456�?分钟内有效�?,
          at: DateTime.utc(2026, 9, 10, 8),
        ),
      );
      final controller = SmsController(
        repository: repo,
        requestRegistry: RequestRegistry(),
        otpSink: sink,
      );
      addTearDown(controller.dispose);

      await controller.pollOtpInbox(seed: true);
      controller.setOtpWatchEnabled(false);
      await controller.loadContacts();
      controller.setOtpWatchEnabled(true);
      await controller.pollOtpInbox();

      expect(sink.hits, isEmpty);
    },
  );
}

final class _Sink implements SmsOtpSink {
  final List<SmsOtpHit> hits = <SmsOtpHit>[];

  @override
  Future<void> present(SmsOtpHit hit) async => hits.add(hit);
}

final class _Target implements SmsContactTarget {
  const _Target();
}

SmsContact _otpContact({
  required String preview,
  required DateTime at,
  int? id,
  String inboxKey = 'modem-a',
}) {
  return SmsContact(
    peerDisplay: '•••�?1234',
    localPhoneDisplay: '•••�?9999',
    iccidDisplay: '•••�?8888',
    deviceName: 'Travel modem',
    preview: preview,
    messageCount: 1,
    unreadCount: 1,
    lastTimestamp: at,
    target: const _Target(),
    inboxKey: inboxKey,
    lastSmsId: id,
  );
}

final class _Repo implements SmsRepository {
  _Repo(this.contact);

  SmsContact contact;
  List<SmsContact>? snapshot;

  @override
  Future<List<SmsContact>> fetchContacts({
    RequestCancellation? cancellation,
  }) async => snapshot ?? <SmsContact>[contact];

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

RemoteOtpEndpoint _endpoint([String url = 'https://gateway.test']) =>
    RemoteOtpEndpoint(baseUrl: Uri.parse(url), token: 'test-token');

SmsContact _numberedOtp(int id, {String inboxKey = 'modem-a'}) => _otpContact(
  preview: 'Verification code: ${100000 + id}',
  at: DateTime.utc(2026, 9, 10, 8, 0, id),
  id: id,
  inboxKey: inboxKey,
);

final class _PairedHarness {
  final store = _PairingStore();
  final sink = _DeliverySink();
  final repo = _Repo(_numberedOtp(10));
  final client = _StreamClient();
  final channel = const MethodChannel('test/polling-otp-apns');
  Object? originError;
  Future<Uri> Function()? originOverride;
  bool disposed = false;
  late final remote = RemoteOtpController(
    store: store,
    streamClient: RemoteOtpStreamClient(client),
    pushClient: IosPushEndpointClient(client),
    apns: IosApnsBridge(channel: channel),
    otpSink: sink,
    pollingOriginProvider: () async {
      if (originError != null) throw originError!;
      return originOverride == null
          ? Uri.parse('https://gateway.test')
          : await originOverride!();
    },
  );
  late final controller = SmsController(
    repository: repo,
    requestRegistry: RequestRegistry(),
    otpSink: sink,
    remoteOtp: remote,
  );

  Future<void> close() async {
    if (!disposed) controller.dispose();
    await client.events.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }

  void mockApns() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'drain'
              ? <Object>[]
              : <String, Object>{
                  'authorization': 'authorized',
                  'alerts_enabled': true,
                },
        );
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('The expected asynchronous boundary was not reached');
}

final class _DeliverySink implements SmsOtpSink, SmsOtpDeliverySink {
  final hits = <SmsOtpHit>[];
  Completer<bool>? pending;
  Object? error;

  @override
  Future<bool> deliver(SmsOtpHit hit) async {
    hits.add(hit);
    if (error != null) throw error!;
    return pending == null ? true : await pending!.future;
  }

  @override
  Future<void> present(SmsOtpHit hit) async {
    await deliver(hit);
  }

  @override
  Future<void> cancelPending() async {}
}

final class _StreamClient extends http.BaseClient {
  final events = StreamController<List<int>>.broadcast();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(events.stream, 200);
}

final class _PairingStore implements RemoteOtpPairingStore {
  RemoteOtpEndpoint? endpoint;
  Object? error;
  Future<RemoteOtpEndpoint?> Function()? readOverride;
  int lastEventId = 0;
  int lastPushId = 0;
  @override
  Future<RemoteOtpEndpoint?> read() async {
    if (error != null) throw error!;
    return readOverride == null ? endpoint : await readOverride!();
  }

  @override
  Future<void> write(RemoteOtpEndpoint value) async {
    endpoint = value;
    lastEventId = 0;
    lastPushId = 0;
  }

  @override
  Future<void> clear() async {
    endpoint = null;
    lastEventId = 0;
    lastPushId = 0;
  }

  @override
  Future<int> readLastEventId() async => lastEventId;
  @override
  Future<void> writeLastEventId(int value) async {
    if (value > lastEventId) lastEventId = value;
  }

  @override
  Future<int> readLastAcknowledgedPushId() async => lastPushId;
  @override
  Future<void> writeLastAcknowledgedPushId(int value) async {
    if (value > lastPushId) lastPushId = value;
  }
}
