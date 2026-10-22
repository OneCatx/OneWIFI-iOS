import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';
import 'package:onewifi_android/features/calls/data/call_handset.dart';
import 'package:onewifi_android/features/calls/data/calls_repository.dart';
import 'package:onewifi_android/features/calls/domain/call.dart';
import 'package:onewifi_android/features/calls/state/calls_controller.dart';

/// P4 通话旧黄金路径：选设备 → refresh → dial/answer/hangup；401 鉴权映射。
void main() {
  const ringing = VoiceCall(
    id: 'call-A',
    deviceId: 'device-a',
    number: '10086',
    direction: CallDirection.incoming,
    state: CallLifecycle.ringing,
  );

  CallsController create(_Repo repo) {
    final controller = CallsController(
      repository: repo,
      originProvider: () async => Uri.parse('http://127.0.0.1:1'),
      tokenProvider: (_) async => 'fake-token',
      requestRegistry: RequestRegistry(),
      handset: SilentCallHandset(),
    );
    addTearDown(() async {
      controller.dispose();
      for (final socket in repo.sockets) {
        if (!socket.events.isClosed) await socket.close();
      }
    });
    return controller;
  }

  group('list', () {
    test('selectDevice refresh lands live calls under calls key', () async {
      final repo = _Repo(calls: <VoiceCall>[ringing]);
      final controller = create(repo)..selectDevice('device-a');

      await controller.refresh();

      expect(controller.calls.status, QueryStatus.data);
      expect(controller.liveCalls.single.id, 'call-A');
    });

    test('refresh 401 maps to authentication and surfaces notice', () async {
      final repo = _Repo(
        listError: const ApiFailure(
          ApiFailureKind.http,
          requestId: 'calls-401',
          statusCode: 401,
          backendCode: 'unauthorized',
        ),
      );
      final controller = create(repo)..selectDevice('device-a');

      await controller.refresh();

      expect(controller.calls.status, QueryStatus.failed);
      expect(controller.calls.failure?.kind, StateFailureKind.authentication);
      expect(controller.noticeError, isTrue);
      expect(controller.notice, contains('无法拉取通话列表'));
    });
  });

  group('actions', () {
    test('dial → answer → hangup golden path', () async {
      final repo = _Repo(calls: <VoiceCall>[ringing]);
      final controller = create(repo)..selectDevice('device-a');
      await controller.refresh();

      controller.setDialNumber('10010');
      await controller.dial();
      expect(repo.dials, <(String, String)>[('device-a', '10010')]);
      expect(controller.notice, '已拨出');

      await controller.answer(ringing);
      expect(repo.answers, <(String, String)>[('device-a', 'call-A')]);
      expect(controller.notice, '已接听');

      await controller.hangup(ringing);
      expect(repo.hangups, <(String, String)>[('device-a', 'call-A')]);
      expect(controller.notice, '已挂断');
    });

    test('hangup is single-flight while submitting', () async {
      final repo = _Repo(calls: <VoiceCall>[ringing])
        ..hangupGate = Completer<void>();
      final controller = create(repo)..selectDevice('device-a');

      final pending = controller.hangup(ringing);
      await controller.hangup(ringing);
      expect(repo.hangups, <(String, String)>[('device-a', 'call-A')]);

      repo.hangupGate!.complete();
      await pending;
      expect(controller.notice, '已挂断');
    });
  });
}

final class _Repo implements CallsRepository {
  _Repo({this.calls = const <VoiceCall>[], this.listError});

  final List<VoiceCall> calls;
  final Object? listError;
  Completer<void>? hangupGate;
  final List<(String, String)> dials = <(String, String)>[];
  final List<(String, String)> answers = <(String, String)>[];
  final List<(String, String)> hangups = <(String, String)>[];
  final List<_Socket> sockets = <_Socket>[];

  @override
  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    final error = listError;
    if (error != null) throw error;
    return calls;
  }

  @override
  Future<VoiceCall> dial(
    String deviceId,
    String number, {
    RequestCancellation? cancellation,
  }) async {
    dials.add((deviceId, number));
    return VoiceCall(
      id: 'outbound',
      deviceId: deviceId,
      number: number,
      direction: CallDirection.outgoing,
      state: CallLifecycle.dialing,
    );
  }

  @override
  Future<VoiceCall> answer(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async {
    answers.add((deviceId, callId));
    return VoiceCall(
      id: callId,
      deviceId: deviceId,
      number: '10086',
      direction: CallDirection.incoming,
      state: CallLifecycle.active,
    );
  }

  @override
  Future<void> hangup(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async {
    hangups.add((deviceId, callId));
    await hangupGate?.future;
  }

  @override
  Future<CallMediaMeta> fetchMediaMeta(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async {
    return CallMediaMeta(
      id: callId,
      codec: 'PCM',
      format: 'pcm',
      stream: '',
    );
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
  }) async {
    final socket = _Socket();
    sockets.add(socket);
    return socket;
  }
}

class _Socket implements WebSocket {
  final events = StreamController<dynamic>.broadcast();
  int closeCount = 0;

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCount += 1;
    if (!events.isClosed) await events.close();
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
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
