import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/config/base_url_policy.dart';
import 'package:onewifi_android/core/config/base_url_store.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/security/secure_token_store.dart';
import 'package:onewifi_android/core/state/session_state.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import 'package:onewifi_android/features/auth/domain/session_user.dart';
import 'package:onewifi_android/features/auth/state/session_controller.dart';

final Uri _origin = Uri.parse('https://old.example.test');
final Uri _nextOrigin = Uri.parse('https://new.example.test');

void main() {
  group('SessionController after dispose()', () {
    test('bootstrap completes silently', () async {
      final h = _Harness(tokens: <Uri, String>{_origin: _runtimeSecret(41, 7)});
      h.controller.dispose();
      final before = h.calls;

      await expectLater(h.controller.bootstrap(), completes);

      expect(h.notifications, 0);
      expect(h.calls, before);
      expect(h.controller.state.status, SessionStatus.booting);
      expect(h.controller.origin, BaseUrlPolicy.defaultOrigin);
      expect(h.controller.sessionEpoch, 0);
    });

    test('signIn completes silently', () async {
      final h = _Harness();
      final read = h.registry.register('overview.load');
      h.controller.dispose();
      final before = h.calls;

      await expectLater(
        h.controller.signIn('admin', _runtimeSecret(45, 17)),
        completes,
      );

      expect(h.notifications, 0);
      expect(h.calls, before);
      expect(read.cancellation.isCancelled, isFalse);
      expect(h.controller.state.status, SessionStatus.booting);
      expect(h.controller.sessionEpoch, 0);
    });

    test('signOut completes silently', () async {
      final token = _runtimeSecret(59, 9);
      final h = _Harness(tokens: <Uri, String>{_origin: token});
      final read = h.registry.register('overview.load');
      h.controller.dispose();
      final before = h.calls;

      await expectLater(h.controller.signOut(), completes);

      expect(h.notifications, 0);
      expect(h.calls, before);
      expect(read.cancellation.isCancelled, isFalse);
      expect(h.controller.state.status, SessionStatus.booting);
      expect(h.controller.sessionEpoch, 0);
      expect(h.tokenStore.tokens[_origin], token);
    });

    test('changeOrigin completes silently', () async {
      final token = _runtimeSecret(67, 17);
      final h = _Harness(tokens: <Uri, String>{_origin: token});
      final read = h.registry.register('overview.load');
      h.controller.dispose();
      final before = h.calls;

      await expectLater(h.controller.changeOrigin(_nextOrigin), completes);

      expect(h.notifications, 0);
      expect(h.calls, before);
      expect(read.cancellation.isCancelled, isFalse);
      expect(h.controller.state.status, SessionStatus.booting);
      expect(h.controller.origin, BaseUrlPolicy.defaultOrigin);
      expect(h.controller.sessionEpoch, 0);
      expect(h.baseUrlStore.origin, _origin);
      expect(h.tokenStore.tokens[_origin], token);
    });

    test('expireIfCurrent with the current epoch completes silently', () async {
      final token = _runtimeSecret(77, 5);
      final h = _Harness(tokens: <Uri, String>{_origin: token});
      final read = h.registry.register('overview.load');
      h.controller.dispose();
      final before = h.calls;

      await expectLater(
        h.controller.expireIfCurrent(h.controller.sessionEpoch),
        completes,
      );

      expect(h.notifications, 0);
      expect(h.calls, before);
      expect(read.cancellation.isCancelled, isFalse);
      expect(h.controller.state.status, SessionStatus.booting);
      expect(h.controller.sessionEpoch, 0);
      expect(h.tokenStore.tokens[_origin], token);
    });
  });

  group('SessionController disposed while a request is in flight', () {
    test('signIn: late success completes silently', () async {
      final h = _Harness();
      final login = Completer<SessionUser>();
      h.repository.loginGate = login;
      final pending = h.controller.signIn('admin', _runtimeSecret(45, 17));
      await pumpEventQueue();
      expect(h.repository.loginCount, 1);
      expect(h.controller.state.status, SessionStatus.signingIn);
      h.controller.dispose();
      final notified = h.notifications;
      final before = h.calls;

      login.complete(SessionUser('admin'));
      await expectLater(pending, completes);

      expect(h.notifications, notified);
      expect(h.calls, before);
      expect(h.controller.state.status, SessionStatus.signingIn);
    });

    test('signIn: late failure completes silently', () async {
      final h = _Harness();
      final login = Completer<SessionUser>();
      h.repository.loginGate = login;
      final pending = h.controller.signIn('admin', _runtimeSecret(43, 21));
      await pumpEventQueue();
      expect(h.repository.loginCount, 1);
      h.controller.dispose();
      final notified = h.notifications;
      final before = h.calls;

      login.completeError(
        const ApiFailure(
          ApiFailureKind.network,
          requestId: 'local-late-login-failure',
        ),
      );
      await expectLater(pending, completes);

      expect(h.notifications, notified);
      expect(h.calls, before);
      expect(h.controller.state.status, SessionStatus.signingIn);
    });

    test('bootstrap: late restore success completes silently', () async {
      final h = _Harness(tokens: <Uri, String>{_origin: _runtimeSecret(49, 9)});
      final restore = Completer<SessionUser>();
      h.repository.restoreGate = restore;
      final pending = h.controller.bootstrap();
      await pumpEventQueue();
      expect(h.repository.restoreCount, 1);
      h.controller.dispose();
      final before = h.calls;

      restore.complete(SessionUser('admin'));
      await expectLater(pending, completes);

      expect(h.notifications, 0);
      expect(h.calls, before);
      expect(h.controller.state.status, SessionStatus.booting);
    });

    test('bootstrap: late restore failure completes silently', () async {
      final h = _Harness(
        tokens: <Uri, String>{_origin: _runtimeSecret(55, 11)},
      );
      final restore = Completer<SessionUser>();
      h.repository.restoreGate = restore;
      final pending = h.controller.bootstrap();
      await pumpEventQueue();
      expect(h.repository.restoreCount, 1);
      h.controller.dispose();
      final before = h.calls;

      restore.completeError(
        const ApiFailure(
          ApiFailureKind.network,
          requestId: 'local-late-restore-failure',
        ),
      );
      await expectLater(pending, completes);

      expect(h.notifications, 0);
      expect(h.calls, before);
      expect(h.controller.state.status, SessionStatus.booting);
    });

    test('bootstrap: late token read completes silently', () async {
      final token = _runtimeSecret(95, 1);
      final h = _Harness(tokens: <Uri, String>{_origin: token});
      final tokenRead = Completer<String?>();
      h.tokenStore.readGate = tokenRead;
      final pending = h.controller.bootstrap();
      await pumpEventQueue();
      expect(h.tokenStore.reads, 1);
      expect(h.repository.restoreCount, 0);
      h.controller.dispose();

      tokenRead.complete(token);
      await expectLater(pending, completes);

      expect(h.notifications, 0);
      expect(h.controller.state.status, SessionStatus.booting);
    });

    test('bootstrap: late token read sends no restore', () async {
      final token = _runtimeSecret(97, 3);
      final h = _Harness(tokens: <Uri, String>{_origin: token});
      final tokenRead = Completer<String?>();
      h.tokenStore.readGate = tokenRead;
      final pending = h.controller.bootstrap();
      await pumpEventQueue();
      expect(h.tokenStore.reads, 1);
      expect(h.repository.restoreCount, 0);
      h.controller.dispose();
      final before = h.calls;

      tokenRead.complete(token);
      await expectLater(pending, completes);

      expect(h.repository.restoreCount, 0);
      expect(h.calls, before);
      expect(h.notifications, 0);
      expect(h.controller.state.status, SessionStatus.booting);
    });

    test('bootstrap: late origin read sends no token read', () async {
      final repository = _AuthRepository();
      final tokenStore = _TokenStore(
        tokens: <Uri, String>{_origin: _runtimeSecret(89, 13)},
      );
      final baseUrlStore = _GatedBaseUrlStore(_origin);
      final originRead = Completer<Uri>();
      baseUrlStore.readGate = originRead;
      final controller = SessionController(
        repository: repository,
        tokenStore: tokenStore,
        baseUrlStore: baseUrlStore,
        requestRegistry: RequestRegistry(),
      );
      var notifications = 0;
      controller.addListener(() => notifications += 1);
      final pending = controller.bootstrap();
      await pumpEventQueue();
      expect(baseUrlStore.reads, 1);
      expect(tokenStore.reads, 0);
      controller.dispose();

      originRead.complete(_origin);
      await expectLater(pending, completes);

      expect(tokenStore.reads, 0);
      expect(controller.origin, BaseUrlPolicy.defaultOrigin);
      expect(repository.restoreCount, 0);
      expect(notifications, 0);
      expect(controller.state.status, SessionStatus.booting);
    });

    test('signOut: late logout success completes silently', () async {
      final h = _Harness(tokens: <Uri, String>{_origin: _runtimeSecret(59, 9)});
      final logout = Completer<void>();
      h.repository.logoutGate = logout;
      final pending = h.controller.signOut();
      await pumpEventQueue();
      expect(h.repository.logoutCount, 1);
      h.controller.dispose();

      logout.complete();
      await expectLater(pending, completes);

      expect(h.notifications, 0);
      expect(h.controller.state.status, SessionStatus.booting);
      expect(h.tokenStore.clears, 1);
      expect(h.tokenStore.tokens.containsKey(_origin), isFalse);
    });

    test('signOut: late logout failure completes silently', () async {
      final h = _Harness(
        tokens: <Uri, String>{_origin: _runtimeSecret(63, 11)},
      );
      final logout = Completer<void>();
      h.repository.logoutGate = logout;
      final pending = h.controller.signOut();
      await pumpEventQueue();
      expect(h.repository.logoutCount, 1);
      h.controller.dispose();

      logout.completeError(
        const ApiFailure(
          ApiFailureKind.network,
          requestId: 'local-late-logout-failure',
        ),
      );
      await expectLater(pending, completes);

      expect(h.notifications, 0);
      expect(h.controller.state.status, SessionStatus.booting);
      expect(h.tokenStore.clears, 1);
      expect(h.tokenStore.tokens.containsKey(_origin), isFalse);
    });

    test('changeOrigin: late token clear completes silently', () async {
      final h = _Harness(
        tokens: <Uri, String>{_origin: _runtimeSecret(71, 21)},
      );
      final clear = Completer<void>();
      h.tokenStore.clearGate = clear;
      final pending = h.controller.changeOrigin(_nextOrigin);
      await pumpEventQueue();
      expect(h.tokenStore.clears, 1);
      h.controller.dispose();

      clear.complete();
      await expectLater(pending, completes);

      expect(h.notifications, 0);
      expect(h.controller.state.status, SessionStatus.booting);
      expect(h.tokenStore.tokens.containsKey(_origin), isFalse);
      expect(h.baseUrlStore.origin, _nextOrigin);
    });

    test('expireIfCurrent: late token clear completes silently', () async {
      final h = _Harness(tokens: <Uri, String>{_origin: _runtimeSecret(77, 5)});
      final clear = Completer<void>();
      h.tokenStore.clearGate = clear;
      final pending = h.controller.expireIfCurrent(0);
      await pumpEventQueue();
      expect(h.tokenStore.clears, 1);
      h.controller.dispose();

      clear.complete();
      await expectLater(pending, completes);

      expect(h.notifications, 0);
      expect(h.controller.state.status, SessionStatus.booting);
      expect(h.tokenStore.tokens.containsKey(_origin), isFalse);
    });
  });

  group('SessionController dispose() twice', () {
    test('second dispose() returns normally without a notification', () {
      final h = _Harness();
      h.controller.dispose();

      expect(h.controller.dispose, returnsNormally);

      expect(h.notifications, 0);
    });
  });
}

