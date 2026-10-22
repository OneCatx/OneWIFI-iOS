import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/config/base_url_policy.dart';
import 'package:onewifi_android/core/config/base_url_store.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/security/secure_token_store.dart';
import 'package:onewifi_android/core/state/session_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import 'package:onewifi_android/features/auth/domain/session_user.dart';
import 'package:onewifi_android/features/auth/state/session_controller.dart';

void main() {
  group('SessionController bootstrap', () {
    test('no token becomes signed out without a restore request', () async {
      final harness = _Harness();

      await harness.controller.bootstrap();

      expect(
        harness.controller.state.status == SessionStatus.signedOut,
        isTrue,
      );
      expect(harness.repository.restoreCount, 0);
    });

    test(
      'exposes the stored origin after bootstrap and origin change',
      () async {
        final origin = Uri.parse('http://192.168.10.20:6688');
        final next = Uri.parse('http://10.0.0.8:6688');
        final harness = _Harness(origin: origin);

        expect(harness.controller.origin, BaseUrlPolicy.defaultOrigin);
        await harness.controller.bootstrap();
        expect(harness.controller.origin, origin);

        await harness.controller.changeOrigin(next);
        expect(harness.controller.origin, next);
        expect(harness.baseUrlStore.origin, next);
      },
    );

    test('a valid stored token restores a signed-in user', () async {
      final origin = Uri.parse('https://old.example.test');
      final harness = _Harness(
        origin: origin,
        tokens: <Uri, String>{origin: _runtimeSecret(41, 7)},
      );

      await harness.controller.bootstrap();

      expect(harness.controller.state.status == SessionStatus.signedIn, isTrue);
      expect(
        harness.controller.state.principal == SessionUser('admin'),
        isTrue,
      );
      expect(harness.repository.restoreCount, 1);
    });

    test('restore network failure retains the exact-origin token', () async {
      final origin = Uri.parse('https://old.example.test');
      final token = _runtimeSecret(49, 9);
      final harness = _Harness(
        origin: origin,
        tokens: <Uri, String>{origin: token},
        restoreHandler: (_) async => throw const ApiFailure(
          ApiFailureKind.network,
          requestId: 'local-network-failure',
        ),
      );

      await harness.controller.bootstrap();

      expect(harness.controller.state.status == SessionStatus.failed, isTrue);
      expect(
        harness.controller.state.failure?.kind == StateFailureKind.network,
        isTrue,
      );
      expect(harness.tokenStore.tokens[origin] == token, isTrue);
    });

    test(
      'a current 401 expires and its later restore error cannot overwrite it',
      () async {
        final origin = Uri.parse('https://old.example.test');
        final token = _runtimeSecret(55, 11);
        final restoreStarted = Completer<void>();
        final restore = Completer<_SessionResult>();
        final harness = _Harness(
          origin: origin,
          tokens: <Uri, String>{origin: token},
          restoreHandler: (_) {
            restoreStarted.complete();
            return restore.future;
          },
        );
        final bootstrap = harness.controller.bootstrap();
        await restoreStarted.future;

        try {
          await harness.controller.expireIfCurrent(0);
        } finally {
          restore.completeError(
            const ApiFailure(
              ApiFailureKind.http,
              requestId: 'local-current-unauthorized',
              statusCode: 401,
            ),
          );
          await bootstrap;
        }

        expect(
          harness.controller.state.status == SessionStatus.expired,
          isTrue,
        );
        expect(harness.controller.sessionEpoch, 1);
        expect(harness.tokenStore.tokens.containsKey(origin), isFalse);
      },
    );

    test(
      'a replaced restore cannot commit after the newer generation',
      () async {
        final origin = Uri.parse('https://old.example.test');
        final first = Completer<_SessionResult>();
        final second = Completer<_SessionResult>();
        var restoreIndex = 0;
        final harness = _Harness(
          origin: origin,
          tokens: <Uri, String>{origin: _runtimeSecret(89, 21)},
          restoreHandler: (_) {
            restoreIndex += 1;
            return restoreIndex == 1 ? first.future : second.future;
          },
        );

        final olderBootstrap = harness.controller.bootstrap();
        await Future<void>.delayed(Duration.zero);
        final newerBootstrap = harness.controller.bootstrap();
        await Future<void>.delayed(Duration.zero);
        second.complete(
          _SessionResult(SessionUser('newer-admin'), _runtimeSecret(91, 23)),
        );
        await newerBootstrap;
        first.completeError(
          const ApiFailure(
            ApiFailureKind.cancelled,
            requestId: 'local-replaced-restore',
          ),
        );
        await olderBootstrap;

        expect(
          harness.controller.state.status == SessionStatus.signedIn,
          isTrue,
        );
        expect(
          harness.controller.state.principal == SessionUser('newer-admin'),
          isTrue,
        );
      },
    );

    test(
      'origin change cancels bootstrap restore without a late failure commit',
      () async {
        final oldOrigin = Uri.parse('https://old.example.test');
        final newOrigin = Uri.parse('https://new.example.test');
        final restoreStarted = Completer<RequestCancellation>();
        final harness = _Harness(
          origin: oldOrigin,
          tokens: <Uri, String>{oldOrigin: _runtimeSecret(93, 25)},
          restoreHandler: (cancellation) async {
            final handle = cancellation!;
            restoreStarted.complete(handle);
            await handle.whenCancelled;
            throw const ApiFailure(
              ApiFailureKind.cancelled,
              requestId: 'local-origin-cancelled-restore',
            );
          },
        );
        final bootstrap = harness.controller.bootstrap();
        final cancellation = await restoreStarted.future;

        await harness.controller.changeOrigin(newOrigin);
        await bootstrap;

        expect(cancellation.isCancelled, isTrue);
        expect(
          harness.controller.state.status == SessionStatus.signedOut,
          isTrue,
        );
        expect(harness.baseUrlStore.origin == newOrigin, isTrue);
        expect(harness.controller.sessionEpoch, 1);
      },
    );

    test(
      'sign-out during gated token read prevents restore from starting',
      () async {
        final origin = Uri.parse('https://old.example.test');
        final token = _runtimeSecret(95, 1);
        final tokenReadStarted = Completer<void>();
        final tokenRead = Completer<String?>();
        final harness = _Harness(
          origin: origin,
          tokens: <Uri, String>{origin: token},
        );
        harness.tokenStore.readHandler = (_) {
          tokenReadStarted.complete();
          return tokenRead.future;
        };
        final bootstrap = harness.controller.bootstrap();
        await tokenReadStarted.future;

        await harness.controller.signOut();
        tokenRead.complete(token);
        await bootstrap;

        expect(harness.repository.restoreCount, 0);
        expect(
          harness.controller.state.status == SessionStatus.signedOut,
          isTrue,
        );
        expect(harness.tokenStore.tokens.containsKey(origin), isFalse);
      },
    );

    test(
      'origin change during gated token read prevents restore from starting',
      () async {
        final oldOrigin = Uri.parse('https://old.example.test');
        final newOrigin = Uri.parse('https://new.example.test');
        final token = _runtimeSecret(97, 3);
        final tokenReadStarted = Completer<void>();
        final tokenRead = Completer<String?>();
        final harness = _Harness(
          origin: oldOrigin,
          tokens: <Uri, String>{oldOrigin: token},
        );
        harness.tokenStore.readHandler = (_) {
          tokenReadStarted.complete();
          return tokenRead.future;
        };
        final bootstrap = harness.controller.bootstrap();
        await tokenReadStarted.future;

        await harness.controller.changeOrigin(newOrigin);
        tokenRead.complete(token);
        await bootstrap;

        expect(harness.repository.restoreCount, 0);
        expect(
          harness.controller.state.status == SessionStatus.signedOut,
          isTrue,
        );
        expect(harness.baseUrlStore.origin == newOrigin, isTrue);
        expect(harness.tokenStore.tokens.containsKey(oldOrigin), isFalse);
      },
    );

    test('failed sign-in invalidates a late restore commit', () async {
      final origin = Uri.parse('https://old.example.test');
      final restoreStarted = Completer<void>();
      final lateRestore = Completer<_SessionResult>();
      final harness = _Harness(
        origin: origin,
        tokens: <Uri, String>{origin: _runtimeSecret(99, 5)},
        restoreHandler: (_) {
          restoreStarted.complete();
          return lateRestore.future;
        },
        loginHandler: (_) async => throw const ApiFailure(
          ApiFailureKind.http,
          requestId: 'local-review-login-failure',
          statusCode: 401,
        ),
      );
      final bootstrap = harness.controller.bootstrap();
      await restoreStarted.future;

      await harness.controller.signIn('admin', _runtimeSecret(63, 7));
      lateRestore.complete(
        _SessionResult(SessionUser('late-admin'), _runtimeSecret(101, 9)),
      );
      await bootstrap;

      expect(harness.controller.state.status == SessionStatus.failed, isTrue);
      expect(
        harness.controller.state.failure?.kind ==
            StateFailureKind.authentication,
        isTrue,
      );
      expect(harness.controller.state.principal == null, isTrue);
    });
  });

  group('SessionController sign in', () {
    test(
      'secure token write completes before signed-in state is exposed',
      () async {
        final events = <String>[];
        final token = _runtimeSecret(57, 13);
        final remote = Completer<_SessionResult>();
        final harness = _Harness(loginHandler: (_) => remote.future);
        harness.tokenStore.onWrite = () => events.add('store-write');
        harness.controller.addListener(() {
          if (harness.controller.state.status == SessionStatus.signedIn) {
            events.add('signed-in');
          }
        });

        final pending = harness.controller.signIn(
          'admin',
          _runtimeSecret(45, 17),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          harness.controller.state.status == SessionStatus.signingIn,
          isTrue,
        );
        remote.complete(_SessionResult(SessionUser('admin'), token));
        await pending;
        expect(events, <String>['store-write', 'signed-in']);
        expect(
          harness.controller.state.status == SessionStatus.signedIn,
          isTrue,
        );
        expect(harness.controller.sessionEpoch, 1);
        expect(harness.tokenStore.tokens[harness.origin] == token, isTrue);
      },
    );

    test('login 401 is a sign-in failure and never a global expiry', () async {
      final origin = Uri.parse('https://old.example.test');
      final existingToken = _runtimeSecret(51, 19);
      final harness = _Harness(
        origin: origin,
        tokens: <Uri, String>{origin: existingToken},
        loginHandler: (_) async => throw const ApiFailure(
          ApiFailureKind.http,
          requestId: 'local-login-unauthorized',
          statusCode: 401,
        ),
      );

      await harness.controller.signIn('admin', _runtimeSecret(43, 21));

      expect(harness.controller.state.status == SessionStatus.failed, isTrue);
      expect(
        harness.controller.state.failure?.kind ==
            StateFailureKind.authentication,
        isTrue,
      );
      expect(harness.controller.state.status == SessionStatus.expired, isFalse);
      expect(harness.tokenStore.tokens[origin] == existingToken, isTrue);
      expect(harness.controller.sessionEpoch, 0);
    });

    test(
      'login 403 retains the existing token and reports forbidden',
      () async {
        final origin = Uri.parse('https://old.example.test');
        final existingToken = _runtimeSecret(53, 23);
        final harness = _Harness(
          origin: origin,
          tokens: <Uri, String>{origin: existingToken},
          loginHandler: (_) async => throw const ApiFailure(
            ApiFailureKind.http,
            requestId: 'local-login-forbidden',
            statusCode: 403,
          ),
        );

        await harness.controller.signIn('admin', _runtimeSecret(47, 25));

        expect(harness.controller.state.status == SessionStatus.failed, isTrue);
        expect(
          harness.controller.state.failure?.kind == StateFailureKind.forbidden,
          isTrue,
        );
        expect(harness.tokenStore.tokens[origin] == existingToken, isTrue);
        expect(harness.controller.sessionEpoch, 0);
      },
    );

    test('duplicate sign-in taps share one in-flight mutation', () async {
      final remote = Completer<_SessionResult>();
      final harness = _Harness(loginHandler: (_) => remote.future);
      final password = _runtimeSecret(49, 1);

      final first = harness.controller.signIn('admin', password);
      final second = harness.controller.signIn('admin', password);
      await Future<void>.delayed(Duration.zero);

      expect(identical(first, second), isTrue);
      expect(harness.repository.loginCount, 1);
      remote.complete(
        _SessionResult(SessionUser('admin'), _runtimeSecret(61, 5)),
      );
      await Future.wait<void>(<Future<void>>[first, second]);
      expect(harness.repository.loginCount, 1);
      expect(harness.controller.state.status == SessionStatus.signedIn, isTrue);
    });

    test(
      'secure-store write failure never exposes a signed-in state',
      () async {
        final harness = _Harness();
        var exposedSignedIn = false;
        harness.tokenStore.writeFailure = StateError('store unavailable');
        harness.controller.addListener(() {
          exposedSignedIn =
              exposedSignedIn ||
              harness.controller.state.status == SessionStatus.signedIn;
        });

        await harness.controller.signIn('admin', _runtimeSecret(55, 7));

        expect(exposedSignedIn, isFalse);
        expect(harness.controller.state.status == SessionStatus.failed, isTrue);
        expect(
          harness.controller.state.failure?.kind == StateFailureKind.generic,
          isTrue,
        );
        expect(harness.controller.sessionEpoch, 0);
      },
    );

    test(
      'validated expiry is stored in SessionState, never SessionUser',
      () async {
        final expiresAt = DateTime.utc(2031, 2, 3, 4, 5, 6);
        final harness = _Harness(
          loginHandler: (_) async => _SessionResult(
            SessionUser('admin'),
            _runtimeSecret(85, 13),
            expiresAt: expiresAt,
          ),
        );

        await harness.controller.signIn('admin', _runtimeSecret(59, 15));

        final principal = harness.controller.state.principal as SessionUser;
        expect(harness.controller.state.expiresAt == expiresAt, isTrue);
        expect(principal.username == 'admin', isTrue);
        expect(principal.toString().contains('2031'), isFalse);
      },
    );
  });

  group('SessionController sign out', () {
    test(
      'remote logout failure still clears local token and signs out',
      () async {
        final origin = Uri.parse('https://old.example.test');
        final harness = _Harness(
          origin: origin,
          tokens: <Uri, String>{origin: _runtimeSecret(59, 9)},
          logoutHandler: () async => throw const ApiFailure(
            ApiFailureKind.network,
            requestId: 'local-logout-network',
          ),
        );
        await harness.controller.bootstrap();

        await harness.controller.signOut();

        expect(harness.repository.logoutCount, 1);
        expect(harness.tokenStore.tokens.containsKey(origin), isFalse);
        expect(
          harness.controller.state.status == SessionStatus.signedOut,
          isTrue,
        );
        expect(harness.controller.sessionEpoch, 1);
      },
    );

    test('secure-store clear failure wins over the remote result', () async {
      final origin = Uri.parse('https://old.example.test');
      final token = _runtimeSecret(63, 11);
      final harness = _Harness(
        origin: origin,
        tokens: <Uri, String>{origin: token},
        logoutHandler: () async => throw const ApiFailure(
          ApiFailureKind.network,
          requestId: 'local-ignored-remote-error',
        ),
      );
      harness.tokenStore.clearFailure = StateError('store unavailable');

      try {
        await harness.controller.signOut();
      } catch (_) {
        // Failure must be represented safely in state rather than as sign-out.
      }

      expect(harness.controller.state.status == SessionStatus.failed, isTrue);
      expect(harness.tokenStore.tokens[origin] == token, isTrue);
      expect(
        harness.controller.state.status == SessionStatus.signedOut,
        isFalse,
      );
    });

    test(
      'sign-out queued during login clears the newly written token',
      () async {
        final token = _runtimeSecret(65, 13);
        final remoteLogin = Completer<_SessionResult>();
        final harness = _Harness(loginHandler: (_) => remoteLogin.future);

        final signIn = harness.controller.signIn(
          'admin',
          _runtimeSecret(51, 15),
        );
        await Future<void>.delayed(Duration.zero);
        final signOut = harness.controller.signOut();
        remoteLogin.complete(_SessionResult(SessionUser('admin'), token));

        await Future.wait<void>(<Future<void>>[signIn, signOut]);
        await Future<void>.delayed(Duration.zero);
        expect(
          harness.controller.state.status == SessionStatus.signedOut,
          isTrue,
        );
        expect(harness.tokenStore.tokens.containsKey(harness.origin), isFalse);
        expect(harness.controller.sessionEpoch, 2);
      },
    );
  });

  group('SessionController expiry epochs', () {
    test('a stale epoch cannot expire a newer signed-in session', () async {
      final token = _runtimeSecret(75, 25);
      final harness = _Harness(
        loginHandler: (_) async => _SessionResult(SessionUser('admin'), token),
      );
      await harness.controller.signIn('admin', _runtimeSecret(57, 3));
      final registeredRead = harness.registry.register('overview.load');

      await harness.controller.expireIfCurrent(0);

      expect(harness.controller.state.status == SessionStatus.signedIn, isTrue);
      expect(harness.controller.sessionEpoch, 1);
      expect(harness.tokenStore.tokens[harness.origin] == token, isTrue);
      expect(registeredRead.cancellation.isCancelled, isFalse);
    });

    test(
      'current expiry clear failure is a failed state, not clean expiry',
      () async {
        final origin = Uri.parse('https://old.example.test');
        final token = _runtimeSecret(77, 5);
        final harness = _Harness(
          origin: origin,
          tokens: <Uri, String>{origin: token},
        );
        harness.tokenStore.clearFailure = StateError('store unavailable');
        final registeredRead = harness.registry.register('overview.load');

        await harness.controller.expireIfCurrent(0);

        expect(registeredRead.cancellation.isCancelled, isTrue);
        expect(harness.controller.state.status == SessionStatus.failed, isTrue);
        expect(
          harness.controller.state.status == SessionStatus.expired,
          isFalse,
        );
        expect(harness.tokenStore.tokens[origin] == token, isTrue);
        expect(harness.controller.sessionEpoch, 1);
      },
    );

    test('current expiry origin-read failure is represented safely', () async {
      final harness = _Harness();
      harness.baseUrlStore.readFailure = StateError('preferences unavailable');
      final registeredRead = harness.registry.register('overview.load');

      try {
        await harness.controller.expireIfCurrent(0);
      } catch (_) {
        // The RED implementation leaked this error instead of setting state.
      }

      expect(registeredRead.cancellation.isCancelled, isTrue);
      expect(harness.controller.state.status == SessionStatus.failed, isTrue);
      expect(harness.controller.sessionEpoch, 1);
    });
  });

  group('SessionController origin change', () {
    test(
      'clears old and new credentials and cancels registered reads',
      () async {
        final oldOrigin = Uri.parse('https://old.example.test');
        final newOrigin = Uri.parse('https://new.example.test');
        final harness = _Harness(
          origin: oldOrigin,
          tokens: <Uri, String>{
            oldOrigin: _runtimeSecret(67, 17),
            newOrigin: _runtimeSecret(69, 19),
          },
        );
        final restoreRead = harness.registry.register('auth.restore');
        final overviewRead = harness.registry.register('overview.load');

        await harness.controller.changeOrigin(newOrigin);

        expect(restoreRead.cancellation.isCancelled, isTrue);
        expect(overviewRead.cancellation.isCancelled, isTrue);
        expect(harness.tokenStore.tokens.containsKey(oldOrigin), isFalse);
        expect(harness.tokenStore.tokens.containsKey(newOrigin), isFalse);
        expect(harness.baseUrlStore.origin == newOrigin, isTrue);
        expect(
          harness.controller.state.status == SessionStatus.signedOut,
          isTrue,
        );
        expect(harness.controller.sessionEpoch, 1);
      },
    );

    test(
      'an old-origin clear failure still attempts new-origin cleanup',
      () async {
        final oldOrigin = Uri.parse('https://old.example.test');
        final newOrigin = Uri.parse('https://new.example.test');
        final oldToken = _runtimeSecret(71, 21);
        final harness = _Harness(
          origin: oldOrigin,
          tokens: <Uri, String>{
            oldOrigin: oldToken,
            newOrigin: _runtimeSecret(73, 23),
          },
        );
        harness.tokenStore.clearFailures[oldOrigin] = StateError(
          'old store unavailable',
        );

        await harness.controller.changeOrigin(newOrigin);

        expect(harness.tokenStore.tokens[oldOrigin] == oldToken, isTrue);
        expect(harness.tokenStore.tokens.containsKey(newOrigin), isFalse);
        expect(harness.baseUrlStore.origin == oldOrigin, isTrue);
        expect(harness.controller.state.status == SessionStatus.failed, isTrue);
      },
    );

    test(
      'persistence failure does not fall back or migrate a session',
      () async {
        final oldOrigin = Uri.parse('https://old.example.test');
        final newOrigin = Uri.parse('https://new.example.test');
        final harness = _Harness(
          origin: oldOrigin,
          tokens: <Uri, String>{
            oldOrigin: _runtimeSecret(79, 7),
            newOrigin: _runtimeSecret(81, 9),
          },
        );
        harness.baseUrlStore.writeFailure = StateError(
          'preferences unavailable',
        );

        await harness.controller.changeOrigin(newOrigin);

        expect(harness.baseUrlStore.origin == oldOrigin, isTrue);
        expect(harness.tokenStore.tokens.containsKey(oldOrigin), isFalse);
        expect(harness.tokenStore.tokens.containsKey(newOrigin), isFalse);
        expect(harness.controller.state.status == SessionStatus.failed, isTrue);
        expect(harness.baseUrlStore.origin.port == 6688, isFalse);
      },
    );

    test('invalid origin is rejected through the existing policy', () async {
      final harness = _Harness();

      await harness.controller.changeOrigin(
        Uri.parse('https://example.com/api'),
      );

      expect(harness.controller.state.status == SessionStatus.failed, isTrue);
      expect(
        harness.controller.state.failure?.kind == StateFailureKind.protocol,
        isTrue,
      );
      expect(harness.controller.sessionEpoch, 0);
    });

    test('origin change queued during login cannot be resurrected', () async {
      final newOrigin = Uri.parse('https://new.example.test');
      final token = _runtimeSecret(87, 17);
      final remoteLogin = Completer<_SessionResult>();
      final harness = _Harness(loginHandler: (_) => remoteLogin.future);

      final signIn = harness.controller.signIn('admin', _runtimeSecret(61, 19));
      await Future<void>.delayed(Duration.zero);
      final changeOrigin = harness.controller.changeOrigin(newOrigin);
      remoteLogin.complete(_SessionResult(SessionUser('admin'), token));

      await Future.wait<void>(<Future<void>>[signIn, changeOrigin]);
      await Future<void>.delayed(Duration.zero);
      expect(
        harness.controller.state.status == SessionStatus.signedOut,
        isTrue,
      );
      expect(harness.baseUrlStore.origin == newOrigin, isTrue);
      expect(harness.tokenStore.tokens.containsKey(harness.origin), isFalse);
      expect(harness.tokenStore.tokens.containsKey(newOrigin), isFalse);
      expect(harness.controller.sessionEpoch, 2);
    });
  });

  test('approved API failures map to the closed safe state taxonomy', () async {
    final cases = <({ApiFailure error, StateFailureKind expected})>[
      (
        error: const ApiFailure(
          ApiFailureKind.authentication,
          requestId: 'local-authentication',
        ),
        expected: StateFailureKind.authentication,
      ),
      (
        error: const ApiFailure(
          ApiFailureKind.protocol,
          requestId: 'local-protocol',
        ),
        expected: StateFailureKind.protocol,
      ),
      (
        error: const ApiFailure(
          ApiFailureKind.redirect,
          requestId: 'local-redirect',
        ),
        expected: StateFailureKind.protocol,
      ),
      (
        error: const ApiFailure(
          ApiFailureKind.timeout,
          requestId: 'local-timeout',
        ),
        expected: StateFailureKind.timeout,
      ),
      (
        error: const ApiFailure(
          ApiFailureKind.cancelled,
          requestId: 'local-cancelled',
        ),
        expected: StateFailureKind.cancelled,
      ),
      (
        error: const ApiFailure(
          ApiFailureKind.network,
          requestId: 'local-network',
        ),
        expected: StateFailureKind.network,
      ),
      (
        error: const ApiFailure(
          ApiFailureKind.http,
          requestId: 'local-conflict',
          statusCode: 409,
        ),
        expected: StateFailureKind.conflict,
      ),
      (
        error: const ApiFailure(
          ApiFailureKind.http,
          requestId: 'local-rate-limit',
          statusCode: 429,
          retryAfter: Duration(seconds: 17),
        ),
        expected: StateFailureKind.rateLimited,
      ),
      (
        error: const ApiFailure(
          ApiFailureKind.http,
          requestId: 'local-unavailable',
          statusCode: 503,
        ),
        expected: StateFailureKind.unavailable,
      ),
    ];

    for (final testCase in cases) {
      final harness = _Harness(loginHandler: (_) async => throw testCase.error);

      await harness.controller.signIn('admin', _runtimeSecret(83, 11));

      final failure = harness.controller.state.failure;
      expect(failure?.kind == testCase.expected, isTrue);
      expect(failure?.statusCode == testCase.error.statusCode, isTrue);
      expect(failure?.retryAfter == testCase.error.retryAfter, isTrue);
      expect(failure?.message.contains(testCase.error.requestId), isFalse);
    }
  });
}

