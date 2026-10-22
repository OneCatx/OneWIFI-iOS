import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/app/app_dependencies.dart';
import 'package:onewifi_android/core/config/base_url_store.dart';
import 'package:onewifi_android/core/http/gateway_io_client.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/security/gateway_trust_store.dart';
import 'package:onewifi_android/core/state/session_state.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import 'package:onewifi_android/features/auth/domain/session_user.dart';
import 'package:onewifi_android/features/auth/state/session_controller.dart';
import 'package:onewifi_android/features/calls/data/calls_repository.dart';
import 'package:onewifi_android/features/calls/data/native_call_session.dart';
import 'package:onewifi_android/features/calls/domain/call.dart';
import 'package:onewifi_android/features/calls/presentation/calls_screen.dart';
import 'package:onewifi_android/features/calls/presentation/native_call_panel.dart';
import 'package:onewifi_android/features/calls/state/call_session_binding.dart';
import 'package:onewifi_android/features/calls/state/calls_controller.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/state/device_list_controller.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_backend_store.dart';
import 'package:onewifi_android/features/settings/data/product_license_store.dart';

import '../../../support/fakes.dart';
import '../data/native_call_snapshot_test.dart' show snapshotWire, localWire;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());
  CallsController controller() {
    final c = CallsController(
      repository: _NoLegacy(),
      originProvider: () async => h.origin,
      tokenProvider: (_) async => 'token',
      requestRegistry: RequestRegistry(),
      nativeCalls: h.binding,
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'native refresh reaches channel with authoritative generation',
    () async {
      await h.login();
      await h.event(snapshotWire(revision: 5)..['eventStatus'] = 'failed');
      final c = controller();
      await c.refresh();
      final refreshes = h.methods.where((m) => m.method == 'refreshEvents');
      expect(refreshes, hasLength(1));
      expect((refreshes.single.arguments as Map)['generation'], 2);
      expect(c.canDialNative, isFalse);
      expect(h.methods.where((m) => m.method == 'configure'), hasLength(1));
    },
  );

  test(
    'binding replaces caller generation and rejects late refresh after logout',
    () async {
      await h.login();
      await h.binding.execute('refreshEvents', {'generation': 999});
      expect((h.methods.last.arguments as Map)['generation'], 2);
      await h.event(snapshotWire(generation: 3, revision: 6));
      await h.event(snapshotWire(generation: 2, revision: 99));
      await h.binding.execute('refreshEvents', {'generation': 2});
      expect((h.methods.last.arguments as Map)['generation'], 3);
      h.auth.logoutGate = Completer<void>();
      final logout = h.session.signOut();
      await h.flush();
      final before = h.methods.length;
      await expectLater(
        h.binding.execute('refreshEvents', {}),
        throwsA(isA<PlatformException>()),
      );
      expect(h.methods.length, before);
      h.auth.logoutGate!.complete();
      await logout;
    },
  );

  test(
    'rejected refresh does not overwrite remote end notice or claim readiness',
    () async {
      await h.login();
      final c = controller();
      await h.event(
        snapshotWire(revision: 5)
          ..['error'] = 'call_remote_end_unconfirmed'
          ..['eventStatus'] = 'failed',
      );
      h.failCommand = true;
      await c.refresh();
      expect(c.nativeEventDiagnostic, contains('未被接受'));
      expect(c.notice, '本机已结束，远端状态待确认');
      expect(c.noticeError, isFalse);
      expect(c.canDialNative, isFalse);
      await h.event(snapshotWire(revision: 6));
      expect(c.nativeEventDiagnostic, isEmpty);
    },
  );

  for (final code in [
    'call_unauthorized',
    'call_transport',
    'unknown_configuration_failure',
  ]) {
    test(
      'terminal configuration failure $code never promises configuring',
      () async {
        h.configureFailure = code;
        await h.login();
        final c = controller();
        expect(h.binding.snapshot, isNull);
        expect(c.nativeStatusLabel, isNot('正在配置系统通话'));
        expect(c.nativeStatusLabel, contains('重新登录'));
        expect(
          c.nativeStatusLabel,
          isNot(contains('unknown_configuration_failure')),
        );
      },
    );
  }

  testWidgets(
    'permanent listener failure is not presented as automatic retry',
    (tester) async {
      await tester.runAsync(h.login);
      await tester.runAsync(
        () => h.event(snapshotWire(revision: 5)..['eventStatus'] = 'failed'),
      );
      final c = controller();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NativeCallPanel(calls: c)),
        ),
      );
      expect(find.text('通话状态可能已过期，等待重新同步'), findsNothing);
      expect(find.textContaining('监听失败'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'refresh single flight preserves remote end notice and rejects logout',
    () async {
      await h.login();
      final c = controller();
      await h.event(
        snapshotWire(revision: 5)
          ..['error'] = 'call_remote_end_unconfirmed'
          ..['eventStatus'] = 'failed',
      );
      h.commandGate = Completer<void>();
      final first = c.refresh();
      final second = c.refresh();
      expect(identical(first, second), isTrue);
      expect(c.canRefreshNative, isFalse);
      expect(c.notice, '本机已结束，远端状态待确认');
      h.commandGate!.complete();
      await first;
      expect(h.methods.where((m) => m.method == 'refreshEvents'), hasLength(1));
      expect(c.notice, '本机已结束，远端状态待确认');
      expect(c.noticeError, isFalse);
      await h.binding.clear();
      await expectLater(
        h.binding.execute('refreshEvents', {}),
        throwsA(isA<PlatformException>()),
      );
      await c.refresh();
      expect(h.methods.where((m) => m.method == 'refreshEvents'), hasLength(1));
    },
  );

  test(
    'event diagnostics never expose unknown strings or take notice ownership',
    () async {
      await h.login();
      final c = controller();
      await h.event(
        snapshotWire(revision: 5)
          ..['error'] = 'call_remote_end_unconfirmed'
          ..['eventStatus'] = 'failed'
          ..['eventError'] = 'call_trust',
      );
      expect(c.nativeEventDiagnostic, contains('call_trust'));
      expect(c.notice, '本机已结束，远端状态待确认');
      await h.event(
        snapshotWire(revision: 6)
          ..['error'] = 'call_remote_end_unconfirmed'
          ..['eventStatus'] = 'failed'
          ..['eventError'] = 'https://secret.test/token',
      );
      expect(c.nativeEventDiagnostic, isNot(contains('secret')));
      expect(c.notice, '本机已结束，远端状态待确认');
      await h.event(
        snapshotWire(revision: 7)..['error'] = 'call_remote_end_unconfirmed',
      );
      expect(c.nativeEventDiagnostic, isEmpty);
      expect(c.notice, '本机已结束，远端状态待确认');
    },
  );

  test(
    'recovery labels distinguish lifecycle states and keep dialing fail closed',
    () async {
      await h.login();
      final c = controller()..selectDevice('A');
      var revision = 5;
      for (final pair in {
        'connecting': '正在同步',
        'offline': '自动重试',
        'stale': '自动重试',
        'failed': '监听失败',
        'stopped': '监听已停止',
        'unavailable': '尚不支持',
      }.entries) {
        await h.event(
          snapshotWire(revision: revision++)..['eventStatus'] = pair.key,
        );
        expect(c.nativeStatusLabel, contains(pair.value));
        expect(c.canDialNative, isFalse);
      }
      await h.event(
        snapshotWire(revision: revision++)
          ..['foreground'] = false
          ..['eventStatus'] = 'stopped',
      );
      expect(c.nativeStatusLabel, contains('后台'));
      expect(c.canRefreshNative, isFalse);
      await h.event(
        snapshotWire(revision: revision++)
          ..['error'] = 'call_history_limit'
          ..['eventStatus'] = 'failed',
      );
      expect(c.canRefreshNative, isFalse);
      expect(c.nativeStatusLabel, contains('安全上限'));
      await h.event(snapshotWire(revision: revision++));
      expect(c.canDialNative, isTrue);
    },
  );

  testWidgets(
    'panel refresh is actionable and disabled while native command is busy',
    (tester) async {
      await tester.runAsync(h.login);
      await tester.runAsync(
        () => h.event(snapshotWire(revision: 5)..['eventStatus'] = 'failed'),
      );
      final c = controller();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => NativeCallPanel(calls: c),
            ),
          ),
        ),
      );
      h.commandGate = Completer<void>();
      await tester.tap(find.byKey(const Key('native-refresh')));
      await tester.pump();
      expect(h.methods.last.method, 'refreshEvents');
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('native-refresh')))
            .onPressed,
        isNull,
      );
      h.commandGate!.complete();
      await tester.pump();
      expect(c.canDialNative, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('system end pending is neutral until remote acknowledgment', () async {
    await h.login();
    final c = controller();
    await h.event(
      snapshotWire(revision: 5)..['error'] = 'call_remote_end_unconfirmed',
    );
    expect(c.notice, '本机已结束，远端状态待确认');
    expect(c.noticeError, isFalse);
  });
  test(
    'system end acknowledgment clears only the native-owned pending notice',
    () async {
      await h.login();
      final c = controller();
      await h.event(
        snapshotWire(revision: 5)..['error'] = 'call_remote_end_unconfirmed',
      );
      await h.event(snapshotWire(revision: 6));
      expect(c.notice, isEmpty);
      expect(c.noticeError, isFalse);
    },
  );
  for (final validation in [true, false]) {
    test(
      'native acknowledgment preserves newer ${validation ? 'validation' : 'command'} notice after repeated pending state',
      () async {
        await h.login();
        final c = controller();
        await h.event(
          snapshotWire(revision: 5)..['error'] = 'call_remote_end_unconfirmed',
        );
        if (validation) {
          await c.dial();
        } else {
          h.failCommand = true;
          // Permission is a real command path, rejected by the fixture below.
          await c.requestPermissions();
        }
        final notice = c.notice;
        expect(c.noticeError, isTrue);
        await h.event(
          snapshotWire(revision: 6)..['error'] = 'call_remote_end_unconfirmed',
        );
        expect(c.notice, notice);
        await h.event(snapshotWire(revision: 7));
        expect(c.notice, notice);
        expect(c.noticeError, isTrue);
      },
    );
  }
  test(
    'new local call does not retain prior native end pending notice',
    () async {
      await h.login();
      final c = controller();
      await h.event(
        snapshotWire(revision: 5)..['error'] = 'call_remote_end_unconfirmed',
      );
      await h.event(
        snapshotWire(revision: 6, local: localWire()..['uuid'] = 'next-call'),
      );
      expect(c.localCall!.uuid, 'next-call');
      expect(c.notice, isEmpty);
      expect(c.noticeError, isFalse);
    },
  );
  test(
    'app end accepted before pending snapshot clears on acknowledgment without claiming ended',
    () async {
      await h.login();
      final c = controller();
      await c.hangup(c.localCall!.call);
      expect(c.notice, '请求已提交，等待系统通话状态');
      await h.event(
        snapshotWire(revision: 5)..['error'] = 'call_remote_end_unconfirmed',
      );
      expect(c.notice, '本机已结束，远端状态待确认');
      expect(c.noticeError, isFalse);
      await h.event(snapshotWire(revision: 6));
      expect(c.notice, isEmpty);
      expect(c.noticeError, isFalse);
    },
  );
  test(
    'actual native hangup failure remains error despite command acceptance',
    () async {
      await h.login();
      final c = controller();
      h.commandGate = Completer<void>();
      final pending = c.hangup(c.localCall!.call);
      await h.flush();
      await h.event(
        snapshotWire(revision: 5)..['error'] = 'call_hangup_failed',
      );
      h.commandGate!.complete();
      await pending;
      expect(c.notice, contains('call_hangup_failed'));
      expect(c.noticeError, isTrue);
    },
  );

  test(
    'same-call repeated DTMF failure replaces validation after authoritative empty pending and survives acceptance',
    () async {
      await h.login();
      final c = controller();
      Map<String, Object?> local({String error = '', bool pending = false}) =>
          localWire()
            ..['dtmfSupported'] = true
            ..['error'] = error
            ..['actionPending'] = pending;
      const failure = 'call_dtmf_unavailable';
      await h.event(snapshotWire(revision: 5, local: local(error: failure)));
      expect(c.notice, '通话失败（$failure）');
      await c.dial();
      expect(c.notice, '号码无效');
      h.commandGate = Completer<void>();
      final second = c.sendDtmf('5', uuid: 'uuid-1');
      await h.flush();
      expect(h.methods.last.method, 'dtmf');
      // Coordinator clears the old error only when the new action begins.
      // Producer emission is independently tested by the native owner.
      await h.event(snapshotWire(revision: 6, local: local(pending: true)));
      expect(c.notice, '号码无效');
      expect(c.localCall!.actionPending, isTrue);
      await h.event(snapshotWire(revision: 7, local: local(error: failure)));
      expect(c.notice, '通话失败（$failure）');
      expect(c.noticeError, isTrue);
      expect(c.localCall!.uuid, 'uuid-1');
      h.commandGate!.complete();
      await second;
      expect(c.notice, '通话失败（$failure）');
      expect(c.noticeError, isTrue);
    },
  );

  test(
    'same-code global termination supersedes validation after a local DTMF error',
    () async {
      await h.login();
      final c = controller();
      const failure = 'call_transport';
      await h.event(
        snapshotWire(revision: 5, local: localWire()..['error'] = failure),
      );
      expect(c.notice, '通话失败（$failure）');
      await c.dial();
      expect(c.notice, '号码无效');
      // A repeated projection from the same local source is not a new failure.
      await h.event(
        snapshotWire(revision: 6, local: localWire()..['error'] = failure),
      );
      expect(c.notice, '号码无效');
      // Media termination removes the local call and publishes global failure.
      await h.event(snapshotWire(revision: 7)..['error'] = failure);
      expect(c.localCall, isNull);
      expect(c.notice, '通话失败（$failure）');
      expect(c.noticeError, isTrue);
    },
  );

  test(
    'native unauthorized snapshot expires current authentication and clears native resources',
    () async {
      await h.login();
      final epoch = h.session.sessionEpoch;
      expect(h.session.state.status, SessionStatus.signedIn);
      expect(h.binding.snapshot!.local, isNotNull);
      await h.event(snapshotWire(revision: 5)..['status'] = 'unauthorized');
      expect(h.session.state.status, SessionStatus.expired);
      expect(h.session.sessionEpoch, greaterThan(epoch));
      expect(await h.tokens.read(h.origin), isNull);
      expect(h.methods.where((m) => m.method == 'clear'), hasLength(1));
      expect(h.binding.snapshot, isNull);
      await h.trust.setFingerprint(h.origin, 'a' * 64);
      await h.event(snapshotWire(revision: 6, local: localWire()));
      expect(h.methods.where((m) => m.method == 'configure'), hasLength(1));
      expect(h.binding.snapshot, isNull);
      expect(h.session.state.status, SessionStatus.expired);
    },
  );

  test(
    'a new authentication transition reopens calls using latest trust after logout',
    () async {
      await h.login();
      await h.session.signOut();
      await h.trust.setFingerprint(h.origin, 'a' * 64);
      await h.flush();
      expect(h.methods.where((m) => m.method == 'configure'), hasLength(1));
      await h.tokens.write(h.origin, 'new-session-token');
      await h.session.signIn('user', 'password');
      await h.flush();
      final configurations = h.methods
          .where((m) => m.method == 'configure')
          .toList();
      expect(configurations, hasLength(2));
      expect(
        (configurations.last.arguments as Map)['token'],
        'new-session-token',
      );
      expect(
        (configurations.last.arguments as Map)['certificateFingerprint'],
        'a' * 64,
      );
      await h.trust.setFingerprint(h.origin, 'b' * 64);
      await h.flush();
      final latest = h.methods.lastWhere((m) => m.method == 'configure');
      expect((latest.arguments as Map)['certificateFingerprint'], 'b' * 64);
    },
  );
  for (final blockOrigin in [true, false]) {
    test(
      'late trust write cannot revive logout while ${blockOrigin ? 'origin storage' : 'backend logout'} is blocked',
      () async {
        await h.login();
        h.trustStore.writeGate = Completer<void>();
        final writing = h.trust.setFingerprint(h.origin, 'a' * 64);
        await h.flush();
        if (blockOrigin) {
          h.origins.gate = Completer<Uri>();
        } else {
          h.auth.logoutGate = Completer<void>();
        }
        final logout = h.session.signOut();
        await h.flush();
        expect(h.binding.snapshot, isNull);
        final reads = h.tokenReads;
        h.trustStore.writeGate!.complete();
        await writing;
        await h.flush();
        final configurations = h.methods
            .where((m) => m.method == 'configure')
            .length;
        final extraReads = h.tokenReads - reads;
        final restored = h.binding.snapshot;
        if (blockOrigin) {
          h.origins.gate!.complete(h.origin);
        } else {
          h.auth.logoutGate!.complete();
        }
        await logout;
        expect(configurations, 1);
        expect(extraReads, 0);
        expect(restored, isNull);
      },
    );
  }
  test(
    'late old-origin pin cannot revive changeOrigin while origin storage is blocked',
    () async {
      await h.login();
      h.trustStore.writeGate = Completer<void>();
      final writing = h.trust.setFingerprint(h.origin, 'a' * 64);
      await h.flush();
      h.origins.gate = Completer<Uri>();
      final nextOrigin = Uri.parse('https://next.example.test');
      final changing = h.session.changeOrigin(nextOrigin);
      await h.flush();
      final reads = h.tokenReads;
      h.trustStore.writeGate!.complete();
      await writing;
      await h.flush();
      final configurations = h.methods
          .where((m) => m.method == 'configure')
          .length;
      final extraReads = h.tokenReads - reads;
      final restored = h.binding.snapshot;
      h.origins.gate!.complete(h.origin);
      await changing;
      expect(configurations, 1);
      expect(extraReads, 0);
      expect(restored, isNull);
      expect(h.binding.snapshot, isNull);
      expect(h.session.origin, nextOrigin);
      expect(h.session.state.status, SessionStatus.signedOut);
      expect(await h.tokens.read(h.origin), isNull);
    },
  );

  test(
    'queued trust reconfiguration cannot overtake later authentication teardown',
    () async {
      await h.login();
      h.clearGate = Completer<void>();
      await h.trust.setFingerprint(h.origin, 'a' * 64);
      h.origins.gate = Completer<Uri>();
      final logout = h.session.signOut();
      await h.flush();
      final reads = h.tokenReads;
      h.clearGate!.complete();
      await h.flush();
      final configurations = h.methods
          .where((m) => m.method == 'configure')
          .length;
      final extraReads = h.tokenReads - reads;
      h.origins.gate!.complete(h.origin);
      await logout;
      expect(configurations, 1);
      expect(extraReads, 0);
      expect(h.binding.snapshot, isNull);
    },
  );

  test(
    'permanent native view completion directs user to login instead of promising retry',
    () async {
      await h.login();
      final c = controller();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'com.oneims.onewifi/call_session/events',
            null,
            (_) {},
          );
      await h.flush();
      expect(c.nativeStatusLabel, contains('重新登录'));
      expect(h.binding.snapshot, isNull);
    },
  );
  testWidgets(
    'DTMF menu keeps original UUID when a new call replaces the owner',
    (tester) async {
      await tester.runAsync(h.login);
      await tester.runAsync(
        () => h.event(
          snapshotWire(
            revision: 5,
            local: localWire()..['dtmfSupported'] = true,
          ),
        ),
      );
      final c = controller();
      await c.sendDtmf('5', uuid: c.localCall!.uuid);
      expect(h.methods.last.method, 'dtmf');
      expect((h.methods.last.arguments as Map)['digit'], '5');
      final oldIntent = c.localCall!.uuid;
      await tester.runAsync(
        () => h.event(
          snapshotWire(
            revision: 6,
            local: localWire()
              ..['uuid'] = 'new-uuid'
              ..['dtmfSupported'] = true,
          ),
        ),
      );
      final before = h.methods.length;
      await c.sendDtmf('5', uuid: oldIntent);
      expect(h.methods.length, before);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'controller local audio commands carry captured UUID and reject old targets',
    () async {
      await h.login();
      await h.event(
        snapshotWire(revision: 5, local: localWire()..['dtmfSupported'] = true),
      );
      final c = controller();
      final old = c.localCall!.uuid;
      await c.setMuted(true, uuid: old);
      await c.setRoute('speaker', uuid: old);
      await c.sendDtmf('5', uuid: old);
      for (final m in h.methods.where(
        (m) => ['mute', 'route', 'dtmf'].contains(m.method),
      )) {
        expect((m.arguments as Map)['uuid'], old);
      }
      await h.event(
        snapshotWire(
          revision: 6,
          local: localWire()
            ..['uuid'] = 'new-uuid'
            ..['dtmfSupported'] = true,
        ),
      );
      final before = h.methods.length;
      await c.setMuted(false, uuid: old);
      await c.setRoute('receiver', uuid: old);
      await c.sendDtmf('9', uuid: old);
      expect(h.methods.length, before);
    },
  );
  testWidgets(
    'old pending-dial UI intent cannot cancel a new empty-id call in same generation',
    (tester) async {
      await tester.runAsync(h.login);
      Map<String, Object?> pending(String uuid) => localWire()
        ..['uuid'] = uuid
        ..['id'] = ''
        ..['phase'] = 'dialing'
        ..['owned'] = false
        ..['actionPending'] = true;
      await tester.runAsync(
        () => h.event(snapshotWire(revision: 5, local: pending('old-uuid'))),
      );
      final c = controller();
      final old = c.localCall!.call;
      await tester.runAsync(
        () => h.event(snapshotWire(revision: 6, local: pending('new-uuid'))),
      );
      final before = h.methods.length;
      await c.hangup(old, uuid: 'old-uuid');
      expect(h.methods.length, before);
      await c.hangup(c.localCall!.call, uuid: 'new-uuid');
      final end = h.methods.singleWhere((m) => m.method == 'hangup');
      expect((end.arguments as Map)['uuid'], 'new-uuid');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'binding rejects missing or stale UUID on every local command',
    () async {
      await h.login();
      for (final method in ['answer', 'hangup', 'mute', 'route', 'dtmf']) {
        final count = h.methods.length;
        await expectLater(
          h.binding.execute(method, {
            'uuid': 'old-uuid',
            'deviceId': 'A',
            'id': 'c1',
          }),
          throwsA(isA<PlatformException>()),
        );
        await expectLater(
          h.binding.execute(method, {}),
          throwsA(isA<PlatformException>()),
        );
        expect(h.methods.length, count);
      }
    },
  );
  test(
    'trust writes and clears for a different origin preserve current local owner',
    () async {
      await h.login();
      final local = h.binding.snapshot!.local;
      final before = h.methods.length;
      final other = Uri.parse('https://mihomo.example.test:9090');
      await h.trust.setFingerprint(other, 'b' * 64);
      await h.flush();
      await h.trust.setFingerprint(other, null);
      await h.flush();
      expect(h.methods.length, before);
      expect(identical(h.binding.snapshot!.local, local), isTrue);
    },
  );
  test(
    'saving the same effective current-origin pin does not clear the call',
    () async {
      h.trustStore.pins[h.origin] = 'a' * 64;
      await h.login();
      final before = h.methods.length;
      await h.trust.setFingerprint(h.origin, 'AA:' * 31 + 'AA');
      await h.flush();
      expect(h.methods.length, before);
      expect(h.binding.snapshot!.local!.uuid, 'uuid-1');
    },
  );
  test(
    'current-origin pin replacement clears immediately before reconfiguration',
    () async {
      await h.login();
      h.clearGate = Completer<void>();
      await h.trust.setFingerprint(h.origin, 'a' * 64);
      expect(h.binding.snapshot, isNull);
      expect(h.methods.where((m) => m.method == 'clear'), hasLength(1));
      expect(h.methods.where((m) => m.method == 'configure'), hasLength(1));
      h.clearGate!.complete();
      await h.flush();
      final configured = h.methods
          .where((m) => m.method == 'configure')
          .toList();
      expect(configured, hasLength(2));
      expect(
        (configured.last.arguments as Map)['certificateFingerprint'],
        'a' * 64,
      );
      expect(h.binding.snapshot!.generation, 3);
    },
  );
  test(
    'failed current-origin pin write preserves owner and configuration',
    () async {
      await h.login();
      h.trustStore.fail = true;
      final before = h.methods.length;
      await expectLater(
        h.trust.setFingerprint(h.origin, 'b' * 64),
        throwsStateError,
      );
      await h.flush();
      expect(h.methods.length, before);
      expect(h.binding.snapshot!.local!.uuid, 'uuid-1');
    },
  );
  test(
    'queued asynchronous pin replacements configure only latest settled trust',
    () async {
      await h.login();
      h.clearGate = Completer<void>();
      h.trustStore.writeGate = Completer<void>();
      final first = h.trust.setFingerprint(h.origin, 'a' * 64);
      final last = h.trust.setFingerprint(h.origin, 'b' * 64);
      await h.flush();
      expect(h.binding.snapshot, isNotNull);
      h.trustStore.writeGate!.complete();
      await Future.wait([first, last]);
      expect(h.binding.snapshot, isNull);
      h.clearGate!.complete();
      await h.flush();
      final configured = h.methods
          .where((m) => m.method == 'configure')
          .toList();
      expect(configured, hasLength(2));
      expect(
        (configured.last.arguments as Map)['certificateFingerprint'],
        'b' * 64,
      );
    },
  );

  testWidgets('app can cancel a pending native dial with no backend id', (
    tester,
  ) async {
    await tester.runAsync(h.login);
    await tester.runAsync(
      () => h.event(
        snapshotWire(
          revision: 5,
          local: localWire()
            ..['id'] = ''
            ..['phase'] = 'dialing'
            ..['owned'] = false
            ..['actionPending'] = true,
        ),
      ),
    );
    final c = controller();
    await c.hangup(c.localCall!.call, uuid: c.localCall!.uuid);
    expect(h.methods.last.method, 'hangup');
    expect((h.methods.last.arguments as Map)['id'], '');
    expect((h.methods.last.arguments as Map)['deviceId'], 'A');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'pending native answer can cancel once without duplicating end',
    () async {
      await h.login();
      await h.event(
        snapshotWire(
          revision: 5,
          local: localWire()
            ..['phase'] = 'answering'
            ..['actionPending'] = true,
        ),
      );
      final c = controller();
      h.commandGate = Completer<void>();
      final ending = c.hangup(c.localCall!.call);
      await h.flush();
      await c.hangup(c.localCall!.call);
      final ends = h.methods.where((m) => m.method == 'hangup').length;
      h.commandGate!.complete();
      await ending;
      expect(ends, 1);
    },
  );
  testWidgets(
    'real capability sends DTMF without editing the dialed number',
    (tester) async {
      await tester.runAsync(h.login);
      await tester.runAsync(
        () => h.event(
          snapshotWire(
            revision: 5,
            local: localWire()..['dtmfSupported'] = true,
          ),
        ),
      );
      final c = controller()..setDialNumber('123');
      await c.sendDtmf('5', uuid: c.localCall!.uuid);
      expect(h.methods.last.method, 'dtmf');
      expect((h.methods.last.arguments as Map)['digit'], '5');
      expect(c.dialNumber, '123');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'mute route and DTMF stay disabled until ownership and real audio readiness',
    () async {
      await h.login();
      final c = controller();
      for (final local in [
        localWire()..['owned'] = false,
        localWire()..['audioReady'] = false,
        localWire()..['actionPending'] = true,
      ]) {
        await h.event(snapshotWire(revision: ++h.eventRevision, local: local));
        expect(c.canControlNativeAudio, isFalse);
        expect(c.canSendDtmf, isFalse);
        final before = h.methods.length;
        await c.setMuted(true);
        await c.setRoute('speaker');
        await c.sendDtmf('5');
        expect(h.methods.length, before);
      }
    },
  );
  test(
    'native pending end arriving before request acceptance remains neutral and unconfirmed',
    () async {
      await h.login();
      final c = controller();
      h.commandGate = Completer<void>();
      final pending = c.hangup(c.localCall!.call);
      await h.flush();
      await h.event(
        snapshotWire(revision: 5)..['error'] = 'call_remote_end_unconfirmed',
      );
      h.commandGate!.complete();
      await pending;
      expect(c.noticeError, isFalse);
      expect(c.notice, '本机已结束，远端状态待确认');
    },
  );

  testWidgets(
    'native panel keeps diagnostics but does not render a second call UI',
    (tester) async {
      await tester.runAsync(h.login);
      final c = controller()..selectDevice('B');
      final devices = DeviceListController(
        repository: _Devices(),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(devices.dispose);
      Widget page() => MaterialApp(
        home: Scaffold(
          body: CallsScreen(calls: c, devices: devices),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pump();
      expect(find.byKey(const Key('native-call-panel')), findsOneWidget);
      expect(c.localCall?.label, 'Device A');
      expect(find.byKey(const Key('call-stage-number')), findsNothing);
      expect(find.text('接听'), findsNothing);
      expect(find.text('挂断'), findsNothing);
      expect(find.byKey(const Key('native-dtmf')), findsNothing);
      expect(find.byKey(const Key('global-current-call')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      c.selectDevice('B');
      await tester.pumpWidget(page());
      await tester.pump();
      expect(find.text('接听'), findsNothing);
      expect(find.text('挂断'), findsNothing);
      expect(h.methods.where((m) => m.method == 'clear'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('permission readiness is actionable and stale snapshot warns', (
    tester,
  ) async {
    await tester.runAsync(h.login);
    await tester.runAsync(
      () => h.event(
        snapshotWire(revision: 5)..['permissions'] = {'microphone': false},
      ),
    );
    final c = controller();
    final devices = DeviceListController(
      repository: _Devices(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(devices.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallsScreen(calls: c, devices: devices),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('通话设置'));
    await tester.pumpAndSettle();
    expect(find.text('通话权限'), findsOneWidget);
    await tester.tap(find.text('通话权限'));
    await tester.pump();
    expect(h.methods.any((m) => m.method == 'requestPermissions'), isTrue);
    await tester.ensureVisible(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => h.event(snapshotWire(revision: 6)..['eventStatus'] = 'stale'),
    );
    await tester.pump();
    expect(find.text('通话状态可能已过期，正在自动重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'native controller preserves local target through device switch and never touches legacy media',
    () async {
      await h.login();
      final c = controller();
      c.selectDevice('B');
      await c.refresh();
      await c.ensureMedia(
        const VoiceCall(
          id: 'c1',
          deviceId: 'A',
          number: '10086',
          direction: CallDirection.incoming,
          state: CallLifecycle.active,
        ),
      );
      await c.hangup(
        const VoiceCall(
          id: 'c1',
          deviceId: 'A',
          number: '10086',
          direction: CallDirection.incoming,
          state: CallLifecycle.active,
        ),
      );
      expect((h.methods.last.arguments as Map)['deviceId'], 'A');
      expect((h.methods.last.arguments as Map)['id'], 'c1');
      expect(c.notice, isNot('已挂断'));
    },
  );
  test('native action rejection is displayed as failure not success', () async {
    await h.login();
    final c = controller()..selectDevice('A');
    h.failCommand = true;
    await c.hangup(
      const VoiceCall(
        id: 'c1',
        deviceId: 'A',
        number: '10086',
        direction: CallDirection.incoming,
        state: CallLifecycle.active,
      ),
    );
    expect(c.noticeError, isTrue);
    expect(c.notice, contains('call_state_conflict'));
  });
  test(
    'real app dependencies configure iOS native without creating CallsController',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final deps = AppDependencies(
        productLicenseStore: MemoryProductLicenseStore(),
        mihomoBackendStore: MemoryMihomoBackendStore(),
        baseUrlStore: MemoryBaseUrlStore(h.origin),
        tokenStore: MemoryTokenStore({h.origin: 'test-only-token'}),
        httpClient: FakeClient(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'data': {
                    'authenticated': true,
                    'user': {'username': 'user'},
                    'session_token': 'test-only-token',
                    'expires_at': '2030-01-01T00:00:00Z',
                  },
                }),
              ),
            ),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(deps.dispose);
      await deps.sessionController.bootstrap();
      await h.flush();
      expect(h.methods.where((m) => m.method == 'configure'), hasLength(1));
    },
  );
  test(
    'cold login configures current credentials before any calls page exists',
    () async {
      await h.login();
      expect(h.methods.where((m) => m.method == 'configure'), hasLength(1));
      final args =
          h.methods.firstWhere((m) => m.method == 'configure').arguments as Map;
      expect(args['origin'], h.origin.toString());
      expect(args['token'], 'test-only-token');
      expect(args['certificateFingerprint'], null);
      expect(h.binding.snapshot!.generation, 2);
    },
  );
  test(
    'stream error cannot lower generation or revision high water marks',
    () async {
      await h.login();
      await h.event(snapshotWire(generation: 3, revision: 9));
      await h.error();
      expect(h.binding.snapshot, isNull);
      await h.event(snapshotWire(generation: 2, revision: 99));
      await h.event(snapshotWire(generation: 3, revision: 8));
      expect(h.binding.snapshot, isNull);
      await h.event(snapshotWire(generation: 3, revision: 10));
      expect(h.binding.snapshot!.revision, 10);
    },
  );
  test(
    'logout clears native before a blocked backend logout completes',
    () async {
      await h.login();
      h.auth.logoutGate = Completer<void>();
      final pending = h.session.signOut();
      await h.flush();
      expect(h.methods.any((m) => m.method == 'clear'), isTrue);
      expect(h.binding.snapshot, isNull);
      h.auth.logoutGate!.complete();
      await pending;
    },
  );
  test(
    'trust change invalidates old view and configures new pin exactly once',
    () async {
      await h.login();
      await h.trust.setFingerprint(h.origin, 'a' * 64);
      await h.flush();
      final configurations = h.methods
          .where((m) => m.method == 'configure')
          .toList();
      expect(configurations, hasLength(2));
      expect(
        (configurations.last.arguments as Map)['certificateFingerprint'],
        'a' * 64,
      );
    },
  );
  test(
    'native rejected command remains failure and carries authoritative generation',
    () async {
      await h.login();
      h.failCommand = true;
      await expectLater(
        h.binding.execute('hangup', {
          'deviceId': 'A',
          'id': 'c1',
          'uuid': 'uuid-1',
        }),
        throwsA(isA<PlatformException>()),
      );
      expect((h.methods.last.arguments as Map)['generation'], 2);
    },
  );
  test(
    'logout invalidates native even when origin storage is suspended',
    () async {
      await h.login();
      h.origins.gate = Completer<Uri>();
      final pending = h.session.signOut();
      await h.flush();
      final cleared = h.methods.any((m) => m.method == 'clear');
      h.origins.gate!.complete(h.origin);
      await pending;
      expect(cleared, isTrue);
    },
  );
  test('late credentials after logout cannot configure native', () async {
    h.tokenGate = Completer<String?>();
    await h.session.signIn('user', 'password');
    await h.flush();
    final clearing = h.session.signOut();
    await h.flush();
    h.tokenGate!.complete('old-token');
    await clearing;
    await h.flush();
    expect(h.methods.where((m) => m.method == 'configure'), isEmpty);
  });
}

class _Harness {
  _Harness() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IOSNativeCallSession.channel, (
      call,
    ) async {
      methods.add(call);
      if (call.method == 'configure' && configureFailure != null) {
        throw PlatformException(code: configureFailure!);
      }
      if (call.method == 'configure') nativeGeneration++;
      if (call.method == 'snapshot') {
        return snapshotWire(generation: nativeGeneration, local: localWire());
      }
      if (call.method == 'clear') await clearGate?.future;
      if (failCommand &&
          (call.method == 'hangup' ||
              call.method == 'requestPermissions' ||
              call.method == 'refreshEvents')) {
        throw PlatformException(code: 'call_state_conflict');
      }
      if (call.method == 'hangup' ||
          call.method == 'dtmf' ||
          call.method == 'refreshEvents') {
        await commandGate?.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.oneims.onewifi/call_session/events'),
      (_) async => null,
    );
    session = SessionController(
      repository: auth,
      tokenStore: tokens,
      baseUrlStore: origins,
      requestRegistry: RequestRegistry(),
    );
    binding = CallSessionBinding(
      native: const IOSNativeCallSession(),
      tokenProvider: (origin) {
        tokenReads++;
        return tokenGate?.future ?? tokens.read(origin);
      },
      fingerprintProvider: trust.readFingerprint,
      trustChanges: trust,
    )..attach(session);
    session.registerResource(binding);
  }
  final origin = Uri.parse('https://gateway.example.test');
  late final origins = _OriginStore(origin);
  late final tokens = MemoryTokenStore({origin: 'test-only-token'});
  int tokenReads = 0;
  final auth = _Auth();
  final trustStore = _TrustStore();
  late final trust = GatewayConnectionFactory(trustStore: trustStore);
  final methods = <MethodCall>[];
  late final SessionController session;
  late final CallSessionBinding binding;
  int nativeGeneration = 1;
  Completer<void>? clearGate;
  bool failCommand = false;
  String? configureFailure;
  Completer<String?>? tokenGate;
  Completer<void>? commandGate;
  int eventRevision = 4;
  Future<void> login() async {
    await session.bootstrap();
    await flush();
  }

  Future<void> flush() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> event(Object wire) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'com.oneims.onewifi/call_session/events',
          const StandardMethodCodec().encodeSuccessEnvelope(wire),
          (_) {},
        );
    await flush();
  }

  Future<void> error() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'com.oneims.onewifi/call_session/events',
          const StandardMethodCodec().encodeErrorEnvelope(code: 'view_failed'),
          (_) {},
        );
    await flush();
  }

  void dispose() {
    binding.dispose();
    session.dispose();
    trust.close();
  }
}

class _Auth implements AuthRepository {
  Completer<void>? logoutGate;
  @override
  Future<SessionUser> login(String username, String password) async =>
      SessionUser(username);
  @override
  Future<SessionUser> restore({RequestCancellation? cancellation}) async =>
      SessionUser('user');
  @override
  Future<void> logout() async {
    await logoutGate?.future;
  }
}

class _OriginStore implements BaseUrlStore {
  _OriginStore(this.origin);
  Uri origin;
  Completer<Uri>? gate;
  @override
  Future<Uri> read() => gate?.future ?? Future.value(origin);
  @override
  Future<void> write(Uri origin) async {
    this.origin = origin;
  }
}

class _TrustStore implements GatewayTrustStore {
  final pins = <Uri, String>{};
  bool fail = false;
  Completer<void>? writeGate;
  @override
  Future<String?> readFingerprint(Uri origin) async => pins[origin];
  @override
  Future<void> writeFingerprint(Uri origin, String fingerprint) async {
    await writeGate?.future;
    if (fail) throw StateError('synthetic trust failure');
    pins[origin] = fingerprint;
  }

  @override
  Future<void> clearFingerprint(Uri origin) async {
    if (fail) throw StateError('synthetic trust failure');
    pins.remove(origin);
  }
}

class _NoLegacy implements CallsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Legacy must not be used');
}

class _Devices implements DeviceRepository {
  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) async =>
      DeviceFleet(deviceLimit: 0, devices: []);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected devices operation');
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