typedef _Calls = ({
  int login,
  int restore,
  int logout,
  int tokenReads,
  int tokenWrites,
  int tokenClears,
  int tokenClearAlls,
  int originReads,
  int originWrites,
});

final class _Harness {
  _Harness({Map<Uri, String>? tokens})
    : repository = _AuthRepository(),
      tokenStore = _TokenStore(tokens: tokens),
      baseUrlStore = _BaseUrlStore(_origin),
      registry = RequestRegistry() {
    controller = SessionController(
      repository: repository,
      tokenStore: tokenStore,
      baseUrlStore: baseUrlStore,
      requestRegistry: registry,
    );
    controller.addListener(() => notifications += 1);
  }

  final _AuthRepository repository;
  final _TokenStore tokenStore;
  final _BaseUrlStore baseUrlStore;
  final RequestRegistry registry;
  late final SessionController controller;
  int notifications = 0;

  _Calls get calls => (
    login: repository.loginCount,
    restore: repository.restoreCount,
    logout: repository.logoutCount,
    tokenReads: tokenStore.reads,
    tokenWrites: tokenStore.writes,
    tokenClears: tokenStore.clears,
    tokenClearAlls: tokenStore.clearAlls,
    originReads: baseUrlStore.reads,
    originWrites: baseUrlStore.writes,
  );
}