final class _Harness {
  _Harness({
    Uri? origin,
    Map<Uri, String>? tokens,
    _LoginHandler? loginHandler,
    _RestoreHandler? restoreHandler,
    _LogoutHandler? logoutHandler,
  }) : origin = origin ?? Uri.parse('https://old.example.test'),
       tokenStore = _TokenStore(tokens: tokens),
       baseUrlStore = _BaseUrlStore(
         origin ?? Uri.parse('https://old.example.test'),
       ),
       registry = RequestRegistry() {
    repository = _AuthRepository(
      tokenStore: tokenStore,
      baseUrlStore: baseUrlStore,
      loginHandler: loginHandler,
      restoreHandler: restoreHandler,
      logoutHandler: logoutHandler,
    );
    controller = SessionController(
      repository: repository,
      tokenStore: tokenStore,
      baseUrlStore: baseUrlStore,
      requestRegistry: registry,
    );
  }

  final Uri origin;
  final _TokenStore tokenStore;
  final _BaseUrlStore baseUrlStore;
  final RequestRegistry registry;
  late final _AuthRepository repository;
  late final SessionController controller;
}

typedef _LoginHandler = Future<_SessionResult> Function(String username);
typedef _RestoreHandler =
    Future<_SessionResult> Function(RequestCancellation? cancellation);
