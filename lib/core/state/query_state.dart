import 'state_failure.dart';

enum QueryStatus { initial, loading, data, empty, refreshing, failed }

final class QueryState<T> {
  const QueryState._({
    required this.status,
    this.lastGoodData,
    this.failure,
    this.isStale = false,
    this.key,
  });

  const QueryState.initial({Object? key})
    : this._(status: QueryStatus.initial, key: key);

  const QueryState.loading({Object? key})
    : this._(status: QueryStatus.loading, key: key);

  const QueryState.data({required T data, Object? key})
    : this._(status: QueryStatus.data, lastGoodData: data, key: key);

  const QueryState.empty({Object? key})
    : this._(status: QueryStatus.empty, key: key);

  const QueryState.refreshing({T? lastGoodData, Object? key})
    : this._(
        status: QueryStatus.refreshing,
        lastGoodData: lastGoodData,
        key: key,
      );

  const QueryState.failed({
    required StateFailure failure,
    T? lastGoodData,
    bool isStale = false,
    Object? key,
  }) : this._(
         status: QueryStatus.failed,
         lastGoodData: lastGoodData,
         failure: failure,
         isStale: isStale,
         key: key,
       );

  /// 发起一次读取时的过渡态：没有旧数据就是首屏 loading，有就是保留旧数据的 refreshing。
  const QueryState.pending({T? previous, Object? key})
    : this._(
        status: previous == null ? QueryStatus.loading : QueryStatus.refreshing,
        lastGoodData: previous,
        key: key,
      );

  /// 读取失败：有旧数据则标记为过期继续展示，让 UI 提示「可能不是最新」。
  factory QueryState.failedAfter(Object error, {T? previous, Object? key}) =>
      QueryState<T>.failed(
        failure: StateFailure.fromError(error),
        lastGoodData: previous,
        isStale: previous != null,
        key: key,
      );

  final QueryStatus status;
  final T? lastGoodData;
  final StateFailure? failure;
  final bool isStale;
  final Object? key;
}
