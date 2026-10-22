import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/http/request_slot.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/request_notifier.dart';

// B1-03：同一 slot 上，`silent: true` 顶替 `silent: false` 后失败——被顶替方不写、
// silent 失败也不写，`pending`/`refreshing` 成为终态。
//
// 产品裁定：收回 last-good `data`，不把瞬时失败刷成 failed。
void main() {
  test('silent 顶替非 silent 并失败后，不得停留在 refreshing', () async {
    final p = _Probe();
    addTearDown(p.dispose);
    await p.load((_) async => 'alpha');
    expect(p.query.status, QueryStatus.data);

    final loudGate = Completer<String>();
    final loud = p.load((_) => loudGate.future);
    expect(p.query.status, QueryStatus.refreshing);

    final silentGate = Completer<String>();
    final silent = p.load((_) => silentGate.future, silent: true);

    silentGate.completeError(StateError('transient'));
    loudGate.complete('beta');
    await silent;
    await loud;

    expect(p.read.isActive, isFalse);
    expect(p.query.status, QueryStatus.data);
    expect(p.query.lastGoodData, 'alpha');
  });
}

final class _Probe extends RequestNotifier {
  _Probe() : read = RequestSlot(RequestRegistry(), 'probe.read');

  final RequestSlot read;
  QueryState<String> query = const QueryState<String>.initial(
    key: 'probe.read',
  );

  @override
  List<RequestSlot> get slots => <RequestSlot>[read];

  Future<void> load(
    Future<String> Function(RequestTicket ticket) fetch, {
    bool silent = false,
  }) => runQuery<String>(
    slot: read,
    current: () => query,
    set: (next) => publish(() => query = next),
    fetch: fetch,
    silent: silent,
  );
}
