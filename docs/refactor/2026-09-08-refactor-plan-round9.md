# 2026-09-08 · 第九轮重构计划书（细颗粒度 · 状态层控制器样板去重）

> 状态：**规格已冻结**（第 1–7 节执行期不得改软）。执行记录见第 11 节。
> 方法：migration-refactor 六内核 —— 先侦察 → 冻结规格与规则手册 → 裁判先就位 → 试点批试航 → 机械分批 → 漂移自审 → 验证修复环 → 可回滚。
> 状态根：`.xj-cursor/refactor-r9/`（gitignored；基线、哈希、账本、交接都在那里）。
> 基线提交：`4497b4a`（`main`）。工作区 18 个「M」全为 CRLF 行尾噪声（`git diff --numstat` 为空），源码内容等同 HEAD；`docs/perf/` 为另一条在途工作（性能第一轮），本轮不碰。

## 0. 侦察结论（有证据，非拍脑袋）

| 事实 | 证据 |
|---|---|
| 裁判强：`dart format` 189/0、`flutter analyze` 0 issues、`flutter test` **559/559**（36 s） | `.xj-cursor/refactor-r9/baseline/{format,analyze,test}.log` |
| 第八轮已把表现层拆分惯例补齐到全部功能片，并明确写下「本轮不动状态与数据层」 | `docs/refactor/2026-09-07-refactor-plan-round8.md` §1 OUT OF SCOPE |
| 9 个控制器（8 功能片 + 会话）全部 `extends ChangeNotifier`，各自手写同一套 `bool _disposed` / `_publish` 或 `_setX` 守卫 / `dispose()` 逐个 `slot.close()` | 逐文件阅读；`_publish(`×3、`bool _disposed`×9、`slot.close()`×9 |
| 「读查询」样板（begin → previous → pending → await → isCurrent → data/empty → catch isCurrent → failedAfter → finally end）出现 **11 处**，其中 6 处逐字机械、5 处带局部变体 | `QueryState.pending(previous` 11 处、`QueryState.failedAfter(` 10 处 |
| 「写动作」样板（guard submitting → begin → submitting → await → isCurrent → succeeded → catch fromError → finally end）出现 **9 处**；其中 3 个控制器各自私有了一份泛型版本（`settings._runAction`、`automation._write`、`device_detail._runAction`），`esim._mutateProfile` 是第 4 份半泛型，其余内联 | `ActionState.fromError(error)` 10 处 |
| 生命周期测试对「通知次数」「仓储调用序列」「状态对象身份 `same()`」「dispose 后静默」做精确断言，是天然的等价性裁判 | `test/features/*/state/*_lifecycle_test.dart` ×8、`*_controller_test.dart` ×8、`settings_controller_actions_test.dart` |
| 数据层已有共享 `JsonShape`，各 dto 残留的私有助手只是「带默认值」的 3–5 行变体，去重收益低 | `lib/core/http/json_shape.dart`；`*_dto.dart` 私有函数扫描 |
| `analysis_options.yaml` 开了 `strict-casts / strict-inference / strict-raw-types` + `directives_ordering` | 文件内容 |
| `logs_screen` 只在 `dispose` 里调 `stopWatching()`，没有监听者在通知回调里同步调 `start/stopWatching` | grep `lib/features/logs` |

可行性裁决：**GO**。理由：结构保持型重构；裁判就位且强（每个控制器都有行为 + 生命周期两套测试）；改动面 9 个源文件 + 1 个新核心文件 + 1 个新测试文件；无外部消费者（独立 App）；无依赖变化。

## 1. 迁移目标与范围

**目标（一句话）**：在不改变任何外部可见行为（状态序列、通知次数、仓储调用序列、dispose 语义）的前提下，把 9 个控制器共有的「dispose 守卫 / 发布 / 请求线收口」与「读查询 / 写动作」样板收敛到 `lib/core/state/request_notifier.dart` 一处，删除 4 份私有泛型副本与 ~15 处内联副本。类型：**结构保持型**。

### IN SCOPE（工作项全集，也是漂移检查白名单）

| 主题 | 文件 |
|---|---|
| P · 核心底座（试点批） | 新 `lib/core/state/request_notifier.dart`、新 `test/core/state/request_notifier_test.dart`；改 `lib/features/logs/state/logs_controller.dart` |
| A · esim | `lib/features/esim/state/esim_controller.dart` |
| B · sms | `lib/features/sms/state/sms_controller.dart` |
| C · settings | `lib/features/settings/state/settings_controller.dart` |
| D · devices | `lib/features/devices/state/device_list_controller.dart`、`device_detail_controller.dart` |
| E · 轻量三件 | `lib/features/automation/state/automation_controller.dart`、`lib/features/overview/state/overview_controller.dart`、`lib/features/auth/state/session_controller.dart` |
| 测试 | 既有 `test/**` **一字不改**；只允许新增 `test/core/state/request_notifier_test.dart` |

