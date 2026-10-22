import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/security/secure_token_store.dart';
import 'package:onewifi_android/features/auth/data/auth_api.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import '../../support/fakes.dart';

void main() {
  group('DefaultAuthRepository', () {
    test(
      'login writes the returned token to the captured exact origin',
      () async {
        final password = _runtimeSecret(39, 3);
        final sessionToken = _runtimeSecret(51, 7);
        final origin = Uri.parse('https://api.example.test');
        final events = <String>[];
        final client = FakeClient((_) async {
          events.add('remote-complete');
          return _sessionResponse(sessionToken);
        });
        final tokenStore = _TokenStore(
          onWrite: () => events.add('store-write'),
        );
        final repository = DefaultAuthRepository(
          api: _api(client, origin, tokenStore),
          tokenStore: tokenStore,
          originProvider: () async => origin,
        );

        final user = await repository.login('admin', password);

        expect(user.username == 'admin', isTrue);
        expect(user.toString().contains(sessionToken), isFalse);
        expect(tokenStore.lastWriteOrigin == origin, isTrue);
        expect(tokenStore.lastWriteToken == sessionToken, isTrue);
        expect(events, <String>['remote-complete', 'store-write']);
        final SessionExpirySource expirySource = repository;
        expect(
          expirySource.takeSessionExpiresAt(user) ==
              DateTime.utc(2030, 1, 2, 3, 4, 5),
          isTrue,
        );
        expect(expirySource.takeSessionExpiresAt(user) == null, isTrue);
      },
    );

    test(
      'restore validates the session without rewriting exact-origin storage',
      () async {
        final storedToken = _runtimeSecret(47, 11);
        final returnedToken = _runtimeSecret(53, 13);
        final origin = Uri.parse('https://api.example.test');
        final tokenStore = _TokenStore(initialToken: storedToken);
        final repository = DefaultAuthRepository(
          api: _api(
            FakeClient(
              (_) async => _sessionResponse(returnedToken, login: false),
            ),
            origin,
            tokenStore,
          ),
          tokenStore: tokenStore,
          originProvider: () async => origin,
        );

        final user = await repository.restore();

        expect(user.username == 'admin', isTrue);
        expect(tokenStore.lastWriteOrigin == null, isTrue);
        expect(tokenStore.lastWriteToken == null, isTrue);
        expect(tokenStore.writeCount, 0);
      },
    );

    test(
      'does not return a signed-in user when secure storage write fails',
      () async {
        final password = _runtimeSecret(41, 17);
        final sessionToken = _runtimeSecret(57, 19);
        final origin = Uri.parse('https://api.example.test');
        final tokenStore = _TokenStore(
          writeFailure: StateError('store unavailable'),
        );
        final repository = DefaultAuthRepository(
          api: _api(
            FakeClient((_) async => _sessionResponse(sessionToken)),
            origin,
            tokenStore,
          ),
          tokenStore: tokenStore,
          originProvider: () async => origin,
        );

        var returnedUser = false;
        try {
          await repository.login('admin', password);
          returnedUser = true;
        } catch (_) {
          // The externally asserted outcome is the absence of a returned user.
        }

        expect(returnedUser, isFalse);
        expect(tokenStore.writeCount, 1);
      },
    );

    test('concurrent operations do not cross-wire expiry metadata', () async {
      final origin = Uri.parse('https://api.example.test');
      final loginStarted = Completer<void>();
      final restoreStarted = Completer<void>();
      final loginResponse = Completer<http.StreamedResponse>();
      final restoreResponse = Completer<http.StreamedResponse>();
      final loginExpiry = DateTime.utc(2031, 2, 3, 4, 5, 6);
      final restoreExpiry = DateTime.utc(2032, 3, 4, 5, 6, 7);
      final tokenStore = _TokenStore(initialToken: _runtimeSecret(103, 11));
      final client = FakeClient((request) {
        if (request.url.path == '/api/auth/login') {
          loginStarted.complete();
          return loginResponse.future;
        }
        restoreStarted.complete();
        return restoreResponse.future;
      });
      final repository = DefaultAuthRepository(
        api: _api(client, origin, tokenStore),
        tokenStore: tokenStore,
        originProvider: () async => origin,
      );

      final login = repository.login('admin', _runtimeSecret(65, 13));
      final restore = repository.restore();
      await Future.wait<void>(<Future<void>>[
        loginStarted.future,
        restoreStarted.future,
      ]);
      loginResponse.complete(
        _sessionResponse(
          _runtimeSecret(105, 15),
          expiresAt: '2031-02-03T04:05:06Z',
        ),
      );
      final loginUser = await login;
      restoreResponse.complete(
        _sessionResponse(
          _runtimeSecret(107, 17),
          login: false,
          expiresAt: '2032-03-04T05:06:07Z',
        ),
      );
      final restoreUser = await restore;
      final SessionExpirySource expirySource = repository;

      final firstExpiry = expirySource.takeSessionExpiresAt(loginUser);
      final secondExpiry = expirySource.takeSessionExpiresAt(restoreUser);

      expect(identical(loginUser, restoreUser), isFalse);
      expect(firstExpiry == loginExpiry, isTrue);
      expect(secondExpiry == restoreExpiry, isTrue);
    });

    test(
      'overlapping restores retain expiry by returned user identity',
      () async {
        final origin = Uri.parse('https://api.example.test');
        final firstStarted = Completer<void>();
        final secondStarted = Completer<void>();
        final firstResponse = Completer<http.StreamedResponse>();
        final secondResponse = Completer<http.StreamedResponse>();
        final firstExpiry = DateTime.utc(2033, 4, 5, 6, 7, 8);
        final secondExpiry = DateTime.utc(2034, 5, 6, 7, 8, 9);
        var sendIndex = 0;
        final tokenStore = _TokenStore(initialToken: _runtimeSecret(111, 19));
        final client = FakeClient((_) {
          sendIndex += 1;
          if (sendIndex == 1) {
            firstStarted.complete();
            return firstResponse.future;
          }
          secondStarted.complete();
          return secondResponse.future;
        });
        final repository = DefaultAuthRepository(
          api: _api(client, origin, tokenStore),
          tokenStore: tokenStore,
          originProvider: () async => origin,
        );

        final firstRestore = repository.restore();
        final secondRestore = repository.restore();
        await Future.wait<void>(<Future<void>>[
          firstStarted.future,
          secondStarted.future,
        ]);
        firstResponse.complete(
          _sessionResponse(
            _runtimeSecret(113, 21),
            login: false,
            expiresAt: '2033-04-05T06:07:08Z',
          ),
        );
        final firstUser = await firstRestore;
        secondResponse.complete(
          _sessionResponse(
            _runtimeSecret(115, 23),
            login: false,
            expiresAt: '2034-05-06T07:08:09Z',
          ),
        );
        final secondUser = await secondRestore;
        final SessionExpirySource expirySource = repository;

        expect(identical(firstUser, secondUser), isFalse);
        expect(
          expirySource.takeSessionExpiresAt(firstUser) == firstExpiry,
          isTrue,
        );
        expect(
          expirySource.takeSessionExpiresAt(secondUser) == secondExpiry,
          isTrue,
        );
      },
    );
  });
}

