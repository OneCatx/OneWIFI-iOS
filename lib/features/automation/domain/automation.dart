abstract interface class AutomationTaskTarget {}

enum AutomationTaskType {
  sms,

  /// 旧任务解码用。网关已拒绝新建/执行 `call`，App 不再提供拨号入口。
  call,
  publicIp,
}

enum AutomationEnvironment { vowifi, cellular }

enum AutomationRunStatus { queued, running, success, failed }

final class AutomationTask {
  const AutomationTask({
    required this.id,
    required this.name,
    required this.enabled,
    required this.deviceId,
    required this.profileDisplay,
    required this.taskType,
    required this.environment,
    required this.intervalDays,
    required this.runTime,
    required this.nextRunAt,
    required this.target,
  });

  final int id;
  final String name;
  final bool enabled;
  final String deviceId;
  final String profileDisplay;
  final AutomationTaskType taskType;
  final AutomationEnvironment environment;
  final int intervalDays;
  final String runTime;

  /// 后端 `time.Time` 零值（0001-01-01）会照实吐出来；这里当「未排期」。
  final DateTime? nextRunAt;
  final AutomationTaskTarget target;

  AutomationTask copyWith({bool? enabled}) => AutomationTask(
    id: id,
    name: name,
    enabled: enabled ?? this.enabled,
    deviceId: deviceId,
    profileDisplay: profileDisplay,
    taskType: taskType,
    environment: environment,
    intervalDays: intervalDays,
    runTime: runTime,
    nextRunAt: nextRunAt,
    target: target,
  );

  @override
  String toString() =>
      'AutomationTask(id: $id, name: $name, enabled: $enabled, type: ${taskType.name})';
}

final class AutomationRun {
  const AutomationRun({
    required this.id,
    required this.taskId,
    required this.deviceId,
    required this.scheduledAt,
    required this.startedAt,
    required this.finishedAt,
    required this.status,
    required this.attempts,
    required this.output,
    required this.error,
  });

  final int id;
  final int taskId;
  final String deviceId;
  final DateTime scheduledAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final AutomationRunStatus status;
  final int attempts;
  final String output;
  final String error;

  @override
  String toString() =>
      'AutomationRun(id: $id, taskId: $taskId, status: ${status.name}, attempts: $attempts)';
}

final class AutomationRunPage {
  const AutomationRunPage({required this.runs, required this.total});

  final List<AutomationRun> runs;
  final int total;
}

final class AutomationWorkspace {
  const AutomationWorkspace({
    required this.tasks,
    required this.runs,
    required this.runTotal,
  });

  final List<AutomationTask> tasks;
  final List<AutomationRun> runs;
  final int runTotal;
}
