import 'dart:async';

import 'package:flutter/foundation.dart';

import '../http/request_slot.dart';
import 'action_state.dart';
import 'query_state.dart';

/// 功能片控制器的公共底座：统一「dispose 后静默」「写状态即通知」「请求线收口」，
/// 以及读查询 / 写动作两套票据样板。
///
/// 取代每个控制器手写的 `bool _disposed` / `_publish` / 逐个 `slot.close()`，
/// 和四处几乎相同的 `begin → 过渡态 → await → isCurrent → 终态 → finally end`。
/// 子类只描述「哪条请求线、读哪个状态、怎么写回、怎么取数」，票据与失效判断在这里。
abstract base class RequestNotifier extends ChangeNotifier {
  bool _disposed = false;

  /// dispose 之后为 true；之后所有状态写入与通知都静默。
  bool get isDisposed => _disposed;

  /// 本控制器持有的请求线，dispose 时按此顺序逐个 close。
  /// 动态创建的槽（按任务 / 设备维度的 map）用展开运算符并入。
  @protected
  List<RequestSlot> get slots;

  /// 写状态即通知；dispose 后静默。
  @protected
  void publish(void Function() assign) {
    if (_disposed) return;
    assign();
    notifyListeners();
  }

  /// 读查询样板。
  ///
  /// - 进入即 `slot.begin()`；`silent == false` 时先发 `pending(previous)`；
  /// - `fetch` 成功且票据仍 current：`isEmpty` 判空则 `empty`，否则 `data`；随后
  ///   `await onData`（二次读取、逐项补读等放这里）；
  /// - `fetch` 抛错且票据仍 current：非 silent 落 `failedAfter`；silent 若当前停在
  ///   loading/refreshing（刚顶替了别人的过渡态）则收回 last-good `data`，没有旧数据
  ///   才落 `failedAfter`，其余瞬时失败不写；
  /// - `finally ticket.end()`。
  ///
  /// [silent] 用于静默轮询：不切过渡态、不把瞬时失败刷成失败态，只在拿到新数据时替换。
  @protected
  Future<void> runQuery<T>({
    required RequestSlot slot,
    required QueryState<T> Function() current,
    required void Function(QueryState<T> next) set,
    required Future<T> Function(RequestTicket ticket) fetch,
    bool Function(T value)? isEmpty,
    FutureOr<void> Function(T value, RequestTicket ticket)? onData,
    bool silent = false,
  }) async {
    if (_disposed) return;
    final ticket = slot.begin();
    final previous = current().lastGoodData;
    if (!silent) {
      set(QueryState<T>.pending(previous: previous, key: slot.key));
    }
    try {
      final value = await fetch(ticket);
      if (!ticket.isCurrent) return;
      set(
        isEmpty != null && isEmpty(value)
            ? QueryState<T>.empty(key: slot.key)
            : QueryState<T>.data(data: value, key: slot.key),
      );
      if (onData != null) await onData(value, ticket);
    } catch (error) {
      if (!ticket.isCurrent) return;
      if (silent) {
        final pending = current();
        if (pending.status == QueryStatus.loading ||
            pending.status == QueryStatus.refreshing) {
          final kept = pending.lastGoodData;
          set(
            kept != null
                ? QueryState<T>.data(data: kept, key: slot.key)
                : QueryState<T>.failedAfter(error, key: slot.key),
          );
        }
        return;
      }
      set(QueryState<T>.failedAfter(error, previous: previous, key: slot.key));
    } finally {
      ticket.end();
    }
  }

  /// 写动作样板。返回 true 表示请求成功且终态已在票据 current 时落下。
  ///
  /// - 已 dispose 或该动作正在 submitting → 直接返回 false，不发请求；
  /// - `slot.begin(key: key)`，`set(submitting)`；
  /// - 成功且票据 current：没有 [onSuccess] 就 `set(succeeded)`；否则由回调决定终态——
  ///   返回非 null 则在再次确认票据 current 后 `set`，返回 null 表示回调已自行处理
  ///   （或有意不改）；
  /// - 抛错且票据 current：`set(ActionState.fromError(error))`，再 `onFailure`；
  /// - `finally { always; ticket.end(); }`。
  @protected
  Future<bool> runAction<T>({
    required RequestSlot slot,
    required ActionState Function() current,
    required void Function(ActionState next) set,
    required Future<T> Function(RequestTicket ticket) request,
    String? key,
    ActionState submitting = const ActionState.submitting(),
    FutureOr<ActionState?> Function(T result, RequestTicket ticket)? onSuccess,
    void Function(Object error)? onFailure,
    void Function(RequestTicket ticket)? always,
  }) async {
    if (_disposed || current().status == ActionStatus.submitting) return false;
    final ticket = slot.begin(key: key);
    set(submitting);
    try {
      final result = await request(ticket);
      if (!ticket.isCurrent) return false;
      if (onSuccess == null) {
        set(const ActionState.succeeded());
        return true;
      }
      final next = await onSuccess(result, ticket);
      if (!ticket.isCurrent) return false;
      if (next != null) set(next);
      return true;
    } catch (error) {
      if (!ticket.isCurrent) return false;
      set(ActionState.fromError(error));
      onFailure?.call(error);
      return false;
    } finally {
      always?.call(ticket);
      ticket.end();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final slot in slots) {
      slot.close();
    }
    super.dispose();
  }
}