### OUT OF SCOPE（不许碰）

- `pubspec.yaml` / `pubspec.lock` / `analysis_options.yaml` / `.gitignore` / `.gitattributes` / `android/**` / `assets/**` / `docs/perf/**`
- `lib/core/http/**`（`RequestSlot` / `RequestTicket` / `RequestRegistry` 签名不变）、`lib/core/state/{query_state,action_state,state_failure,session_state}.dart`
- 所有 `data/`、`domain/`、`presentation/` 目录；`lib/app/**`（`AppearanceController` 没有请求线，不纳入；`AppDependencies` 的 `_disposed` 是资源容器语义，不纳入）
- 控制器的**公开 API**（类名、构造签名、getter 名与类型、方法名与签名）一律不变
- 任何用户可见文案
- git 写操作：**不 commit、不 push、不 stash、不 reset、不改行尾**

### 依赖锁定

不允许新增或升级任何依赖。`DEPENDENCY_ALLOWLIST` 为空。

## 2. 成功判据与行为契约

**成功判据（全部满足才算完成）**

1. `dart format --output=none --set-exit-if-changed lib test` 退出 0
2. `flutter analyze --no-pub` 0 issues
3. `flutter test --no-pub` 全绿，用例数 ≥ 559（只增不减；既有 `test/**` 文件哈希与 `BASELINE_HASHES.tsv` 一致）
4. `lib/features/**/state/*.dart` 中：`bool _disposed` 0 处、`void _publish(` 0 处、`@override void dispose()` 仅出现在需要额外收尾的 3 个控制器（logs 停表、automation / device_list 清动态槽 map）
5. `lib/` 内 `QueryState.pending(previous` 仅出现在 `request_notifier.dart` 与第 5 节列明保留内联的 4 处（settings.load、overview._request、automation.load、sms._readThread）
6. `lib/` 内 `ActionState.fromError(error)` 仅出现在 `request_notifier.dart` 与 esim.download 这 1 处保留内联
7. 9 个控制器全部 `extends RequestNotifier`；`lib/features/**/state/` 不再 `import 'package:flutter/foundation.dart'`，除非仍用到 `VoidCallback` 等其它符号
8. `git status --porcelain` 只列出第 1 节 IN SCOPE 文件 + 本计划书；`git ls-files --eol` 无新增 `w/crlf`

**行为契约（必须保持）**

- 每个公开方法在每条路径上 `notifyListeners()` 的**次数与顺序**与迁移前逐一相同
- 每个公开方法触发的仓储调用**序列**（含参数）相同；不多发一次请求，不少发一次
- `RequestSlot.begin()` 的 key、`QueryState.key` 的值相同
- 票据失效（被顶替 / 取消 / dispose）后不写任何状态、不通知——与迁移前同一判断点
- dispose 后所有公开方法静默返回；二次 dispose 不通知不抛
- `QueryState` 的 `empty` / `data` 判定谓词、`isStale` 语义逐字相同
- 私有字段的静默赋值（不伴随通知的）允许在「同一段同步代码内」前移或后移，但不得跨越任何 `await` 或 `notifyListeners()`

**有意的改进（单独声明）**：无。本轮零功能变更。

## 3. 冻结的 API（`lib/core/state/request_notifier.dart` · 试点批已实现并通过 25 个用例）

以下签名是宪法，子代理不得增删参数；发现不够用 → 标 `BLOCKED` 回报，由主 Agent 修订规格后重派。

```dart
abstract base class RequestNotifier extends ChangeNotifier {
  /// dispose 之后为 true；取代各控制器的 `bool _disposed`。
  bool get isDisposed;

  /// 本控制器持有的请求线，dispose 时按此顺序逐个 close。
  /// 动态创建的槽（map）用展开运算符并入：`[_read, ..._writes.values]`。
  @protected
  List<RequestSlot> get slots;

  /// 写状态即通知；dispose 后静默。取代 `_publish` / 手写 `if (_disposed) return; x = next; notifyListeners();`。
  @protected
  void publish(void Function() assign);

  /// 读查询样板。
  /// - 进入即 `slot.begin()`；`silent == false` 时先发 `pending(previous)`；
  /// - `fetch` 成功且票据仍 current：`isEmpty?.call(value) == true` → `empty`，否则 `data`；随后 `await onData?.call(value, ticket)`；
  /// - `fetch` 抛错且票据仍 current 且 `!silent`：`failedAfter(error, previous)`；
  /// - `finally ticket.end()`。
  @protected
  Future<void> runQuery<T>({
    required RequestSlot slot,
    required QueryState<T> Function() current,
    required void Function(QueryState<T> next) set,
    required Future<T> Function(RequestTicket ticket) fetch,
    bool Function(T value)? isEmpty,
    FutureOr<void> Function(T value, RequestTicket ticket)? onData,
    bool silent = false,
  });

  /// 写动作样板。返回 true 表示请求成功且终态已在票据 current 时落下。
  /// - `isDisposed || current().status == submitting` → 直接返回 false；
  /// - `slot.begin(key: key)`，`set(submitting)`；
  /// - 成功且票据 current：`onSuccess == null` → `set(succeeded)`；否则 `next = await onSuccess(result, ticket)`，
  ///   再查一次 `ticket.isCurrent`，`next != null` 时 `set(next)`；`next == null` 表示回调已自行处理终态（或有意不改）；
  /// - 抛错且票据 current：`set(ActionState.fromError(error))`，再 `onFailure?.call(error)`；
  /// - `finally { always?.call(ticket); ticket.end(); }`。
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
  });

  /// 基类实现：`if (isDisposed) return; 置位; for (slot in slots) slot.close(); super.dispose();`
  @override
  void dispose();
}
```

