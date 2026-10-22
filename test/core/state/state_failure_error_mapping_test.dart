import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/state/state_failure.dart';

void main() {
  group('StateFailure.fromError ApiFailure → kind', () {
    test('maps authentication kind and 401 http', () {
      expect(
        StateFailure.fromError(
          const ApiFailure(
            ApiFailureKind.authentication,
            requestId: 'r1',
          ),
        ).kind,
        StateFailureKind.authentication,
      );
      expect(
        StateFailure.fromError(
          const ApiFailure(
            ApiFailureKind.http,
            requestId: 'r2',
            statusCode: 401,
            backendCode: 'unauthorized',
          ),
        ).kind,
        StateFailureKind.authentication,
      );
    });

    test('maps 403 to forbidden and preserves backendCode', () {
      final failure = StateFailure.fromError(
        const ApiFailure(
          ApiFailureKind.http,
          requestId: 'r3',
          statusCode: 403,
          backendCode: 'network_access_denied',
        ),
      );
      expect(failure.kind, StateFailureKind.forbidden);
      expect(failure.statusCode, 403);
      expect(failure.backendCode, 'network_access_denied');
    });

    test('maps network / timeout / cancelled / protocol', () {
      expect(
        StateFailure.fromError(
          const ApiFailure(ApiFailureKind.network, requestId: 'n'),
        ).kind,
        StateFailureKind.network,
      );
      expect(
        StateFailure.fromError(
          const ApiFailure(ApiFailureKind.timeout, requestId: 't'),
        ).kind,
        StateFailureKind.timeout,
      );
      expect(
        StateFailure.fromError(
          const ApiFailure(ApiFailureKind.cancelled, requestId: 'c'),
        ).kind,
        StateFailureKind.cancelled,
      );
      expect(
        StateFailure.fromError(
          const ApiFailure(ApiFailureKind.protocol, requestId: 'p'),
        ).kind,
        StateFailureKind.protocol,
      );
      expect(
        StateFailure.fromError(const FormatException('bad json')).kind,
        StateFailureKind.protocol,
      );
    });

    test('maps 409 / 429 / 5xx', () {
      expect(
        StateFailure.fromError(
          const ApiFailure(
            ApiFailureKind.http,
            requestId: 'c',
            statusCode: 409,
          ),
        ).kind,
        StateFailureKind.conflict,
      );
      expect(
        StateFailure.fromError(
          const ApiFailure(
            ApiFailureKind.http,
            requestId: 'r',
            statusCode: 429,
          ),
        ).kind,
        StateFailureKind.rateLimited,
      );
      expect(
        StateFailure.fromError(
          const ApiFailure(
            ApiFailureKind.http,
            requestId: 's',
            statusCode: 503,
            backendCode: 'unavailable',
          ),
        ).kind,
        StateFailureKind.unavailable,
      );
    });
  });

  group('StateFailure.message backendCode mapping', () {
    test('network_access_denied explains intranet-only policy', () {
      const failure = StateFailure(
        StateFailureKind.forbidden,
        statusCode: 403,
        backendCode: 'network_access_denied',
      );
      expect(failure.message, contains('只允许内网登录'));
      expect(failure.message, isNot(equals('没有权限执行此操作。')));
    });

    test('https_required and invalid_redirect_host map to HTTPS copy', () {
      expect(
        const StateFailure(
          StateFailureKind.forbidden,
          backendCode: 'https_required',
        ).message,
        contains('HTTPS'),
      );
      expect(
        const StateFailure(
          StateFailureKind.forbidden,
          backendCode: 'invalid_redirect_host',
        ).message,
        contains('HTTPS'),
      );
    });

    test('invalid_csrf maps to session re-login copy', () {
      expect(
        const StateFailure(
          StateFailureKind.forbidden,
          backendCode: 'invalid_csrf',
        ).message,
        contains('会话校验失败'),
      );
    });

    test('invalid_credentials and unauthorized have dedicated copy', () {
      expect(
        const StateFailure(
          StateFailureKind.authentication,
          backendCode: 'invalid_credentials',
        ).message,
        '用户名或密码错误。',
      );
      expect(
        const StateFailure(
          StateFailureKind.authentication,
          backendCode: 'unauthorized',
        ).message,
        '登录已失效，请重新登录。',
      );
      expect(
        const StateFailure(
          StateFailureKind.forbidden,
          backendCode: 'too_many_attempts',
        ).message,
        '尝试过多，请稍后再试。',
      );
      expect(
        const StateFailure(
          StateFailureKind.forbidden,
          backendCode: 'origin_rejected',
        ).message,
        contains('来源不被允许'),
      );
    });

    test('unknown backendCode falls back to kind message', () {
      expect(
        const StateFailure(
          StateFailureKind.forbidden,
          backendCode: 'blocked_destination',
        ).message,
        '没有权限执行此操作。',
      );
      expect(
        const StateFailure(StateFailureKind.network).message,
        '无法连接到服务。',
      );
      expect(
        const StateFailure(StateFailureKind.authentication).message,
        '身份验证失败，请重新登录。',
      );
    });

    test('login-relevant codes stay in BackendErrorCodes allow-list path',
        () {
      for (final code in <String>[
        'invalid_credentials',
        'unauthorized',
        'invalid_token',
        'invalid_csrf',
        'network_access_denied',
        'https_required',
        'invalid_redirect_host',
        'too_many_attempts',
        'password_mismatch',
        'weak_password',
      ]) {
        final failure = StateFailure.fromError(
          ApiFailure(
            ApiFailureKind.http,
            requestId: 'login-$code',
            statusCode: code == 'invalid_credentials' || code == 'unauthorized'
                ? 401
                : 403,
            backendCode: code,
          ),
        );
        expect(failure.backendCode, code);
        expect(failure.message, isNotEmpty);
      }
    });
  });
}