typedef _LogoutHandler = Future<void> Function();

final class _SessionResult {
  const _SessionResult(this.user, this.token, {this.expiresAt});

  final SessionUser user;
  final String token;
  final DateTime? expiresAt;
}

final class _AuthRepository implements AuthRepository, SessionExpirySource {
  factory _AuthRepository({
    required _TokenStore tokenStore,
    required _BaseUrlStore baseUrlStore,
    _LoginHandler? loginHandler,
    _RestoreHandler? restoreHandler,
    _LogoutHandler? logoutHandler,
  }) {
    return _AuthRepository._(
      tokenStore,
      baseUrlStore,
      loginHandler,
      restoreHandler,
      logoutHandler,
    );
  }

  _AuthRepository._(
    this.tokenStore,
    this.baseUrlStore,
    this._loginHandler,
    this._restoreHandler,
    this._logoutHandler,
  );

  final _TokenStore tokenStore;
  final _BaseUrlStore baseUrlStore;
  final _LoginHandler? _loginHandler;
  final _RestoreHandler? _restoreHandler;
  final _LogoutHandler? _logoutHandler;
  int loginCount = 0;
  int restoreCount = 0;
  int logoutCount = 0;
  final Expando<DateTime> _expiresAtByUser = Expando<DateTime>();