## 4. 规则手册（rulebook · 两个 agent 可能答得不一样的地方都在这里）

| # | 规则 |
|---|---|
| R1 | 控制器改为 `final class X extends RequestNotifier`；删 `bool _disposed`，所有 `_disposed` 读取改 `isDisposed`；删私有 `_publish`，改用基类 `publish`；`_setX(next) => publish(() => _x = next)` 这类一行 setter **保留**（它们是可读性锚点，也让 diff 最小） |
| R2 | 手写 `if (_disposed) return; _x = next; notifyListeners();` 三行改为 `publish(() => _x = next)`；裸 `notifyListeners()`（如 `_loadOverviewFor`）保持原样，不强改 |
| R3 | 删 `dispose()` 覆写，改为 `@override List<RequestSlot> get slots => <RequestSlot>[...]`，顺序与原 `dispose()` 里的 close 顺序**逐字一致**。需要额外收尾的三处：logs `dispose()` 覆写为 `{ if (isDisposed) return; stopWatching(); super.dispose(); }`；automation / device_list 覆写为 `{ super.dispose(); _writes.clear(); }`（`_overviewReads` 同理），且 `slots` 用 `[_read, ..._writes.values]` 并入动态槽 |
| R4 | 只把第 5 节表里标「迁」的调用点改为 `runQuery` / `runAction`；标「留」的一律保持内联，只做 R1/R2 替换。不得自作主张多迁一处或少迁一处 |
| R5 | 迁移前置守卫（`profile.active`、`resolved == null`、`loader == null`、`contact == null`、`text.isEmpty` 等业务条件）留在调用方原位置；`isDisposed` / `submitting` 守卫由 runner 负责，调用方可保留原守卫（重复但无害）也可删，**但业务条件不得搬进 runner** |
| R6 | `fetch` / `request` 闭包内只做原 `try` 块里「await 之前 + await 本身 + 纯数据整形（排序 / 包装）」；任何写字段、通知、二次请求都放 `onData` / `onSuccess` |
| R7 | `onSuccess` 的返回约定：原代码在成功路径末尾是单一 `set(succeeded)` → 回调返回 `const ActionState.succeeded()`；原代码成功路径里自己 `set` 了多种状态或在 `set` 之后还有 `await` → 回调内部原样复现整段（含 `set`），返回 `null` |
| R8 | 通知顺序守恒：回调内语句顺序与原 `try` 块顺序逐字一致；不得把 `_setNotice` 之类带通知的调用挪到 `always` 或 runner 外 |
| R9 | 静默字段赋值（如 `_lastSendResult = null`、`_actionSources[id] = source`）若原本位于 `begin()` 与 `set(submitting)` 之间，允许前移到 `runAction(...)` 调用之前；跨 `await` 或跨通知的不得移动 |
| R10 | `QueryState` 的 key 一律用 `slot.key`（runner 内部已如此）；原代码用的静态常量与 slot key 同值，删常量前先确认它没有其它引用 |
| R11 | 既有 `test/**` 一字不动；断言、期望值、用例数不变。任何「测试需要改才能过」都是实现错误或规格漏洞，标 `BLOCKED` 回报，不改测试 |
| R12 | 只改自己「所有权清单」内的文件。发现必须改清单外文件（含 `request_notifier.dart`）才能完成 → 停下，标 `BLOCKED` 并说明，不越权 |
| R13 | 每次编辑后 `dart format <改过的文件>`；提交报告前 `flutter analyze --no-pub` 必须 0 issues（`strict-inference` 下闭包参数类型推不出来时显式写 `<T>` 或参数类型） |
| R14 | 子代理只跑自己主题的测试目录（`flutter test --no-pub test/features/<feature>/state/`），不跑全量；全量由主 Agent 串行跑（唯一 build daemon） |
| R15 | 删 `import 'package:flutter/foundation.dart'` 前先确认文件内不再用 `ChangeNotifier` / `VoidCallback` / `@protected` 之外的符号；`directives_ordering` 下新 import 按字典序插入（`request_notifier.dart` 排在 `query_state.dart` 之后、`state_failure.dart` 之前） |
| R16 | 不新增任何叙述「本次改了什么」的注释；原有文档注释随代码搬移；LF 行尾、UTF-8 无 BOM |
| R17 | **多个占位参数一律写 `(_, _)`**（Dart 3.12 通配符）；写 `(_, __)` 会触发 `unnecessary_underscores` lint（试点批 P-2 实测） |

