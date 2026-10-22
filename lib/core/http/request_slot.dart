import 'http_transport.dart';
import 'request_registry.dart';

/// 控制器里一条独立请求线（读列表 / 切卡 / 保存策略 / 发短信…）的生命周期槽。
///
/// 取代每个控制器手写的 `RequestRegistration? _xRegistration / int _xGeneration /
/// bool _isXCurrent()` 三件套：
/// - [begin] 作废上一代、向 [RequestRegistry] 注册取消令牌（同 key 的旧请求被登记表取消）；
/// - [RequestTicket.isCurrent] 在 await 之后判断结果是否仍然有效（没被新一代顶掉、
///   没被取消、控制器没 dispose）；
/// - [RequestTicket.end] 在 finally 里归还登记；
/// - [cancel] 主动取消在途请求并作废其结果；[close] 在 dispose 时一并收口。
final class RequestSlot {
  RequestSlot(this._registry, this.key);

  final RequestRegistry _registry;

  /// 默认登记 key；按设备等维度变化的请求可在 [begin] 时覆盖。
  final String key;
  RequestTicket? _active;
  int _generation = 0;
  bool _closed = false;

  /// 是否有在途请求。
  bool get isActive => _active != null;

  RequestTicket begin({String? key}) {
    final generation = ++_generation;
    final effectiveKey = key ?? this.key;
    final registration = _registry.register(effectiveKey);
    final ticket = RequestTicket._(
      this,
      generation,
      effectiveKey,
      registration,
    );
    _active = ticket;
    return ticket;
  }

  /// 取消在途请求并让它的结果作废；没有在途请求时只推进代际。
  void cancel() {
    _generation += 1;
    final ticket = _active;
    if (ticket == null) return;
    _active = null;
    ticket.registration.cancellation.cancel();
    _registry.remove(ticket.key, ticket.registration);
  }

  /// dispose 时调用：之后任何票据都不再 current。
  void close() {
    _closed = true;
    cancel();
  }

  bool _isCurrent(RequestTicket ticket) =>
      !_closed &&
      ticket._generation == _generation &&
      !ticket.registration.cancellation.isCancelled;

  void _end(RequestTicket ticket) {
    _registry.remove(ticket.key, ticket.registration);
    if (identical(_active, ticket)) _active = null;
  }
}

/// 一次 [RequestSlot.begin] 的凭据；持有本次的取消令牌与代际。
final class RequestTicket {
  RequestTicket._(this._slot, this._generation, this.key, this.registration);

  final RequestSlot _slot;
  final int _generation;
  final String key;
  final RequestRegistration registration;

  RequestCancellation get cancellation => registration.cancellation;

  /// await 回来后先问这一句：false 表示结果已过期，直接 return，不得写状态。
  bool get isCurrent => _slot._isCurrent(this);

  void end() => _slot._end(this);
}