  @override
  Future<SessionUser> login(String username, String password) async {
    loginCount += 1;
    final result =
        await (_loginHandler?.call(username) ??
            Future<_SessionResult>.value(
              _SessionResult(SessionUser(username), _runtimeSecret(47, 3)),
            ));
    await tokenStore.write(await baseUrlStore.read(), result.token);
    _expiresAtByUser[result.user] = result.expiresAt;
    return result.user;
  }

  @override
  Future<SessionUser> restore({RequestCancellation? cancellation}) async {
    restoreCount += 1;
    final result =
        await (_restoreHandler?.call(cancellation) ??
            Future<_SessionResult>.value(
              _SessionResult(SessionUser('admin'), _runtimeSecret(43, 5)),
            ));
    _expiresAtByUser[result.user] = result.expiresAt;
    return result.user;
  }

  @override
  Future<void> logout() async {
    logoutCount += 1;
    await _logoutHandler?.call();
  }

  @override
  DateTime? takeSessionExpiresAt(SessionUser user) {
    final value = _expiresAtByUser[user];
    _expiresAtByUser[user] = null;
    return value;
  }
}

final class _TokenStore implements TokenStore {
  _TokenStore({Map<Uri, String>? tokens}) : tokens = <Uri, String>{...?tokens};

  final Map<Uri, String> tokens;
  Object? readFailure;
  Object? writeFailure;
  Object? clearFailure;
  final Map<Uri, Object> clearFailures = <Uri, Object>{};
  Future<String?> Function(Uri origin)? readHandler;
  void Function()? onWrite;
  void Function(Uri origin)? onClear;

  @override
  Future<String?> read(Uri origin) async {
    final failure = readFailure;
    if (failure != null) throw failure;
    final handler = readHandler;
    if (handler != null) return handler(origin);
    return tokens[origin];
  }

  @override
  Future<void> write(Uri origin, String token) async {
    onWrite?.call();
    final failure = writeFailure;
    if (failure != null) throw failure;
    tokens[origin] = token;
  }

  @override
  Future<void> clear(Uri origin) async {
    onClear?.call(origin);
    final failure = clearFailures[origin] ?? clearFailure;
    if (failure != null) throw failure;
    tokens.remove(origin);
  }

  @override
  Future<void> clearAll() async => tokens.clear();
}

final class _BaseUrlStore implements BaseUrlStore {
  _BaseUrlStore(this.origin);

  Uri origin;
  Object? readFailure;
  Object? writeFailure;

  @override
  Future<Uri> read() async {
    final failure = readFailure;
    if (failure != null) throw failure;
    return origin;
  }

  @override
  Future<void> write(Uri origin) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    this.origin = origin;
  }
}

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}
