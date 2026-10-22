import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import 'package:onewifi_android/features/auth/domain/session_user.dart';
import 'package:onewifi_android/features/auth/state/session_controller.dart';
import 'package:onewifi_android/features/calls/data/call_push_registrar.dart';
import 'package:onewifi_android/features/calls/data/ios_call_push.dart';
import 'package:onewifi_android/features/calls/state/call_push_binding.dart';

import '../../../support/fakes.dart';

/// PushKit 令牌是 32 字节，也就是 64 个十六进制字符。
String _pairs(String pair) => List<String>.filled(32, pair).join();

final _tokenA = CallPushToken(
  deviceToken: _pairs('aa'),
  environment: 'production',
);
final _tokenB = CallPushToken(deviceToken: _pairs('bb'), environment: 'sandbox');

void main() {
  test('登录后登记当前令牌，令牌不变化就不重复登记', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.session.signIn('user', 'password');
    await h.flush();
    expect(h.tokens.starts, 1);
    expect(h.registrar.registered, <CallPushToken>[_tokenA]);
    h.tokens.emit(_tokenA);
    await h.flush();
    expect(h.registrar.registered, <CallPushToken>[_tokenA]);
    h.tokens.emit(_tokenB);
    await h.flush();
    expect(h.registrar.registered, <CallPushToken>[_tokenA, _tokenB]);
  });

  test('系统还没发出令牌时不登记，令牌到达后补上', () async {
    final h = _Harness(hasToken: false);
    addTearDown(h.dispose);
    await h.session.signIn('user', 'password');
    await h.flush();
    expect(h.registrar.registered, isEmpty);
    h.tokens.emit(_tokenA);
    await h.flush();
    expect(h.registrar.registered, <CallPushToken>[_tokenA]);
  });

  test('登出后到达的令牌不会带着旧会话登记', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.session.signIn('user', 'password');
    await h.flush();
    await h.session.signOut();
    await h.flush();
    h.tokens.emit(_tokenB);
    await h.flush();
    expect(h.registrar.registered, <CallPushToken>[_tokenA]);
  });

  test('再次登录会重新登记，因为上一次登记随会话一起失效', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.session.signIn('user', 'password');
    await h.flush();
    await h.session.signOut();
    await h.flush();
    await h.session.signIn('user', 'password');
    await h.flush();
    expect(h.registrar.registered, <CallPushToken>[_tokenA, _tokenA]);
  });

  test('销毁后的令牌事件不再产生登记', () async {
    final h = _Harness();
    await h.session.signIn('user', 'password');
    await h.flush();
    h.binding.dispose();
    h.tokens.emit(_tokenB);
    await h.flush();
    expect(h.registrar.registered, <CallPushToken>[_tokenA]);
    h.dispose();
  });

  test('登记失败自己退避重试，成功后不再重试', () {
    fakeAsync((async) {
      final h = _Harness(failures: 2);
      h.session.signIn('user', 'password');
      async.flushMicrotasks();
      expect(h.registrar.attempts, 1);
      // 2s、4s 后各重试一次：退避是自我推进的，不依赖用户操作。
      async.elapse(const Duration(seconds: 2));
      expect(h.registrar.attempts, 2);
      async.elapse(const Duration(seconds: 4));
      expect(h.registrar.attempts, 3);
      expect(h.registrar.registered, <CallPushToken>[_tokenA]);
      async.elapse(const Duration(minutes: 10));
      expect(h.registrar.attempts, 3);
      h.dispose();
      async.flushMicrotasks();
    });
  });

  test('登出会停掉重试，不再对已失效的会话登记', () {
    fakeAsync((async) {
      final h = _Harness(failures: 10);
      h.session.signIn('user', 'password');
      async.flushMicrotasks();
      expect(h.registrar.attempts, 1);
      h.session.signOut();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 30));
      expect(h.registrar.attempts, 1);
      h.dispose();
      async.flushMicrotasks();
    });
  });
}

final class _Harness {
  _Harness({bool hasToken = true, int failures = 0})
    : tokens = _FakePushTokens(hasToken ? _tokenA : null),
      registrar = _Recorder(failures: failures) {
    session = SessionController(
      repository: _Auth(),
      tokenStore: MemoryTokenStore(<Uri, String>{origin: 'test-only-token'}),
      baseUrlStore: MemoryBaseUrlStore(origin),
      requestRegistry: RequestRegistry(),
    );
    binding = CallPushBinding(tokens: tokens, registrar: registrar)
      ..attach(session);
  }

  static final Uri origin = Uri.parse('https://gateway.example.test');

  final _FakePushTokens tokens;
  final _Recorder registrar;
  late final SessionController session;
  late final CallPushBinding binding;

  Future<void> flush() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void dispose() {
    binding.dispose();
    tokens.close();
    session.dispose();
  }
}

final class _FakePushTokens implements CallPushTokens {
  _FakePushTokens(this.token);

  CallPushToken? token;
  final StreamController<CallPushToken> _changes =
      StreamController<CallPushToken>.broadcast();
  int starts = 0;

  @override
  Future<CallPushToken?> start() async {
    starts += 1;
    return token;
  }

  @override
  Stream<CallPushToken> get changes => _changes.stream;

  void emit(CallPushToken next) {
    token = next;
    _changes.add(next);
  }

  void close() => unawaited(_changes.close());
}

final class _Recorder implements CallPushRegistrar {
  _Recorder({this.failures = 0});

  int failures;
  int attempts = 0;
  final List<CallPushToken> registered = <CallPushToken>[];

  @override
  Future<void> register(CallPushToken token) async {
    attempts += 1;
    if (failures > 0) {
      failures -= 1;
      throw StateError('synthetic call push registration failure');
    }
    registered.add(token);
  }
}

final class _Auth implements AuthRepository {
  @override
  Future<SessionUser> login(String username, String password) async =>
      SessionUser(username);

  @override
  Future<SessionUser> restore({RequestCancellation? cancellation}) async =>
      SessionUser('user');

  @override
  Future<void> logout() async {}
}