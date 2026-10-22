import '../http/http_transport.dart' show ApiFailure, ApiFailureKind;

enum StateFailureKind {
  authentication,
  forbidden,
  network,
  protocol,
  timeout,
  cancelled,
  conflict,
  rateLimited,
  unavailable,
  generic,
  unknownOutcome,
}

final class StateFailure {
  const StateFailure(
    this.kind, {
    this.statusCode,
    this.retryAfter,
    this.backendCode,
  });

  factory StateFailure.fromUnsafeValue(
    StateFailureKind kind,
    Object? _, {
    int? statusCode,
    Duration? retryAfter,
    String? backendCode,
  }) {
    return StateFailure(
      kind,
      statusCode: statusCode,
      retryAfter: retryAfter,
      backendCode: backendCode,
    );
  }

  /// 所有控制器共用的一张错误分类表：传输层 [ApiFailure] 按种类与 HTTP 状态码
  /// 归到 UI 能处理的枚举；DTO 解析抛出的 [FormatException] 归协议错误；
  /// 其余一律 generic。故意不带任何原始报文，避免把后端消息泄到界面。
  factory StateFailure.fromError(Object error) {
    if (error is FormatException) {
      return const StateFailure(StateFailureKind.protocol);
    }
    if (error is! ApiFailure) {
      return const StateFailure(StateFailureKind.generic);
    }
    final kind = switch (error.kind) {
      ApiFailureKind.authentication => StateFailureKind.authentication,
      ApiFailureKind.protocol ||
      ApiFailureKind.redirect => StateFailureKind.protocol,
      ApiFailureKind.timeout => StateFailureKind.timeout,
      ApiFailureKind.cancelled => StateFailureKind.cancelled,
      ApiFailureKind.network => StateFailureKind.network,
      ApiFailureKind.http => switch (error.statusCode) {
        401 => StateFailureKind.authentication,
        403 => StateFailureKind.forbidden,
        409 => StateFailureKind.conflict,
        429 => StateFailureKind.rateLimited,
        final status? when status >= 500 && status <= 599 =>
          StateFailureKind.unavailable,
        _ => StateFailureKind.generic,
      },
    };
    return StateFailure(
      kind,
      statusCode: error.statusCode,
      retryAfter: error.retryAfter,
      backendCode: error.backendCode,
    );
  }

  final StateFailureKind kind;
  final int? statusCode;
  final Duration? retryAfter;
  final String? backendCode;

  String get message => switch (backendCode) {
    'network_access_denied' => '这台主机只允许内网登录。连家里的 Wi-Fi，或到网页设置把访问改成公网。',
    'https_required' => '这台主机要求走 HTTPS，把登录页的 HTTPS 打开。',
    'invalid_redirect_host' => '当前地址不能自动跳到 HTTPS。关掉 HTTPS，或改用家里的内网地址。',
    'invalid_csrf' => '会话校验失败，请再登一次。',
    'invalid_credentials' => '用户名或密码错误。',
    'too_many_attempts' => '尝试过多，请稍后再试。',
    'unauthorized' => '登录已失效，请重新登录。',
    'origin_rejected' => '当前来源不被允许访问此服务。',
    _ => switch (kind) {
      StateFailureKind.authentication => '身份验证失败，请重新登录。',
      StateFailureKind.forbidden => '没有权限执行此操作。',
      StateFailureKind.network => '无法连接到服务。',
      StateFailureKind.protocol => '服务返回了无法识别的数据。',
      StateFailureKind.generic => '出了点问题。',
      StateFailureKind.timeout => '请求超时。',
      StateFailureKind.cancelled => '请求已取消。',
      StateFailureKind.conflict => '请求与当前状态冲突。',
      StateFailureKind.rateLimited => '请求太频繁，请稍后再试。',
      StateFailureKind.unavailable => '服务暂时不可用。',
      StateFailureKind.unknownOutcome => '操作结果未知。',
    },
  };
}