## 5. 逐调用点映射（细颗粒 · 每一处都有裁决）

「迁」= 改为 runner；「留」= 保持内联，仅做 R1/R2；括号里是 runner 参数映射。

### esim_controller.dart（子代理 A · 风险中）

| 位置 | 裁决 | 映射 |
|---|---|---|
| `_readHardware` | 迁 runQuery | 前置守卫 `loader == null` 留；`slot: _hardwareRead, current: () => _hardware, set: _setHardware, fetch: (t) async => (await loader(deviceId, cancellation: t.cancellation)).hardware, isEmpty: (r) => r.isEmpty` |
| `switchProfile` | 迁 runAction | 前置守卫 `profile.active` 留；`slot: _switch, current: () => _switchAction, set: _setSwitch, request: (t) => _repository.switchProfile(deviceId, profile.target, cancellation: t.cancellation), onSuccess: (result, _) async { if (!result.verified) return null; await _readInventory(refresh: false); return const ActionState.succeeded(); }` |
| `savePolicy` | 迁 runAction | 前置守卫 `resolved == null` 留；`slot: _policySave, current: () => _policyAction, set: _setPolicyAction, request: (t) => _repository.savePolicy(resolved, ..., cancellation: t.cancellation), onSuccess: (saved, _) { _setPolicy(QueryState<CardPolicy>.data(data: saved, key: _policyRead.key)); return const ActionState.succeeded(); }` |
| `peekPolicy` | 留 | 返回值语义特殊（null / rethrow） |
| `_mutateProfile` | 迁 runAction | `slot: _mutate, current: () => _mutateAction, set: _setMutate, request: (t) => body(t.cancellation), onSuccess: (_, _) async { await _readInventory(refresh: false); return const ActionState.succeeded(); }` |
| `download` / `cancelDownload` | 留 | 进度回调 + 两种失败分支 |
| `_loadPolicy` | 迁 runQuery | 前置守卫 `target == null` 留；`slot: _policyRead, current: () => _policy, set: _setPolicy, fetch: (t) => _repository.fetchPolicy(target, cancellation: t.cancellation)` |
| `_readInventory` | 迁 runQuery | `slot: _read, current: () => _inventory, set: _setInventory, fetch: (t) => _repository.fetchProfiles(deviceId, refresh: refresh, cancellation: t.cancellation), isEmpty: (r) => r.profiles.isEmpty && r.hint == EsimInventoryHint.none, onData: (_, _) => _loadPolicy()` |
| `slots` | — | `[_read, _hardwareRead, _switch, _policyRead, _policySave, _policyPeek, _download, _mutate]` |

### sms_controller.dart（子代理 B · 风险中）

| 位置 | 裁决 | 映射 |
|---|---|---|
| `loadContacts` | 迁 runQuery | `slot: _contactsRead, current: () => _contacts, set: _setContacts, fetch: (t) async { final result = await _repository.fetchContacts(cancellation: t.cancellation); final contacts = List<SmsContact>.of(result)..sort(<原比较器>); return List<SmsContact>.unmodifiable(contacts); }, isEmpty: (c) => c.isEmpty` |
| `selectContact` / `loadEarlier` | 留 | 无请求线；`_disposed` → `isDisposed` |
| `sendMessage` | 迁 runAction | 前置守卫留；`_lastSendResult = null;` 按 R9 前移到 runAction 之前；`slot: _send, current: () => _sendAction, set: _setSendAction, request: (t) => _repository.sendMessage(contact.target, text, cancellation: t.cancellation), onSuccess: (result, _) async { _lastSendResult = result; if (result.outcome == SmsSendOutcome.failed) return ActionState.failed(unknownOutcome: const StateFailure(StateFailureKind.unknownOutcome)); _setSendAction(const ActionState.succeeded()); await _readThread(contact, cursor: null, prepend: false); return null; }` |
| `deleteSelectedThread` | 迁 runAction | `slot: _delete, current: () => _deleteAction, set: _setDeleteAction, request: (t) => _repository.deleteThread(contact.target, cancellation: t.cancellation), onSuccess: (_, _) async { _selectedContact = null; _thread = const QueryState<SmsThread>.initial(key: _threadKey); _setDeleteAction(const ActionState.succeeded()); await loadContacts(); return null; }` |
| `_readThread` | 留 | `previous` 取值依赖 `prepend`，且有 `stillWanted` 双重谓词 |
| `slots` | — | `[_contactsRead, _threadRead, _send, _delete]` |

