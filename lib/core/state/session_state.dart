import 'state_failure.dart';

enum SessionStatus { booting, signedOut, signingIn, signedIn, expired, failed }

final class SessionState {
  const SessionState._({
    required this.status,
    this.failure,
    this.principal,
    this.expiresAt,
    this.previousStable,
  });

  const SessionState.booting() : this._(status: SessionStatus.booting);

  const SessionState.signedOut() : this._(status: SessionStatus.signedOut);

  const SessionState.signingIn({SessionState? previousStable})
    : this._(status: SessionStatus.signingIn, previousStable: previousStable);

  const SessionState.signedIn({required Object principal, DateTime? expiresAt})
    : this._(
        status: SessionStatus.signedIn,
        principal: principal,
        expiresAt: expiresAt,
      );

  const SessionState.expired({StateFailure? failure})
    : this._(status: SessionStatus.expired, failure: failure);

  const SessionState.failed({
    required StateFailure failure,
    SessionState? previousStable,
  }) : this._(
         status: SessionStatus.failed,
         failure: failure,
         previousStable: previousStable,
       );

  final SessionStatus status;
  final StateFailure? failure;
  final Object? principal;
  final DateTime? expiresAt;
  final SessionState? previousStable;
}
