part of 'automation_api.dart';

/// 后端 `store.AutomaticTask` 直接序列化：`payload` 是 `json.RawMessage`
/// （可能是 null / 对象 / 被二次编码的 JSON 字串），`next_run_at`、
/// `last_run_at` 可能是 `time.Time` 零值，老数据 `profile_iccid` 可能为空。
/// 一条脏任务不能拖垮整页，所以这些字段全部按 WEB `parseAutomaticTaskPayload`
/// 的口径容错；只有 id / name / device_id / task_type / environment 这些
/// 没了就没法展示与回写的字段才严格。
AutomationTask _parseTask(Object? value) {
  final raw = _shape.map(value);
  final id = _shape.positiveInt(raw['id']);
  final name = _shape.trimmedNonEmptyString(raw['name']);
  final enabled = _shape.boolean(raw['enabled']);
  final deviceId = _shape.trimmedNonEmptyString(raw['device_id']);
  final iccid = _shape.optionalString(raw['profile_iccid']).trim();
  final aid = _shape.optionalString(raw['profile_aid']).trim();
  final taskTypeText = _shape.trimmedNonEmptyString(raw['task_type']);
  final environmentText = _shape.trimmedNonEmptyString(raw['environment']);
  final intervalDays = _shape.nonNegativeInt(raw['interval_days']);
  final startDate = _shape.optionalString(raw['start_date']).trim();
  final runTime = _shape.optionalString(raw['run_time']).trim();
  final timezone = _shape.optionalString(raw['timezone']).trim();
  final payload = _payload(raw['payload']);
  final retryCount = _shape.nonNegativeInt(raw['retry_count']);
  final notify = _shape.boolean(raw['notify']);
  final nextRunAt = _optionalDate(raw['next_run_at']);
  final taskType = switch (taskTypeText) {
    'sms' => AutomationTaskType.sms,
    'call' => AutomationTaskType.call,
    'public_ip' => AutomationTaskType.publicIp,
    _ => throw const AutomationDtoException(),
  };
  final environment = switch (environmentText) {
    'vowifi' => AutomationEnvironment.vowifi,
    'cellular' => AutomationEnvironment.cellular,
    _ => throw const AutomationDtoException(),
  };
  final writeBody = <String, Object?>{
    'name': name,
    'enabled': enabled,
    'device_id': deviceId,
    'profile_iccid': iccid,
    'profile_aid': aid,
    'task_type': taskTypeText,
    'environment': environmentText,
    'interval_days': intervalDays,
    'start_date': startDate,
    'run_time': runTime,
    'timezone': timezone,
    'payload': payload,
    'retry_count': retryCount,
    'notify': notify,
  };
  return AutomationTask(
    id: id,
    name: name,
    enabled: enabled,
    deviceId: deviceId,
    profileDisplay: iccid.isEmpty ? '—' : Redaction.maskTail4(iccid),
    taskType: taskType,
    environment: environment,
    intervalDays: intervalDays,
    runTime: runTime,
    nextRunAt: nextRunAt,
    target: _AutomationTaskTarget(id, writeBody),
  );
}

AutomationRun _parseRun(Object? value) {
  final raw = _shape.map(value);
  return AutomationRun(
    id: _shape.positiveInt(raw['id']),
    taskId: _shape.positiveInt(raw['task_id']),
    deviceId: _shape.trimmedNonEmptyString(raw['device_id']),
    scheduledAt: _requiredDate(raw['scheduled_at']),
    startedAt: _optionalDate(raw['started_at']),
    finishedAt: _optionalDate(raw['finished_at']),
    status: _status(_shape.trimmedNonEmptyString(raw['status'])),
    attempts: _shape.nonNegativeInt(raw['attempts']),
    output: Redaction.sanitizeText(_shape.string(raw['output'])),
    error: Redaction.sanitizeText(_shape.string(raw['error'])),
  );
}

final class _AutomationTaskTarget implements AutomationTaskTarget {
  const _AutomationTaskTarget(this._id, this._writeBody);

  final int _id;
  final Map<String, Object?> _writeBody;

  @override
  String toString() => 'AutomationTaskTarget(id: $_id, redacted)';
}

final class AutomationDtoException implements DtoShapeException {
  const AutomationDtoException();
}

/// 后端 PUT 用 `DisallowUnknownFields` 解 `automaticTaskPayload`，回写时只能带
/// `phone / message / duration_seconds` 三个键；其余（老数据残留、二次编码的
/// 字串、null）一律丢掉，不然整条任务连开关都切不了。
const Set<String> _payloadKeys = <String>{
  'phone',
  'message',
  'duration_seconds',
};

Map<String, Object?> _payload(Object? value) {
  Object? decoded = value;
  if (decoded is String) {
    final text = decoded.trim();
    if (text.isEmpty) return <String, Object?>{};
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return <String, Object?>{};
    }
  }
  if (decoded is! Map<Object?, Object?>) return <String, Object?>{};
  return <String, Object?>{
    for (final entry in decoded.entries)
      if (entry.key is String && _payloadKeys.contains(entry.key))
        entry.key! as String: entry.value,
  };
}

DateTime _requiredDate(Object? value) {
  final parsed = _shape.dateTime(_shape.trimmedNonEmptyString(value));
  if (parsed.year <= 1) throw const AutomationDtoException();
  return parsed.toLocal();
}

DateTime? _optionalDate(Object? value) {
  if (value == null || value == '') return null;
  final parsed = _shape.dateTime(value);
  return parsed.year <= 1 ? null : parsed.toLocal();
}

AutomationRunStatus _status(String value) => switch (value) {
  'queued' => AutomationRunStatus.queued,
  'running' => AutomationRunStatus.running,
  'success' => AutomationRunStatus.success,
  'failed' => AutomationRunStatus.failed,
  _ => throw const AutomationDtoException(),
};

const _shape = JsonShape(AutomationDtoException.new);