### settings_controller.dart（子代理 C · 风险中）

| 位置 | 裁决 | 映射 |
|---|---|---|
| `load` | 留 | 五路并发 + `_ignore` + 条件二次读取 + 通知文案 |
| `_runAction<T>` 私有包装 | 迁 → 变成对基类的**薄包装**，参数表不变 | `runAction<T>(slot: slot, current: current, set: set, request: request, onSuccess: (result, _) { onSuccess?.call(result); set(const ActionState.succeeded()); _setNotice(okNotice(result)); afterNotice?.call(result); return null; }, onFailure: (_) => _setNotice(failNotice, error: true), always: always)`；10 个调用点**一字不改** |
| `checkBoardVersion` | 留 | 无请求线 |
| `_ignore` / `_replace` / `_setNotice` / 各 `_setX` | 留 | `_setX => publish(...)`；`_setNotice` 内部 `if (_disposed) return; ...; notifyListeners()` 改为 `publish(() { _notice = text; _noticeError = error; })` |
| `slots` | — | `[_read, _language, _notify, _test, _password, _security, _https, _quota, _update, _apply, _license]` |

### devices/state（子代理 D · 风险中）

| 位置 | 裁决 | 映射 |
|---|---|---|
| list `_request` | 迁 runQuery | `slot: _read, current: () => _state, set: _setState, fetch: (t) => _repository.fetchDevices(cancellation: t.cancellation), isEmpty: (fleet) => fleet.devices.isEmpty, onData: (fleet, ticket) => _loadOverviews(fleet, ticket)` |
| list `_loadOverviews` / `_loadOverviewFor` | 留 | 动态槽 + 双票据判定；裸 `notifyListeners()` 按 R2 保留 |
| list `slots` / `dispose` | — | `slots => [_read, ..._overviewReads.values]`；`dispose() { super.dispose(); _overviewReads.clear(); }` |
| detail `_request({silent})` | 迁 runQuery | `slot: _read, current: () => _state, set: _setState, fetch: (t) => _repository.fetchDeviceOverview(deviceId, cancellation: t.cancellation), silent: silent` |
| detail `_runAction(key, body, {onAccepted})` | 迁 → 薄包装 | `final ok = await runAction<void>(slot: _actionRun, key: key, current: () => _action, set: _setAction, submitting: ActionState.submitting(operationId: key), request: (t) => body(t.cancellation), onSuccess: (_, _) { onAccepted?.call(); return const ActionState.succeeded(); }); if (ok) await _request();` 三个公开方法调用点不改 |
| detail `_applyCapability` | 留 | 纯状态整形 |
| detail `slots` | — | `[_read, _actionRun]` |

### automation / overview / session（子代理 E · 风险低）

| 位置 | 裁决 | 映射 |
|---|---|---|
| automation `load` | 留 | 两段串行 await、中间有 isCurrent 早退，runner 无法逐字等价 |
| automation `_write<T>` | 迁 → 薄包装 | 守卫与 `putIfAbsent` 留；`_actionSources[task.id] = source;` 按 R9 前移；`runAction<T>(slot: slot, current: () => actionFor(task.id), set: (next) => _setAction(task.id, next), request: (t) => operation(t.cancellation), onSuccess: (result, _) { publish(() => onSuccess(result)); return null; })` |
| automation `_setWorkspace` / `_setAction` | R2 | `publish(() => ...)` |
| automation `slots` / `dispose` | — | `slots => [_read, ..._writes.values]`；`dispose() { super.dispose(); _writes.clear(); }` |
| overview `_request` | 留 | 双路 `_capture` 合并，非标准查询 |
| overview `_setState` | R2 | `publish` |
| overview `slots` | — | `[_read]`；删 `dispose()` 覆写 |
| session 全部方法 | 留 | 会话状态机不是 Query/Action；只做 R1/R2 |
| session `slots` | — | `[_restore]`；删 `dispose()` 覆写 |

### logs_controller.dart（试点 · 主 Agent · 已完成）

| 位置 | 裁决 | 映射 |
|---|---|---|
| `_fetch` | 迁 runQuery | `slot: _read, current: () => _entries, set: (next) { if (next.status == QueryStatus.failed) stopWatching(); _setEntries(next); }, fetch: (t) => repository.fetchHistory(level: _level, search: _search, cancellation: t.cancellation), isEmpty: (logs) => logs.isEmpty`（G3） |
| `slots` / `dispose` | — | `[_read]`；`dispose() { if (isDisposed) return; stopWatching(); super.dispose(); }` |

## 6. gap inventory（默认规则盖不住、要单独处理的点）