AuthApi _api(http.BaseClient client, Uri origin, TokenStore tokenStore) {
  return AuthApi(
    HttpTransport(
      client: client,
      originProvider: () async => origin,
      tokenProvider: tokenStore.read,
      requestIdGenerator: () => 'local-repository-test',
    ),
  );
}

http.StreamedResponse _sessionResponse(
  String token, {
  bool login = true,
  String expiresAt = '2030-01-02T03:04:05Z',
}) {
  final data = <String, Object?>{
    'user': <String, Object?>{'username': 'admin'},
    if (login) 'csrf_token': _runtimeSecret(29, 23),
    'session_token': token,
    'expires_at': expiresAt,
    'authenticated': true,
    if (login) 'status': 'ok',
  };
  return http.StreamedResponse(
    Stream<List<int>>.value(
      utf8.encode(jsonEncode(<String, Object?>{'data': data})),
    ),
    200,
  );
}

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}

final class _TokenStore implements TokenStore {
  _TokenStore({this.initialToken, this.onWrite, this.writeFailure});

  final String? initialToken;
  final void Function()? onWrite;
  final Object? writeFailure;
  Uri? lastWriteOrigin;
  String? lastWriteToken;
  int writeCount = 0;

  @override
  Future<String?> read(Uri origin) async => initialToken;

  @override
  Future<void> write(Uri origin, String token) async {
    writeCount += 1;
    onWrite?.call();
    final failure = writeFailure;
    if (failure != null) throw failure;
    lastWriteOrigin = origin;
    lastWriteToken = token;
  }

  @override
  Future<void> clear(Uri origin) async {}

  @override
  Future<void> clearAll() async {}
}