final class _AuthRepository implements AuthRepository {
  int loginCount = 0;
  int restoreCount = 0;
  int logoutCount = 0;
  Completer<SessionUser>? loginGate;
  Completer<SessionUser>? restoreGate;
  Completer<void>? logoutGate;

  @override
  Future<SessionUser> login(String username, String password) {
    loginCount += 1;
    return loginGate?.future ??
        Future<SessionUser>.value(SessionUser(username));
  }

  @override
  Future<SessionUser> restore({RequestCancellation? cancellation}) {
    restoreCount += 1;
    return restoreGate?.future ??
        Future<SessionUser>.value(SessionUser('admin'));
  }

  @override
  Future<void> logout() {
    logoutCount += 1;
    return logoutGate?.future ?? Future<void>.value();
  }
}

final class _TokenStore implements TokenStore {
  _TokenStore({Map<Uri, String>? tokens}) : tokens = <Uri, String>{...?tokens};

  final Map<Uri, String> tokens;
  int reads = 0;
  int writes = 0;
  int clears = 0;
  int clearAlls = 0;
  Completer<String?>? readGate;
  Completer<void>? clearGate;

  @override
  Future<String?> read(Uri origin) {
    reads += 1;
    return readGate?.future ?? Future<String?>.value(tokens[origin]);
  }

  @override
  Future<void> write(Uri origin, String token) async {
    writes += 1;
    tokens[origin] = token;
  }

  @override
  Future<void> clear(Uri origin) async {
    clears += 1;
    final gate = clearGate;
    if (gate != null) await gate.future;
    tokens.remove(origin);
  }

  @override
  Future<void> clearAll() async {
    clearAlls += 1;
    tokens.clear();
  }
}

final class _BaseUrlStore implements BaseUrlStore {
  _BaseUrlStore(this.origin);

  Uri origin;
  int reads = 0;
  int writes = 0;

  @override
  Future<Uri> read() async {
    reads += 1;
    return origin;
  }

  @override
  Future<void> write(Uri origin) async {
    writes += 1;
    this.origin = origin;
  }
}

final class _GatedBaseUrlStore extends _BaseUrlStore {
  _GatedBaseUrlStore(super.origin);

  Completer<Uri>? readGate;

  @override
  Future<Uri> read() {
    reads += 1;
    return readGate?.future ?? Future<Uri>.value(origin);
  }
}

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}