| # | 硬点 | 处理 |
|---|---|---|
| G1 | 4 处查询、2 处动作因多段 await / 双谓词 / 自定义失败分支无法逐字等价（settings.load、overview._request、automation.load、sms._readThread、esim.download、esim.peekPolicy） | 一律「留」，只做 R1/R2；不为它们扩 API |
| G2 | `esim.switchProfile` 在 `!result.verified` 时**不落任何终态**（动作停留在 submitting） | 这是现状行为，按 R7 回调返回 `null` 原样保留；记入 `OBSERVATIONS.md` 供产品侧判断，本轮不改 |
| G3 | `logs._fetch` 失败时先 `stopWatching()` 再落 failed 状态；runQuery 无「失败前」钩子 | 用 `set` 拦截：`if (next.status == failed) stopWatching()`。等价性依据：`stopWatching` 不通知；runQuery 只会用 pending/data/empty/failed 四种状态调 `set`；无监听者在通知回调里同步调 `start/stopWatching`（§0 已核实） |
| G4 | `settings._runAction` 失败路径在 `set(fromError)` 之后还要 `_setNotice(fail)`（第二次通知） | runAction 的 `onFailure` 在 `set` 之后触发，顺序守恒 |
| G5 | `device_detail._runAction` 成功后在 `finally` **之后**再 `_request()` | 用 runAction 的 `bool` 返回值：`if (ok) await _request();`；`ticket.end()` 与 `_request()` 的先后与原代码相同 |
| G6 | automation / device_list 的动态槽 map 在 dispose 时要 close + clear | R3：`slots` 用展开并入，`dispose()` 覆写只做 `super.dispose(); map.clear();` |
| G7 | 三个控制器的 `dispose()` 关槽顺序略有差异（logs 先停表，automation / list 固定槽先于动态槽） | R3 已逐一钉死顺序 |
| G8 | `strict-inference` 下 `runQuery(...)` 的 `T` 由 `current` 推断；`runAction<void>` 场景 `request` 返回 `Future<void>` 时 `onSuccess` 参数写 `(_, _)` | R13 / R17 |

## 7. 裁判与工具证据

| 项 | 值 |
|---|---|
| 工具链 | Flutter 3.44.9 stable（engine b9499e4c）、Dart 3.12.2 windows_x64、Git 2.54.0 |
| 裁判 1 | `dart format --output=none --set-exit-if-changed lib test` → 基线 `Formatted 189 files (0 changed)` |
| 裁判 2 | `flutter analyze --no-pub` → 基线 `No issues found!` |
| 裁判 3 | `flutter test --no-pub --reporter compact` → 基线 `+559: All tests passed!` |
| 裁判 4 | 8 套 `*_lifecycle_test.dart`（含在裁判 3 内）—— 通知计数 / 调用序列 / dispose 静默 |
| 裁判 5 | 新 `test/core/state/request_notifier_test.dart`（试点批先 RED 后 GREEN，25 用例） |
| 裁判 6 | 判据 4–7 的 grep 复扫（主 Agent） |
| 基线快照 | `.xj-cursor/refactor-r9/BASELINE_HASHES.tsv`（189 个 dart 文件 SHA256） |
| 裁判自检 | 第八轮已验证过「故意弄坏 → 红」；本轮试点批新增测试亦先 RED（import 不存在）后 GREEN |

## 8. 任务拆分（细颗粒度）

风险分档：低 = 只做 R1/R2/R3；中 = 含 runner 迁移。

### P · 试点批（主 Agent 亲自做，先于派发；兼作压力测试试航）

| 步骤 | 内容 | 完成判据 |
|---|---|---|
| P-1 | 新建 `test/core/state/request_notifier_test.dart`：用一个最小子类覆盖 —— publish 在 dispose 后静默；dispose 关闭所有 slots；二次 dispose 不通知；runQuery 的 pending→data / empty / failedAfter(previous, isStale) / 票据被顶替不写 / silent 不发 pending 不落 failed / onData 收到 value 与 ticket；runAction 的 submitting 守卫 / 默认 succeeded / onSuccess 返回 null 不写 / 返回自定义状态 / fromError + onFailure 顺序 / 票据失效返回 false / always 被调 / 自定义 key 与 submitting | 文件存在；因 import 不存在而 RED |
| P-2 | 新建 `lib/core/state/request_notifier.dart`，按第 3 节签名实现 | `flutter test --no-pub test/core/state/` GREEN |
| P-3 | 按第 5 节 logs 表迁 `logs_controller.dart` | `flutter test --no-pub test/features/logs/` 绿 |
| P-4 | 全量三裁判 | 全绿；用例数 > 559 |
| P-5 | 记 `WAVE_HASHES_BEFORE.tsv`；若 P-3 暴露规则漏洞，先修第 4–6 节再派发 | — |

### A–E · 并行派发（5 个子代理 · 模型 `claude-fable-5-1`）

每个子代理只拿：本计划书路径 + 自己的所有权清单 + 第 3/4/5/6 节。步骤统一：

