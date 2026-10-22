import 'state_failure.dart';

enum ActionStatus { idle, submitting, succeeded, failed }

final class ActionState {
  const ActionState._({
    required this.status,
    this.knownFailure,
    this.unknownOutcome,
    this.operationId,
    this.progress,
    this.reconciling = false,
  });

  const ActionState.idle() : this._(status: ActionStatus.idle);

  const ActionState.submitting({
    String? operationId,
    double? progress,
    bool reconciling = false,
  }) : this._(
         status: ActionStatus.submitting,
         operationId: operationId,
         progress: progress,
         reconciling: reconciling,
       );

  const ActionState.succeeded({String? operationId})
    : this._(status: ActionStatus.succeeded, operationId: operationId);

  factory ActionState.failed({
    StateFailure? knownFailure,
    StateFailure? unknownOutcome,
  }) {
    if ((knownFailure == null) == (unknownOutcome == null)) {
      throw ArgumentError(
        'A failed action requires exactly one failure payload.',
      );
    }
    return ActionState._(
      status: ActionStatus.failed,
      knownFailure: knownFailure,
      unknownOutcome: unknownOutcome,
    );
  }

  /// 写操作抛错时的统一落点：超时 / 网络断开意味着服务端可能已经执行，
  /// 归为「结果未知」让 UI 提示去核对，其余按明确失败展示。
  factory ActionState.fromError(Object error) {
    final failure = StateFailure.fromError(error);
    return failure.kind == StateFailureKind.timeout ||
            failure.kind == StateFailureKind.network
        ? ActionState.failed(
            unknownOutcome: const StateFailure(StateFailureKind.unknownOutcome),
          )
        : ActionState.failed(knownFailure: failure);
  }

  final ActionStatus status;
  final StateFailure? knownFailure;
  final StateFailure? unknownOutcome;
  final String? operationId;
  final double? progress;
  final bool reconciling;

  bool get isUnknownOutcome => unknownOutcome != null;
}
