import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/auth/data/auth_api.dart';
import '../../support/fakes.dart';

void main() {
  group('AuthApi exact requests and complete DTOs', () {
    test(
      'login is anonymous and sends exactly username and password',
      () async {
        final password = _runtimeSecret(37, 3);
        final sessionToken = _runtimeSecret(43, 7);
        final csrfToken = _runtimeSecret(31, 11);
        var tokenProviderCalls = 0;
        var requestContractMatched = false;
        final client = FakeClient((request) async {
          final body = jsonDecode(await _requestBody(request));
          requestContractMatched =
              request.method == 'POST' &&
              request.url.path == '/api/auth/login' &&
              body is Map<Object?, Object?> &&
              body.length == 2 &&
              body['username'] == 'admin' &&
              body['password'] == password &&
              !request.headers.containsKey('authorization') &&
              !request.headers.containsKey('cookie') &&
              !request.headers.containsKey('x-csrf-token');
          return _success(<String, Object?>{
            'user': <String, Object?>{'username': 'admin'},
            'csrf_token': csrfToken,
            'session_token': sessionToken,
            'expires_at': '2030-01-02T03:04:05Z',
            'authenticated': true,
            'status': 'ok',
          });
        });
        final api = _api(
          client,
          tokenProvider: (_) async {
            tokenProviderCalls += 1;
            return _runtimeSecret(41, 13);
          },
        );

        final session = await api.login('admin', password);

        expect(requestContractMatched, isTrue);
        expect(tokenProviderCalls, 0);
        expect(client.sendCount, 1);
        expect(session.username == 'admin', isTrue);
        expect(session.sessionToken == sessionToken, isTrue);
        expect(session.expiresAt == DateTime.utc(2030, 1, 2, 3, 4, 5), isTrue);
      },
    );

    test(
      'restore uses bearer GET and accepts the complete Android envelope',
      () async {
        final storedToken = _runtimeSecret(47, 5);
        final returnedToken = _runtimeSecret(53, 9);
        var requestContractMatched = false;
        final client = FakeClient((request) async {
          requestContractMatched =
              request.method == 'GET' &&
              request.url.path == '/api/auth/session' &&
              request.headers['authorization'] == 'Bearer $storedToken' &&
              !request.headers.containsKey('cookie') &&
              !request.headers.containsKey('x-csrf-token') &&
              (await _requestBody(request)).isEmpty;
          return _success(<String, Object?>{
            'user': <String, Object?>{'username': 'admin'},
            'session_token': returnedToken,
            'expires_at': '2030-01-02T03:04:05Z',
            'authenticated': true,
          });
        });
        final api = _api(client, tokenProvider: (_) async => storedToken);

        final session = await api.restore();

        expect(requestContractMatched, isTrue);
        expect(client.sendCount, 1);
        expect(session.username == 'admin', isTrue);
        expect(session.sessionToken == returnedToken, isTrue);
      },
    );

    test('logout is one bearer POST with no body, cookie, or CSRF', () async {
      final storedToken = _runtimeSecret(59, 1);
      var requestContractMatched = false;
      final client = FakeClient((request) async {
        requestContractMatched =
            request.method == 'POST' &&
            request.url.path == '/api/auth/logout' &&
            request.headers['authorization'] == 'Bearer $storedToken' &&
            !request.headers.containsKey('cookie') &&
            !request.headers.containsKey('x-csrf-token') &&
            (await _requestBody(request)).isEmpty;
        return _success(<String, Object?>{'logged_out': true});
      });

      await _api(client, tokenProvider: (_) async => storedToken).logout();

      expect(requestContractMatched, isTrue);
      expect(client.sendCount, 1);
    });
  });

  group('AuthApi strict sanitized responses', () {
    test(
      'rejects incomplete or invalid login data without retaining secrets',
      () async {
        final password = _runtimeSecret(37, 15);
        final responseToken = _runtimeSecret(61, 17);
        final invalidData = <Map<String, Object?>>[
          <String, Object?>{
            'user': <String, Object?>{'username': 'admin'},
            'session_token': responseToken,
            'expires_at': '2030-01-02T03:04:05Z',
            'authenticated': true,
            'status': 'ok',
          },
          <String, Object?>{
            'user': <String, Object?>{'username': ''},
            'csrf_token': _runtimeSecret(23, 2),
            'session_token': responseToken,
            'expires_at': '2030-01-02T03:04:05Z',
            'authenticated': true,
            'status': 'ok',
          },
          <String, Object?>{
            'user': <String, Object?>{'username': 'admin'},
            'csrf_token': _runtimeSecret(23, 4),
            'session_token': responseToken,
            'expires_at': 'not-a-date',
            'authenticated': true,
            'status': 'ok',
          },
          <String, Object?>{
            'user': <String, Object?>{'username': 'admin'},
            'csrf_token': _runtimeSecret(23, 6),
            'session_token': responseToken,
            'expires_at': '2030-01-02T03:04:05Z',
            'authenticated': false,
            'status': 'ok',
          },
          <String, Object?>{
            'user': <String, Object?>{'username': 'admin'},
            'csrf_token': '',
            'session_token': responseToken,
            'expires_at': '2030-01-02T03:04:05Z',
            'authenticated': true,
            'status': 'ok',
          },
          <String, Object?>{
            'user': <String, Object?>{'username': 'admin'},
            'csrf_token': _runtimeSecret(23, 8),
            'session_token': '',
            'expires_at': '2030-01-02T03:04:05Z',
            'authenticated': true,
            'status': 'ok',
          },
          <String, Object?>{
            'user': <String, Object?>{'username': 'admin'},
            'csrf_token': _runtimeSecret(23, 10),
            'session_token': responseToken,
            'expires_at': '2030-01-02T03:04:05Z',
            'authenticated': true,
            'status': 'not-ok',
          },
        ];
        var index = 0;
        final client = FakeClient((_) async => _success(invalidData[index++]));
        final api = _api(client, tokenProvider: (_) async => responseToken);

        for (
          var caseIndex = 0;
          caseIndex < invalidData.length;
          caseIndex += 1
        ) {
          final failure = await _apiFailureOf(api.login('admin', password));
          expect(failure.kind == ApiFailureKind.protocol, isTrue);
          expect(failure.message.contains(password), isFalse);
          expect(failure.message.contains(responseToken), isFalse);
          expect(failure.requestId.contains(password), isFalse);
          expect(failure.requestId.contains(responseToken), isFalse);
        }
        expect(client.sendCount, invalidData.length);
      },
    );

    test(
      'rejects invalid session and logout data as protocol failures',
      () async {
        final token = _runtimeSecret(67, 19);
        final responses = <Map<String, Object?>>[
          <String, Object?>{
            'user': <String, Object?>{'username': 'admin'},
            'session_token': token,
            'expires_at': '2030-01-02T03:04:05Z',
            'authenticated': 'true',
          },
          <String, Object?>{'logged_out': false},
        ];
        var index = 0;
        final client = FakeClient((_) async => _success(responses[index++]));
        final api = _api(client, tokenProvider: (_) async => token);

        final restoreFailure = await _apiFailureOf(api.restore());
        final logoutFailure = await _apiFailureOf(api.logout());

        expect(restoreFailure.kind == ApiFailureKind.protocol, isTrue);
        expect(logoutFailure.kind == ApiFailureKind.protocol, isTrue);
        expect(restoreFailure.message.contains(token), isFalse);
        expect(logoutFailure.message.contains(token), isFalse);
        expect(client.sendCount, 2);
      },
    );

    test(
      'rejects RFC3339 component overflow instead of normalizing it',
      () async {
        final invalidTimestamps = <String>[
          '2030-13-02T03:04:05Z',
          '2030-02-30T03:04:05Z',
          '2031-02-29T03:04:05Z',
          '2030-01-02T24:04:05Z',
          '2030-01-02T03:60:05Z',
          '2030-01-02T03:04:60Z',
          '2030-01-02T03:04:05+24:00',
          '2030-01-02T03:04:05+05:60',
        ];
        final password = _runtimeSecret(67, 21);
        final token = _runtimeSecret(109, 23);
        var index = 0;
        final client = FakeClient((_) async {
          final timestamp = invalidTimestamps[index++];
          return _success(<String, Object?>{
            'user': <String, Object?>{'username': 'admin'},
            'csrf_token': _runtimeSecret(31, index),
            'session_token': token,
            'expires_at': timestamp,
            'authenticated': true,
            'status': 'ok',
          });
        });
        final api = _api(client);
        var rejectedCount = 0;

        for (
          var caseIndex = 0;
          caseIndex < invalidTimestamps.length;
          caseIndex += 1
        ) {
          try {
            await api.login('admin', password);
          } on ApiFailure catch (failure) {
            if (failure.kind == ApiFailureKind.protocol) rejectedCount += 1;
          }
        }

        expect(rejectedCount, invalidTimestamps.length);
        expect(client.sendCount, invalidTimestamps.length);
      },
    );

    test('accepts valid leap-day fractional and offset boundaries', () async {
      final validTimestamps = <String>[
        '2032-02-29T23:59:59Z',
        '2000-02-29T00:00:00.123456+23:59',
        '1900-02-28T00:00:00-23:59',
      ];
      final password = _runtimeSecret(69, 25);
      var index = 0;
      final client = FakeClient((_) async {
        final timestamp = validTimestamps[index++];
        return _success(<String, Object?>{
          'user': <String, Object?>{'username': 'admin'},
          'csrf_token': _runtimeSecret(33, index),
          'session_token': _runtimeSecret(117, index + 3),
          'expires_at': timestamp,
          'authenticated': true,
          'status': 'ok',
        });
      });
      final api = _api(client);
      var acceptedCount = 0;

      for (
        var caseIndex = 0;
        caseIndex < validTimestamps.length;
        caseIndex += 1
      ) {
        try {
          await api.login('admin', password);
          acceptedCount += 1;
        } on ApiFailure {
          // Count-only assertion keeps diagnostics free of credential values.
        }
      }

      expect(acceptedCount, validTimestamps.length);
      expect(client.sendCount, validTimestamps.length);
    });
  });
}

AuthApi _api(
  http.BaseClient client, {
  Future<String?> Function(Uri origin)? tokenProvider,
}) {
  return AuthApi(
    HttpTransport(
      client: client,
      originProvider: () async => Uri.parse('https://api.example.test'),
      tokenProvider: tokenProvider ?? (_) async => null,
      requestIdGenerator: () => 'local-auth-test',
    ),
  );
}

http.StreamedResponse _success(Object? data) {
  return http.StreamedResponse(
    Stream<List<int>>.value(
      utf8.encode(jsonEncode(<String, Object?>{'data': data})),
    ),
    200,
  );
}

Future<String> _requestBody(http.BaseRequest request) async {
  return utf8.decode(await request.finalize().toBytes());
}

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}

Future<ApiFailure> _apiFailureOf(Future<Object?> pending) async {
  try {
    await pending;
  } on ApiFailure catch (failure) {
    return failure;
  }
  throw StateError('Expected sanitized API failure');
}