| 步骤 | 内容 |
|---|---|
| X-1 | `Read` 本计划书第 3–6 节与 `lib/core/state/request_notifier.dart`（只读，不改）；可参考已迁完的 `lib/features/logs/state/logs_controller.dart` 作为样例 |
| X-2 | `Read` 自己所有权内的控制器与对应 `test/features/<x>/state/` 全部测试（只读，理解裁判在测什么） |
| X-3 | 按第 5 节自己那张表逐行改：先 R1（继承 + isDisposed + publish + slots），跑一次主题测试确认绿；再逐个「迁」调用点，每迁一处跑一次主题测试 |
| X-4 | R15 清理 import；`dart format <改过的文件>`；`flutter analyze --no-pub` 0 issues；`flutter test --no-pub test/features/<x>/state/` 全绿 |
| X-5 | 回报：改动文件清单、每个「迁」点的一句话等价性说明、analyze/test 输出末行、与第 5 节的任何偏离、`BLOCKED` 项 |

所有权：

| 子代理 | 所有权（只允许写这些） | 禁止 |
|---|---|---|
| A | `lib/features/esim/state/esim_controller.dart` | 其它一切；`test/**` |
| B | `lib/features/sms/state/sms_controller.dart` | 同上 |
| C | `lib/features/settings/state/settings_controller.dart` | 同上 |
| D | `lib/features/devices/state/device_list_controller.dart`、`device_detail_controller.dart` | 同上 |
| E | `lib/features/automation/state/automation_controller.dart`、`lib/features/overview/state/overview_controller.dart`、`lib/features/auth/state/session_controller.dart` | 同上 |

## 9. 派发与验证协议

1. **顺序**：P 试点（主 Agent）→ 全量三裁判绿 → 记 `WAVE_HASHES_BEFORE.tsv` → **并行**派 A–E → 回收。
2. **漂移检查（回收后第一件事，无论子代理报成功还是报错）**：全库哈希对比 `WAVE_HASHES_BEFORE.tsv`；任何改动落在非本主题所有权的文件 → `git checkout -- <file>` 还原并记 `OBSERVATIONS.md`；子代理报错但文件已改 → 逐文件 diff 判断是接管续做还是还原。
3. **验证环**：主 Agent 串行跑三裁判 + 判据 4–7 grep 复扫；失败 → 定位主题 → 规则漏洞则修第 4–6 节并让该主题重做；实现错误则主 Agent 直接修。
4. **漂移自审五问**（回收后一次）：还在 SCOPE 内？行为等价（通知次数 / 调用序列）？替代测试（去掉这处改动任务是否仍失败）？有没有幻觉改动？有没有滚雪球（比如顺手改了 data 层）？
5. **账本**：每个主题的 PASS 记 `VERIFY_LEDGER.tsv`（主题、文件、命令、退出码、日志路径、时间）。
6. **回滚**：本轮不 commit；任何文件回滚 = `git checkout -- <file>`；新文件回滚 = 删除。整轮放弃 = `git checkout -- lib test && git clean -fd lib/core/state test/core/state docs/refactor`（需用户授权才执行）。
7. **平台限制预案**：若子代理因账号并发 / 命名模型限制被中断，先做第 2 条漂移检查，文件已改完的按「主 Agent 接管验证」处理，未改的由主 Agent 串行补做，不虚构协作。

## 10. 需要用户拍板的事项（默认值已选，可否决）

| # | 事项 | 默认 |
|---|---|---|
| D1 | 基类命名 `RequestNotifier`、落位 `lib/core/state/` | **采用**（与 `RequestSlot` / `RequestRegistry` 同一语汇族；状态层归 `core/state`） |
| D2 | `esim.switchProfile` 未验证成功时动作停留 submitting 的现状 | **保留**（结构保持型；记 `OBSERVATIONS.md`） |
| D3 | 数据层 dto 私有助手去重 | **不做**（收益低；记为下一轮候选） |
| D4 | 本轮结束是否 commit | **不 commit**，留给用户；建议信息：`refactor: hoist controller lifecycle and request boilerplate into RequestNotifier` |

## 11. 执行记录（随进度追加）

- 2026-09-08 · 侦察 + 基线：format 189/0 · analyze 0 · test 559/559；18 个「M」确认为行尾假阳性；`BASELINE_COMMIT` / `BASELINE_STATUS.txt` / `BASELINE_HASHES.tsv` 落盘。
- 2026-09-08 · 规格冻结（本文件 §1–9）。
- 2026-09-08 · P-1 新测试 RED（import 不存在）→ P-2 基类落地 GREEN 25/25 → P-3 `LogsController` 迁移，`test/features/logs/` 26/26 绿。试航暴露一条规则漏洞：`(_, __)` 触发 `unnecessary_underscores`，已增补 R17 并修正本文件与测试；顺带发现 PowerShell 5 `Get-Content/Set-Content` 会破坏 UTF-8 中文并写入 BOM，改用编辑器工具重写（R16 无 BOM 已复核）。
- 2026-09-08 · P-4 全量：analyze 0 · test **584/584**（559 + 25）。P-5 `WAVE_HASHES_BEFORE.tsv`（191 文件）落盘；`VERIFY_LEDGER.tsv` 记 P 行。
- 2026-09-08 · Wave 派发：A（esim）/ B（sms）/ C（settings）/ D（devices ×2）/ E（automation + overview + session）→ 5 个子代理并行，模型 `claude-fable-5-1`，每个只拿本计划书路径 + 自己的所有权清单。

