import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/features/calls/data/call_handset.dart';
import 'package:onewifi_android/features/calls/data/calls_repository.dart';
import 'package:onewifi_android/features/calls/domain/call.dart';
import 'package:onewifi_android/features/calls/state/calls_controller.dart';

const call = VoiceCall(
  id: 'a',
  deviceId: 'A',
  number: '10086',
  direction: CallDirection.outgoing,
  state: CallLifecycle.active,
  mediaReady: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness h;
  setUp(() {
    h = _Harness();
  });
  tearDown(() async {
    h.controller.dispose();
    await Future<void>.delayed(Duration.zero);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(h.channel, null);
  });

  test(
    'native permission failure is visible and releases the media socket',
    () async {
      h.startError = PlatformException(code: 'mic_denied', message: '麦克风权限被拒绝');
      await h.connect();
      expect(h.controller.mediaConnected, isFalse);
      expect(h.controller.noticeError, isTrue);
      expect(h.controller.notice, contains('麦克风'));
      expect(h.repo.sockets.single.closeCount, 1);
      h.startError = null;
      await h.controller.ensureMedia(call);
      expect(h.controller.mediaConnected, isTrue);
      expect(h.repo.sockets.length, 2);
    },
  );

  test('native stop failure is contained and visible', () async {
    h.stopError = PlatformException(
      code: 'gone',
      message: 'audio bridge released',
    );
    await h.connect();
    expect(h.controller.mediaConnected, isFalse);
    expect(h.controller.noticeError, isTrue);
    expect(h.repo.sockets.every((socket) => socket.closeCount == 1), isTrue);
  });

  test('media is not connected before native startup completes', () async {
    h.startGate = Completer<void>();
    final connecting = h.connect();
    await h.started.future;
    expect(h.controller.mediaConnected, isFalse);
    h.startGate!.complete();
    await connecting;
    expect(h.controller.mediaConnected, isTrue);
  });

  for (final terminal in ['done', 'error', 'dispose', 'switch']) {
    test('$terminal stops native audio and closes the socket', () async {
      await h.connect();
      final socket = h.repo.sockets.single;
      final stops = h.methods.where((method) => method == 'stop').length;
      switch (terminal) {
        case 'done':
          socket.doneCallback!();
        case 'error':
          Function.apply(socket.error!, [StateError('lost')]);
        case 'dispose':
          h.controller.dispose();
        case 'switch':
          h.controller.selectDevice('B');
      }
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.mediaConnected, isFalse);
      expect(socket.closeCount, 1);
      expect(
        h.methods.where((method) => method == 'stop').length,
        greaterThan(stops),
      );
      if (terminal == 'done' || terminal == 'error') {
        await h.controller.ensureMedia(call);
        expect(h.controller.mediaConnected, isTrue);
        final newStops = h.methods.where((method) => method == 'stop').length;
        socket.doneCallback!();
        Function.apply(socket.error!, [StateError('stale')]);
        await Future<void>.delayed(Duration.zero);
        expect(h.controller.mediaConnected, isTrue);
        expect(h.methods.where((method) => method == 'stop').length, newStops);
      }
    });
  }

  test('late startup error cannot close replacement call audio', () async {
    h.startGate = Completer<void>();
    final old = h.connect();
    await h.started.future;
    final oldGate = h.startGate!;
    h.startGate = null;
    h.controller.selectDevice('B');
    await h.controller.refresh();
    await h.controller.ensureMedia(
      const VoiceCall(
        id: 'b',
        deviceId: 'B',
        number: '10010',
        direction: CallDirection.outgoing,
        state: CallLifecycle.active,
        mediaReady: true,
      ),
    );
    oldGate.completeError(PlatformException(code: 'cancelled'));
    await old;
    expect(h.controller.mediaConnected, isTrue);
    expect(h.controller.noticeError, isFalse);
    expect(h.repo.sockets.last.closeCount, 0);
  });

  test('dispose during native startup ignores late success', () async {
    h.startGate = Completer<void>();
    final pending = h.connect();
    await h.started.future;
    h.controller.dispose();
    h.startGate!.complete();
    await pending;
    expect(h.controller.mediaConnected, isFalse);
    expect(h.repo.sockets.single.closeCount, 1);
    await h.sendMic(Uint8List(320));
    expect(h.repo.sockets.single.sent, isEmpty);
  });

  test('second call sends full mic frames only to its own socket', () async {
    await h.connect();
    final first = h.repo.sockets.single;
    await h.sendMic(Uint8List(100));
    first.doneCallback!();
    await h.controller.ensureMedia(call);
    final second = h.repo.sockets.last;
    await h.sendMic(Uint8List(220));
    expect(
      second.sent,
      isEmpty,
      reason: 'No partial frame may leak across calls',
    );
    await h.sendMic(Uint8List(100));
    expect(first.sent, isEmpty);
    expect(second.sent.single, hasLength(320));
  });

  test('stop error after connected media still releases socket', () async {
    await h.connect();
    h.stopError = PlatformException(
      code: 'audio_stop',
      message: 'session busy',
    );
    h.repo.sockets.single.doneCallback!();
    await Future<void>.delayed(Duration.zero);
    expect(h.controller.mediaConnected, isFalse);
    expect(h.controller.noticeError, isTrue);
    expect(h.controller.notice, contains('session busy'));
    expect(h.repo.sockets.single.closeCount, 1);
  });

  test(
    'detach during attach initial stop prevents the obsolete start',
    () async {
      h.stopGate = Completer<void>();
      final attach = h.handset.attach(_Socket());
      await h.stopped.future;
      final detach = h.handset.detach();
      h.stopGate!.complete();
      await Future.wait([attach, detach]);
      expect(h.methods, isNot(contains('start')));
    },
  );
}

