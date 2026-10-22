import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/session_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';

void main() {
  group('State failure boundaries', () {
    test('reject arbitrary objects for every failure payload', () {
      final dynamic createSessionFailure = SessionState.failed;
      final dynamic createQueryFailure = QueryState<String>.failed;
      final dynamic createKnownActionFailure = ActionState.failed;
      final dynamic createUnknownActionFailure = ActionState.failed;

      expect(
        () => createSessionFailure(failure: Object()),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => createQueryFailure(failure: Object()),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => createKnownActionFailure(knownFailure: Object()),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => createUnknownActionFailure(unknownOutcome: Object()),
        throwsA(isA<TypeError>()),
      );
    });

    test('does not retain an opaque raw failure value', () {
      final opaqueValue = _runtimeStateSecret(length: 47, offset: 2);
      final opaqueBody = '{"result":"$opaqueValue"}';

      final failure = StateFailure.fromUnsafeValue(
        StateFailureKind.generic,
        opaqueBody,
        statusCode: 503,
        retryAfter: const Duration(seconds: 30),
      );

      expect(
        <bool>[
          failure.message.contains(opaqueValue),
          failure.message.contains(opaqueBody),
        ],
        everyElement(isFalse),
        reason: 'state failure retained opaque raw input',
      );
      expect(failure.kind, StateFailureKind.generic);
      expect(failure.message, '出了点问题。');
      expect(failure.statusCode, 503);
      expect(failure.retryAfter, const Duration(seconds: 30));
    });

    test('fromError maps transport failures onto the shared kind table', () {
      StateFailure http(int status) => StateFailure.fromError(
        ApiFailure(
          ApiFailureKind.http,
          requestId: 'r',
          statusCode: status,
          retryAfter: status == 429 ? const Duration(seconds: 7) : null,
        ),
      );
      expect(http(401).kind, StateFailureKind.authentication);
      expect(http(403).kind, StateFailureKind.forbidden);
      expect(http(409).kind, StateFailureKind.conflict);
      expect(http(429).kind, StateFailureKind.rateLimited);
      expect(http(429).retryAfter, const Duration(seconds: 7));
      expect(http(500).kind, StateFailureKind.unavailable);
      expect(http(599).kind, StateFailureKind.unavailable);
      expect(http(404).kind, StateFailureKind.generic);
      expect(http(404).statusCode, 404);
      for (final (apiKind, stateKind) in <(ApiFailureKind, StateFailureKind)>[
        (ApiFailureKind.authentication, StateFailureKind.authentication),
        (ApiFailureKind.protocol, StateFailureKind.protocol),
        (ApiFailureKind.redirect, StateFailureKind.protocol),
        (ApiFailureKind.timeout, StateFailureKind.timeout),
        (ApiFailureKind.cancelled, StateFailureKind.cancelled),
        (ApiFailureKind.network, StateFailureKind.network),
      ]) {
        expect(
          StateFailure.fromError(ApiFailure(apiKind, requestId: 'r')).kind,
          stateKind,
        );
      }
      expect(
        StateFailure.fromError(const FormatException('bad json')).kind,
        StateFailureKind.protocol,
      );
      expect(
        StateFailure.fromError(StateError('unrelated')).kind,
        StateFailureKind.generic,
      );
    });

    test('login 403 uses the allowlisted backend code, not the raw body', () {
      const opaque = 'access is restricted to internal network addresses';
      final failure = StateFailure.fromError(
        const ApiFailure(
          ApiFailureKind.http,
          requestId: 'r',
          statusCode: 403,
          backendCode: 'network_access_denied',
          message: opaque,
        ),
      );
      expect(failure.kind, StateFailureKind.forbidden);
      expect(failure.backendCode, 'network_access_denied');
      expect(failure.message.contains(opaque), isFalse);
      expect(failure.message, contains('只允许内网登录'));
      expect(
        StateFailure.fromError(
          const ApiFailure(
            ApiFailureKind.http,
            requestId: 'r',
            statusCode: 403,
            backendCode: 'https_required',
          ),
        ).message,
        contains('HTTPS'),
      );
      expect(
        StateFailure.fromError(
          const ApiFailure(
            ApiFailureKind.http,
            requestId: 'r',
            statusCode: 403,
            backendCode: 'invalid_redirect_host',
          ),
        ).message,
        contains('HTTPS'),
      );
      expect(
        StateFailure.fromError(
          const ApiFailure(
            ApiFailureKind.http,
            requestId: 'r',
            statusCode: 403,
          ),
        ).message,
        '没有权限执行此操作。',
      );
    });
  });

  group('SessionState', () {
    test('exposes exactly the frozen statuses', () {
      expect(SessionStatus.values.map((status) => status.name), <String>[
        'booting',
        'signedOut',
        'signingIn',
        'signedIn',
        'expired',
        'failed',
      ]);
    });

    test('keeps principal expiry failure and previous stable as payloads', () {
      const principal = <String, String>{'displayName': 'Operator'};
      final expiresAt = DateTime.utc(2026, 9, 1, 12);
      final signedIn = SessionState.signedIn(
        principal: principal,
        expiresAt: expiresAt,
      );
      final signingIn = SessionState.signingIn(previousStable: signedIn);
      const failure = StateFailure(StateFailureKind.generic);
      final failed = SessionState.failed(
        failure: failure,
        previousStable: signedIn,
      );

      expect(signedIn.status, SessionStatus.signedIn);
      expect(signedIn.principal, same(principal));
      expect(signedIn.expiresAt, expiresAt);
      expect(signingIn.previousStable, same(signedIn));
      expect(failed.status, SessionStatus.failed);
      expect(failed.failure, failure);
      expect(failed.previousStable, same(signedIn));
    });
  });

  group('QueryState', () {
    test('exposes exactly the frozen statuses', () {
      expect(QueryStatus.values.map((status) => status.name), <String>[
        'initial',
        'loading',
        'data',
        'empty',
        'refreshing',
        'failed',
      ]);
    });

    test('refreshing retains last-good data and key', () {
      const lastGood = <String>['device-a'];
      const key = 'origin/session/device';

      const refreshing = QueryState<List<String>>.refreshing(
        lastGoodData: lastGood,
        key: key,
      );

      expect(refreshing.status, QueryStatus.refreshing);
      expect(refreshing.lastGoodData, same(lastGood));
      expect(refreshing.key, key);
      expect(refreshing.isStale, isFalse);
    });

    test('refresh failure retains old data and marks it stale', () {
      const lastGood = <String>['device-a'];
      const failure = StateFailure(StateFailureKind.timeout);

      final failed = QueryState<List<String>>.failed(
        failure: failure,
        lastGoodData: lastGood,
        isStale: true,
      );

      expect(failed.status, QueryStatus.failed);
      expect(failed.failure, failure);
      expect(failed.lastGoodData, same(lastGood));
      expect(failed.isStale, isTrue);
    });
  });

  group('ActionState', () {
    test('exposes exactly the frozen statuses', () {
      expect(ActionStatus.values.map((status) => status.name), <String>[
        'idle',
        'submitting',
        'succeeded',
        'failed',
      ]);
    });

    test('submitting carries only real operation progress payload', () {
      const submitting = ActionState.submitting(
        operationId: 'operation-42',
        progress: 0.25,
        reconciling: true,
      );

      expect(submitting.status, ActionStatus.submitting);
      expect(submitting.operationId, 'operation-42');
      expect(submitting.progress, 0.25);
      expect(submitting.reconciling, isTrue);
    });

    test('failed keeps unknown outcome distinct from known failure', () {
      const unknown = StateFailure(StateFailureKind.unknownOutcome);
      final failed = ActionState.failed(unknownOutcome: unknown);

      expect(failed.status, ActionStatus.failed);
      expect(failed.unknownOutcome, unknown);
      expect(failed.knownFailure, isNull);
      expect(failed.isUnknownOutcome, isTrue);
      expect(failed.status, isNot(ActionStatus.succeeded));
    });

    test('failed requires exactly one failure payload at runtime', () {
      StateFailure? absentKnownFailure;
      StateFailure? absentUnknownOutcome;
      const knownFailure = StateFailure(StateFailureKind.generic);
      const unknownOutcome = StateFailure(StateFailureKind.unknownOutcome);

      expect(
        () => ActionState.failed(
          knownFailure: absentKnownFailure,
          unknownOutcome: absentUnknownOutcome,
        ),
        throwsArgumentError,
      );
      expect(
        () => ActionState.failed(
          knownFailure: knownFailure,
          unknownOutcome: unknownOutcome,
        ),
        throwsArgumentError,
      );
    });
  });
}

String _runtimeStateSecret({required int length, required int offset}) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}