### 11.1 Wave 回收时间线

| 步骤 | 执行者 | 结果 |
|---|---|---|
| A esim | 子代理（`claude-fable-5-1`） | 6 处迁移全部落地；analyze 0；`test/features/esim/state/` 28/28；无 BLOCKED、无偏离 |
| B sms | 子代理 | 3 处迁移；analyze 0；`sms/state` 16/16；无 BLOCKED；附观察 O2 |
| C settings | 子代理 | `_runAction` 薄包装，10 个调用点一字不改；analyze 0；`settings/state` 100/100；无 BLOCKED |
| D devices | 子代理 | 3 处迁移（list._request、detail._request、detail._runAction）；analyze 0；`devices/state` 37/37；无 BLOCKED；附观察 O3 |
| E automation / overview / session | 子代理 | `_write` 薄包装 + 三文件 R1/R2/R3；analyze 0；三目录 92/92；无 BLOCKED |
| 漂移检查 | 主 Agent | 对比 `WAVE_HASHES_BEFORE.tsv`：恰好 8 个所有权文件变化、0 新文件、`test/**` 内容与 HEAD 一致；**DRIFT_COUNT = 0** |
| 全量三裁判 | 主 Agent（唯一 build daemon） | format 191/0 · analyze 0 · test **584/584** |
| 判据 4–8 复扫 | 主 Agent | 全部满足（见 11.2） |
| 逐字审查 | 主 Agent | 9 个控制器 diff 与第 5 节映射逐行对应；无幻觉改动、无范围外改动 |
| 平台限制 | — | 本轮 5 个子代理均正常结束（`turn_ended: success`），未触发第 9 节第 7 条预案 |

### 11.2 成功判据逐条核对

| # | 判据 | 结果 |
|---|---|---|
| 1 | `dart format` 退出 0 | ✅ 191 files / 0 changed |
| 2 | `flutter analyze` 0 issues | ✅ |
| 3 | 测试全绿且 ≥ 559，既有断言不改 | ✅ 584/584（559 + 25 新增）；`git diff --numstat -- test` 为空 |
| 4 | state 目录无 `bool _disposed` / `void _publish(`；`dispose()` 覆写仅 3 处 | ✅ grep 为空；覆写仅在 logs / automation / device_list |
| 5 | `QueryState.pending(previous` 仅在基类 + 4 处保留内联 | ✅ 基类 1 + settings.load / overview._request / automation.load / sms._readThread |
| 6 | `ActionState.fromError(error)` 仅在基类 + esim.download | ✅ |
| 7 | 9 个控制器 `extends RequestNotifier`；foundation import 只剩必要处 | ✅ 仅 `device_detail_controller.dart` 保留（用到 `VoidCallback`） |
| 8 | `git status` 只列有意改动；无新增 `w/crlf` | ✅ 9 M（控制器）+ 3 新文件（基类、测试、本计划书）；行尾噪声文件未被触碰 |

### 11.3 与规格的偏离

无。子代理均按 `strict-inference` 显式写了 runner 的类型参数（R13 允许）。三条「理论上可观察但仓内不存在触发路径」的微差异记入状态根 `OBSERVATIONS.md`（O1–O3），均为冻结 API 的固有语义而非实现偏离。

### 11.4 变更清单

新建（3）：`lib/core/state/request_notifier.dart`（138 行）、`test/core/state/request_notifier_test.dart`（25 用例）、本计划书。

修改（9）：`lib/features/{auth,automation,devices×2,esim,logs,overview,settings,sms}/state/*_controller.dart`。

净变化：`git diff --numstat -- lib` 9 个已跟踪文件 **+308 / −556**；`lib/` 总行数 17075 → 16937（含新增基类 138 行，即控制器净减约 250 行）。

### 11.5 未提交 · 建议

按 D4 未 commit。建议信息：`refactor: hoist controller lifecycle and request boilerplate into RequestNotifier`。回滚：`git checkout -- lib/features && Remove-Item lib/core/state/request_notifier.dart, test/core/state/request_notifier_test.dart`（需用户授权）。范围外候选见状态根 `OBSERVATIONS.md`（O4 数据层 dto 助手去重、O5 PowerShell 编码坑）。
