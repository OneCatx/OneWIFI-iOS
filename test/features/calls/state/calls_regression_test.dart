import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/features/calls/data/call_handset.dart';
import 'package:onewifi_android/features/calls/data/calls_repository.dart';
import 'package:onewifi_android/features/calls/domain/call.dart';
import 'package:onewifi_android/features/calls/presentation/calls_screen.dart';
import 'package:onewifi_android/features/calls/state/calls_controller.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/state/device_list_controller.dart';

const aCall = VoiceCall(
  id: 'call-A',
  deviceId: 'A',
  number: '10086',
  direction: CallDirection.incoming,
  state: CallLifecycle.ringing,
);
const meta = CallMediaMeta(
  id: 'call-A',
  codec: 'PCM',
  format: 'pcm',
  stream: '',
);

void main() {
  CallsController create(
    _Repo repo, {
    Future<Uri> Function()? originProvider,
    Future<String?> Function(Uri)? tokenProvider,
  }) {
    final c = CallsController(
      repository: repo,
      originProvider:
          originProvider ?? () async => Uri.parse('http://127.0.0.1:1'),
      tokenProvider: tokenProvider ?? (_) async => 'fake-token',
      requestRegistry: RequestRegistry(),
      handset: SilentCallHandset(),
    );
    addTearDown(() async {
      c.dispose();
      for (final socket in repo.sockets) {
        if (!socket.events.isClosed) await socket.close();
      }
    });
    return c;
  }

  test('same-device hangup is the passing control', () async {
    final repo = _Repo();
    final c = create(repo)..selectDevice('A');
    await c.refresh();
    await c.hangup(c.liveCalls.single);
    expect(repo.hangups, [('A', 'call-A')]);
  });

  testWidgets('cold calls entry must request its device list', (tester) async {
    final repository = _Devices();
    final devices = DeviceListController(
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(devices.dispose);
    final calls = create(_Repo());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallsScreen(calls: calls, devices: devices),
        ),
      ),
    );
    await tester.pump();
    final count = repository.loads;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(count, greaterThan(0));
  });

  test('device switch must not expose previous device actions', () async {
    final c = create(_Repo())..selectDevice('A');
    await c.refresh();
    expect(c.liveCalls.single.deviceId, 'A');
    c.selectDevice('B');
    expect(c.liveCalls.where((x) => x.deviceId != c.deviceId), isEmpty);
  });

  test('stale call must never be posted to newly selected device', () async {
    final repo = _Repo();
    final c = create(repo)..selectDevice('A');
    await c.refresh();
    final previousCall = c.liveCalls.single;
    c.selectDevice('B');
    await c.hangup(previousCall);
    expect(repo.hangups, isNot(contains(('B', 'call-A'))));
  });

  test('dispose during metadata must not continue socket opening', () async {
    final repo = _Repo()..metadataGate = Completer<CallMediaMeta>();
    final c = create(repo)..selectDevice('A');
    final pending = c.ensureMedia(aCall);
    await repo.metadataStarted.future;
    c.dispose();
    repo.metadataGate!.complete(meta);
    await pending;
    expect(repo.socketOpens, 0);
  });

  test('socket arriving after dispose must be closed', () async {
    final repo = _Repo()..socketGate = Completer<WebSocket>();
    final c = create(repo)..selectDevice('A');
    final pending = c.ensureMedia(aCall);
    await repo.socketStarted.future;
    c.dispose();
    final socket = repo.sockets.single;
    repo.socketGate!.complete(socket);
    await pending;
    expect(socket.closeCount, 1);
  });

  test('same-device answer and media remain usable', () async {
    final repo = _Repo();
    final c = create(repo)..selectDevice('A');
    await c.answer(aCall);
    await c.ensureMedia(aCall);
    expect(repo.answers, [('A', 'call-A')]);
    expect(c.mediaConnected, isTrue);
    repo.sockets.single.dataCallback!([1, 2, 3]);
    expect(c.pcmBytes, 3);
  });

  test(
    'a stale answer or media request does not target the new device',
    () async {
      final repo = _Repo();
      final c = create(repo)..selectDevice('A');
      c.selectDevice('B');
      await c.answer(aCall);
      await c.ensureMedia(aCall);
      expect(repo.answers, isEmpty);
      expect(repo.metadataLoads, 0);
    },
  );

  test('device switch cancels writes and ignores their late success', () async {
    final repo = _Repo()..hangupGate = Completer<void>();
    final c = create(repo)..selectDevice('A');
    final pending = c.hangup(aCall);
    final cancellation = repo.hangupCancellation;
    c.selectDevice('B');
    expect(cancellation?.isCancelled, isTrue);
    repo.hangupGate!.complete();
    await pending;
    expect(c.notice, isEmpty);
    expect(c.deviceId, 'B');
  });

  test('device switch rejects a late previous-device list', () async {
    final repo = _Repo()..aCallsGate = Completer<List<VoiceCall>>();
    final c = create(repo)..selectDevice('A');
    final pending = c.refresh();
    c.selectDevice('B');
    repo.aCallsGate!.complete([aCall]);
    await pending;
    expect(c.items, isEmpty);
  });

  test(
    'device switch during list notification cannot cancel the new media',
    () async {
      final repo = _Repo()..aCallsGate = Completer<List<VoiceCall>>();
      final c = create(repo)..selectDevice('A');
      Future<void>? newMedia;
      c.addListener(() {
        if (c.deviceId != 'A' || c.items.isEmpty) return;
        c.selectDevice('B');
        newMedia = c.ensureMedia(
          const VoiceCall(
            id: 'call-B',
            deviceId: 'B',
            number: '10010',
            direction: CallDirection.incoming,
            state: CallLifecycle.active,
          ),
        );
      });
      final pending = c.refresh();
      repo.aCallsGate!.complete([aCall]);
      await pending;
      await newMedia;
      expect(c.deviceId, 'B');
      expect(c.mediaConnected, isTrue);
    },
  );

  testWidgets('slow polling keeps a single live request', (tester) async {
    final repo = _Repo()..aCallsGate = Completer<List<VoiceCall>>();
    final c = create(repo)..selectDevice('A');
    final first = c.refresh();
    final second = c.refresh(quiet: true);
    await tester.pump(const Duration(seconds: 6));
    expect(repo.listLoads, 1);
    expect(repo.listCancellations.single?.isCancelled, isFalse);
    repo.aCallsGate!.complete([aCall]);
    await first;
    await second;
    expect(c.items, [aCall]);
    c.dispose();
  });

  testWidgets('PERF-P3: poll stops when UI inactive and resumes on active', (
    tester,
  ) async {
    final repo = _Repo();
    final c = create(repo);
    c.setPollUiActive(true);
    c.selectDevice('A');
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    final armedLoads = repo.listLoads;
    expect(armedLoads, greaterThanOrEqualTo(2));
    c.setPollUiActive(false);
    await tester.pump(const Duration(seconds: 5));
    expect(repo.listLoads, armedLoads);
    c.setPollUiActive(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(repo.listLoads, greaterThan(armedLoads));
    c.dispose();
  });

  test('parallel media requests share the same pending connection', () async {
    final repo = _Repo()..metadataGate = Completer<CallMediaMeta>();
    final c = create(repo)..selectDevice('A');
    final first = c.ensureMedia(aCall);
    final second = c.ensureMedia(aCall);
    repo.metadataGate!.complete(meta);
    await Future.wait([first, second]);
    expect(repo.metadataLoads, 1);
    expect(repo.socketOpens, 1);
    expect(c.mediaConnected, isTrue);
  });

  test('device switch during metadata stops media connection', () async {
    final repo = _Repo()..metadataGate = Completer<CallMediaMeta>();
    final c = create(repo)..selectDevice('A');
    final pending = c.ensureMedia(aCall);
    await repo.metadataStarted.future;
    c.selectDevice('B');
    repo.metadataGate!.complete(meta);
    await pending;
    expect(repo.socketOpens, 0);
    expect(repo.metadataCancellation?.isCancelled, isTrue);
  });

  test(
    'dispose during origin lookup stops token and socket requests',
    () async {
      final repo = _Repo();
      final originStarted = Completer<void>();
      final origin = Completer<Uri>();
      var tokenReads = 0;
      final c = create(
        repo,
        originProvider: () {
          originStarted.complete();
          return origin.future;
        },
        tokenProvider: (_) async {
          tokenReads++;
          return 'test-token';
        },
      )..selectDevice('A');
      final pending = c.ensureMedia(aCall);
      await originStarted.future;
      c.dispose();
      origin.complete(Uri.parse('http://127.0.0.1'));
      await pending;
      expect(tokenReads, 0);
      expect(repo.socketOpens, 0);
    },
  );

  test('dispose during token lookup stops socket requests', () async {
    final repo = _Repo();
    final tokenStarted = Completer<void>();
    final token = Completer<String?>();
    final c = create(
      repo,
      tokenProvider: (_) {
        tokenStarted.complete();
        return token.future;
      },
    )..selectDevice('A');
    final pending = c.ensureMedia(aCall);
    await tokenStarted.future;
    c.dispose();
    token.complete('test-token');
    await pending;
    expect(repo.socketOpens, 0);
  });

  test(
    'late callbacks from a replaced socket cannot modify the new one',
    () async {
      final repo = _Repo();
      final c = create(repo)..selectDevice('A');
      await c.ensureMedia(aCall);
      final old = repo.sockets.single;
      c.selectDevice('B');
      await c.ensureMedia(
        const VoiceCall(
          id: 'call-A',
          deviceId: 'B',
          number: '10010',
          direction: CallDirection.incoming,
          state: CallLifecycle.active,
        ),
      );
      old.dataCallback!([1, 2, 3]);
      old.doneCallback!();
      expect(c.pcmBytes, 0);
      expect(c.mediaConnected, isTrue);
    },
  );

  test('normal call completion closes its media connection', () async {
    final repo = _Repo();
    final c = create(repo)..selectDevice('A');
    await c.refresh();
    await c.ensureMedia(aCall);
    final socket = repo.sockets.single;
    repo.aCalls = const [
      VoiceCall(
        id: 'call-A',
        deviceId: 'A',
        number: '10086',
        direction: CallDirection.incoming,
        state: CallLifecycle.ended,
      ),
    ];
    await c.refresh();
    expect(c.mediaConnected, isFalse);
    expect(c.mediaMeta, isNull);
    expect(socket.closeCount, 1);
  });

  test(
    'late socket from a previous device closes without replacing current media',
    () async {
      final oldGate = Completer<WebSocket>();
      final repo = _Repo()..socketGate = oldGate;
      final c = create(repo)..selectDevice('A');
      final pending = c.ensureMedia(aCall);
      await repo.socketStarted.future;
      final oldSocket = repo.sockets.single;
      c.selectDevice('B');
      repo.socketGate = null;
      await c.ensureMedia(
        const VoiceCall(
          id: 'call-A',
          deviceId: 'B',
          number: '10010',
          direction: CallDirection.incoming,
          state: CallLifecycle.active,
        ),
      );
      oldGate.complete(oldSocket);
      await pending;
      expect(oldSocket.closeCount, 1);
      expect(repo.sockets.last.closeCount, 0);
      expect(c.mediaConnected, isTrue);
    },
  );

  test('media failure can retry and ended calls cannot open media', () async {
    final gate = Completer<CallMediaMeta>();
    final repo = _Repo()..metadataGate = gate;
    final c = create(repo)..selectDevice('A');
    final pending = c.ensureMedia(aCall);
    await repo.metadataStarted.future;
    gate.completeError(StateError('metadata unavailable'));
    await pending;
    expect(c.noticeError, isTrue);
    expect(c.mediaConnected, isFalse);
    repo.metadataGate = null;
    await c.ensureMedia(aCall);
    expect(c.mediaConnected, isTrue);
    await c.ensureMedia(
      const VoiceCall(
        id: 'ended',
        deviceId: 'A',
        number: '10010',
        direction: CallDirection.incoming,
        state: CallLifecycle.ended,
      ),
    );
    expect(repo.socketOpens, 1);
  });

  test('socket errors close the resource and allow reconnection', () async {
    final repo = _Repo();
    final c = create(repo)..selectDevice('A');
    await c.ensureMedia(aCall);
    final socket = repo.sockets.single;
    Function.apply(socket.errorCallback!, [StateError('connection lost')]);
    expect(c.mediaConnected, isFalse);
    expect(socket.closeCount, 1);
    await c.ensureMedia(aCall);
    expect(c.mediaConnected, isTrue);
    expect(repo.socketOpens, 2);
  });

  test('dial and answer cancellations follow their captured device', () async {
    final repo = _Repo()
      ..dialGate = Completer<VoiceCall>()
      ..answerGate = Completer<VoiceCall>();
    final c = create(repo)..selectDevice('A');
    c.setDialNumber('10086');
    final dialing = c.dial();
    final answering = c.answer(aCall);
    c.selectDevice('B');
    expect(repo.dialCancellation?.isCancelled, isTrue);
    expect(repo.answerCancellation?.isCancelled, isTrue);
    repo.dialGate!.complete(aCall);
    repo.answerGate!.complete(aCall);
    await Future.wait([dialing, answering]);
    expect(c.notice, isEmpty);
    expect(repo.dials, [('A', '10086')]);
    expect(repo.answers, [('A', 'call-A')]);
  });

  test('duplicate hangup while submitting does not repeat the write', () async {
    final repo = _Repo()..hangupGate = Completer<void>();
    final c = create(repo)..selectDevice('A');
    final pending = c.hangup(aCall);
    await c.hangup(aCall);
    expect(repo.hangups, [('A', 'call-A')]);
    repo.hangupGate!.complete();
    await pending;
    expect(c.notice, '已挂断');
  });

  test(
    'disposing media does not notify consumers during their teardown',
    () async {
      final repo = _Repo();
      final c = create(repo)..selectDevice('A');
      await c.ensureMedia(aCall);
      var notifications = 0;
      c.addListener(() => notifications++);
      c.dispose();
      expect(notifications, 0);
      expect(repo.sockets.single.closeCount, 1);
    },
  );

  testWidgets('controller replacement updates listeners and loads devices', (
    tester,
  ) async {
    final oldCalls = create(_Repo());
    final newCalls = create(_Repo());
    final oldDevices = DeviceListController(
      repository: _Devices(),
      requestRegistry: RequestRegistry(),
    );
    final newRepository = _Devices();
    final newDevices = DeviceListController(
      repository: newRepository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(oldDevices.dispose);
    addTearDown(newDevices.dispose);
    Widget screen(CallsController calls, DeviceListController devices) =>
        MaterialApp(
          home: Scaffold(
            body: CallsScreen(calls: calls, devices: devices),
          ),
        );
    await tester.pumpWidget(screen(oldCalls, oldDevices));
    await tester.pump();
    await tester.pumpWidget(screen(newCalls, newDevices));
    await tester.pump();
    newCalls.setDialNumber('12345');
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const Key('calls-dial-field')),
    );
    expect(field.controller!.text, '12345');
    expect(newRepository.loads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Repo implements CallsRepository {
  final bCalls = Completer<List<VoiceCall>>();
  Completer<CallMediaMeta>? metadataGate;
  Completer<WebSocket>? socketGate;
  Completer<void>? hangupGate;
  Completer<VoiceCall>? dialGate;
  Completer<VoiceCall>? answerGate;
  Completer<List<VoiceCall>>? aCallsGate;
  List<VoiceCall> aCalls = [aCall];
  RequestCancellation? hangupCancellation;
  RequestCancellation? dialCancellation;
  RequestCancellation? answerCancellation;
  RequestCancellation? metadataCancellation;
  final listCancellations = <RequestCancellation?>[];
  final socketStarted = Completer<void>();
  final metadataStarted = Completer<void>();
  final sockets = <_Socket>[];
  final hangups = <(String, String)>[];
  final answers = <(String, String)>[];
  final dials = <(String, String)>[];
  int socketOpens = 0;
  int metadataLoads = 0;
  int listLoads = 0;

  @override
  Future<List<VoiceCall>> fetchCalls(
    String id, {
    RequestCancellation? cancellation,
  }) {
    listLoads++;
    listCancellations.add(cancellation);
    return id == 'B'
        ? bCalls.future
        : aCallsGate?.future ?? Future.value(aCalls);
  }

  @override
  Future<VoiceCall> dial(
    String id,
    String number, {
    RequestCancellation? cancellation,
  }) {
    dials.add((id, number));
    dialCancellation = cancellation;
    return dialGate?.future ?? Future.value(aCall);
  }

  @override
  Future<VoiceCall> answer(
    String id,
    String callId, {
    RequestCancellation? cancellation,
  }) {
    answers.add((id, callId));
    answerCancellation = cancellation;
    return answerGate?.future ?? Future.value(aCall);
  }

  @override
  Future<void> hangup(
    String id,
    String callId, {
    RequestCancellation? cancellation,
  }) async {
    hangups.add((id, callId));
    hangupCancellation = cancellation;
    await hangupGate?.future;
  }

  @override
  Future<CallMediaMeta> fetchMediaMeta(
    String id,
    String callId, {
    RequestCancellation? cancellation,
  }) {
    metadataLoads++;
    if (!metadataStarted.isCompleted) metadataStarted.complete();
    metadataCancellation = cancellation;
    return metadataGate?.future ?? Future.value(meta);
  }

  @override
  Future<void> sendDtmf(
    String deviceId,
    String callId, {
    String? digit,
    String? digits,
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<CallMediaTicket> createMediaTicket(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async => const CallMediaTicket(ticket: 't', expiresInSeconds: 60);

  @override
  Future<List<CallHistoryEntry>> fetchHistory(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async => const <CallHistoryEntry>[];

  @override
  Future<CallMediaCapabilities> fetchMediaCapabilities({
    RequestCancellation? cancellation,
  }) async => const CallMediaCapabilities(
    preferred: 'websocket',
    webrtcEnabled: false,
    websocketEnabled: true,
  );

  @override
  Future<WebSocket> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  }) {
    socketOpens++;
    final socket = _Socket();
    sockets.add(socket);
    if (!socketStarted.isCompleted) socketStarted.complete();
    return socketGate?.future ?? Future.value(socket);
  }
}

class _Socket implements WebSocket {
  final events = StreamController<dynamic>.broadcast();
  void Function(dynamic)? dataCallback;
  void Function()? doneCallback;
  Function? errorCallback;
  int closeCount = 0;
  @override
  Future<void> close([int? code, String? reason]) async {
    closeCount++;
    if (!events.isClosed) await events.close();
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    dataCallback = onData;
    doneCallback = onDone;
    errorCallback = onError;
    return events.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Devices implements DeviceRepository {
  int loads = 0;
  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) async {
    loads++;
    return DeviceFleet(deviceLimit: 1, devices: []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<List<DiscoveredDevice>> fetchDiscoveredDevices({
    RequestCancellation? cancellation,
  }) async => const <DiscoveredDevice>[];

  @override
  Future<DeviceRescanResult> rescanDevices({
    RequestCancellation? cancellation,
  }) async => const DeviceRescanResult(status: 'ok', devicesCount: 0);

  @override
  Future<void> registerDevice({
    required String deviceId,
    required String discoveryKey,
    required String deviceType,
    String? name,
    String? simPin,
    Map<String, Object?>? additionalConfig,
    RequestCancellation? cancellation,
  }) async {}
}