class _Harness {
  final channel = const MethodChannel('test/call-audio');
  final repo = _Repo();
  late final handset = ChannelCallHandset(channel: channel);
  late final controller = CallsController(
    repository: repo,
    originProvider: () async => Uri.parse('https://example.invalid'),
    tokenProvider: (_) async => 'test',
    requestRegistry: RequestRegistry(),
    handset: handset,
  );
  final methods = <String>[];
  final started = Completer<void>();
  final stopped = Completer<void>();
  Completer<void>? startGate;
  Completer<void>? stopGate;
  Object? startError;
  Object? stopError;
  _Harness() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          if (call.method == 'start') {
            if (!started.isCompleted) started.complete();
            await startGate?.future;
            if (startError != null) throw startError!;
          }
          if (call.method == 'stop') {
            if (!stopped.isCompleted) stopped.complete();
            await stopGate?.future;
            if (stopError != null) throw stopError!;
          }
          return null;
        });
  }
  Future<void> connect() async {
    controller.selectDevice('A');
    await controller.refresh();
    await controller.ensureMedia(call);
  }

  Future<void> sendMic(Uint8List bytes) async {
    final replied = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('mic', bytes),
          ),
          (_) => replied.complete(),
        );
    await replied.future;
  }
}

class _Repo implements CallsRepository {
  final sockets = <_Socket>[];
  @override
  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async => [];
  @override
  Future<CallMediaMeta> fetchMediaMeta(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async =>
      CallMediaMeta(id: callId, codec: 'PCM', format: 's16le', stream: '');
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Socket implements WebSocket {
  final sent = <dynamic>[];
  @override
  int get readyState => closeCount == 0 ? WebSocket.open : WebSocket.closed;
  @override
  void add(dynamic data) => sent.add(data);
  final events = StreamController<dynamic>.broadcast();
  void Function()? doneCallback;
  Function? error;
  int closeCount = 0;
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    doneCallback = onDone;
    error = onError;
    return events.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCount++;
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
