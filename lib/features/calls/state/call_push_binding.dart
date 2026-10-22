import 'dart:async';

import '../../../core/security/session_resource.dart';
import '../../../core/state/session_state.dart';
import '../../auth/state/session_controller.dart';
import '../data/call_push_registrar.dart';
import '../data/ios_call_push.dart';

/// 把 PushKit 令牌登记到网关的会话资源。
///
/// 三件事被刻意拆开：令牌由原生 PushKit 提供（[CallPushTokens]），登记是一次
/// 带会话的 HTTP 请求（[CallPushRegistrar]），而「什么时候该登记、失败之后
/// 多久再试」是会话生命周期问题——只有这里知道。登记成功是后台来电能响的
/// 唯一前提，所以失败必须自己重试，不能等用户下一次操作。
final class CallPushBinding implements SessionResource {
  CallPushBinding({required this.tokens, required this.registrar});

  final CallPushTokens tokens;
  final CallPushRegistrar registrar;

  /// 登记失败的重试区间：网关/网络没准备好是常态，但不能退到「一次失败就
  /// 永久静音」。上限用来兜住长时间离线的场合。
  static const Duration _retryFloor = Duration(seconds: 2);
  static const Duration _retryCeiling = Duration(minutes: 2);

  SessionController? _session;
  StreamSubscription<CallPushToken>? _changes;
  CallPushToken? _token;
  CallPushToken? _registered;
  Timer? _retry;
  Duration _retryDelay = _retryFloor;
  Future<void> _tail = Future<void>.value();
  SessionStatus? _observedStatus;
  bool _enabled = false;
  bool _disposed = false;

  void attach(SessionController session) {
    assert(_session == null);
    _session = session;
    session.registerResource(this);
    session.addListener(_onSessionChanged);
    _changes = tokens.changes.listen((token) {
      _token = token;
      _enqueue(_register);
    });
    _onSessionChanged();
  }

  void _onSessionChanged() {
    final session = _session!;
    final wasSignedIn = _observedStatus == SessionStatus.signedIn;
    _observedStatus = session.state.status;
    if (session.state.status != SessionStatus.signedIn) {
      if (_enabled) unawaited(clear());
      return;
    }
    // 登出过期会先清资源、后改状态：那段窗口里会话仍自称已登录，不能据此
    // 重新登记。只有一次真正的登录迁移才能重新打开登记。
    if (!_enabled && wasSignedIn) return;
    _enabled = true;
    _enqueue(_register);
  }

  Future<void> _register() async {
    if (!_live) return;
    final token = await _currentToken();
    if (token == null || !_live) return;
    if (token == _registered) return;
    try {
      await registrar.register(token);
    } catch (_) {
      _scheduleRetry();
      return;
    }
    if (!_live) return;
    _registered = token;
    _retry?.cancel();
    _retry = null;
    _retryDelay = _retryFloor;
  }

  Future<CallPushToken?> _currentToken() async {
    final known = _token;
    if (known != null) return known;
    try {
      return _token = await tokens.start();
    } catch (_) {
      // 通道暂时不可用不等于「已登记」：下一次触发会再读一次。
      return null;
    }
  }

  void _scheduleRetry() {
    if (!_live) return;
    _retry?.cancel();
    final delay = _retryDelay;
    _retryDelay = _retryDelay * 2 > _retryCeiling
        ? _retryCeiling
        : _retryDelay * 2;
    _retry = Timer(delay, () {
      _retry = null;
      _enqueue(_register);
    });
  }

  /// 登记是串行的：令牌事件、会话状态和重试可能在同一个 tick 里撞在一起，
  /// 排队能保证后一次看到的是前一次的结果（例如刚写完的 `_registered`）。
  void _enqueue(Future<void> Function() operation) {
    _tail = _tail.then((_) => operation()).catchError((Object _) {});
  }

  bool get _live => !_disposed && _enabled;

  @override
  Future<void> clear() {
    _enabled = false;
    _retry?.cancel();
    _retry = null;
    _retryDelay = _retryFloor;
    // 令牌是设备事实，跨会话仍然有效；失效的是「它已经被这次会话登记过」。
    _registered = null;
    return Future<void>.value();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session?.removeListener(_onSessionChanged);
    _session?.unregisterResource(this);
    unawaited(_changes?.cancel() ?? Future<void>.value());
    _changes = null;
    unawaited(clear());
  }
}