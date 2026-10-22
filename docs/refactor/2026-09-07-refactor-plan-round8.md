# 2026-09-07 · 第八轮重构计划书（细颗粒度）

> 状态：**规格已冻结**（第 1–5 节执行期不得改软）。执行记录见第 9 节。
> 状态根：`.xj-cursor/refactor-r8/`（gitignored；基线、哈希、账本、交接都在那里）。
> 基线提交：`fb2e0fbf518fa5fb2b33551540d8c1b76e3e5360`（`main`，领先 `origin/main` 2 个提交）。

## 0. 侦察结论（有证据，非拍脑袋）

| 事实 | 证据 |
|---|---|
| 工作区**内容**干净：21 个「M」全是行尾差异 | `git diff --numstat` 为空；`git ls-files --eol` 显示这些文件 `i/lf w/crlf`；`core.autocrlf=true`，仓库无 `.gitattributes` |
| 索引 205 个文本文件全部 LF；工作区 113 LF / 92 CRLF | `git ls-files --eol` 分组统计 |
| 裁判强：`dart format` 178/0、`flutter analyze` 0 issues、`flutter test` **556/556**（24 s） | `.xj-cursor/refactor-r8/baseline/{format,analyze,test}.log` |
| 第七轮已收口：无 TODO/ignore/print，控制器全部走 `RequestSlot`，仓储全部走 `guardShape` | 全库 grep |
| 上一轮明确留下的唯一工程遗留：「启用 git 时一并归一换行符」 | 第七轮交接结论 |
| 表现层拆分惯例已确立但只落了一半：`esim/settings/sms` 有 `presentation/widgets/`，`automation/overview/auth` 没有 | 目录树 |
| 三份几乎相同的本地时间格式化函数 | `automation_screen._time`、`sms_message_bubble._time`、`logs_screen._format` |
| 设计层存在整文件级死代码与多处无人引用的公开符号 | 全库「公开符号在其它文件零引用」扫描 + 逐项人工核实 |

可行性裁决：**GO**。理由：结构保持型重构；裁判就位且强；改动面约 25 个源文件、7 个新文件；无外部消费者（独立 App）。

## 1. 迁移目标与范围

**目标（一句话）**：在不改变任何外部可见行为的前提下，把表现层拆分惯例补齐到全部功能片、合并重复的时间格式化、清掉设计层死代码、归一换行符。类型：**结构保持型**。

### IN SCOPE（工作项全集，也是漂移检查白名单）

| 主题 | 文件 |
|---|---|
| B · 时间格式化 | 新 `lib/core/format/local_time_text.dart`、新 `test/core/format/local_time_text_test.dart`；改 `lib/features/automation/presentation/automation_screen.dart`、`lib/features/sms/presentation/widgets/sms_message_bubble.dart`、`lib/features/logs/presentation/logs_screen.dart` |
| S1 · automation 表现层 | `lib/features/automation/presentation/automation_screen.dart`；新 `lib/features/automation/presentation/widgets/automation_task_card.dart`、`automation_run_card.dart`、`automation_action_status.dart`、`automation_labels.dart` |
| S2 · overview 表现层 | `lib/features/overview/presentation/overview_screen.dart`；新 `lib/features/overview/presentation/widgets/*.dart`（按第 3 节规则拆） |
| S3 · sms 表现层 | `lib/features/sms/presentation/sms_screen.dart`；新 `lib/features/sms/presentation/widgets/sms_composer.dart` |
| S4 · 设计层死代码 | `lib/design/one/glass.dart`、`glass_select.dart`（删）、`glass_chrome.dart`、`glass_overlays.dart`；`lib/design/tokens/one_tokens.dart`；`lib/design/widgets/glass_action.dart`、`soft_label.dart` |
| S5 · auth 表现层 | `lib/features/auth/presentation/login_screen.dart`；新 `lib/features/auth/presentation/widgets/login_form.dart` |
| S6 · 换行归一 | 新 `.gitattributes`；工作区内 92 个 CRLF 文本文件改写为 LF（内容不变） |
| 测试 | 各主题对应的既有测试文件**只允许改 import 路径**；可新增测试文件 |

### OUT OF SCOPE（不许碰）

- `pubspec.yaml` / `pubspec.lock` / `analysis_options.yaml` / `.gitignore` / `android/**` / `assets/**`
- `lib/core/http/**`、`lib/core/state/**`、所有 `state/`、`data/`、`domain/` 目录（本轮不动状态与数据层）
- `lib/design/one/liquid_glass.dart`、`ultra_glass_dock.dart`、`one_status_hero.dart`、`glass_surface.dart`、`dot_matrix_face.dart`、`one_palette.dart`
- `lib/features/devices/**`（`part` 拆分是第七轮的明确决策，不重排）
- `lib/features/settings/presentation/**`（已拆好；`settings_screen` 424 行是装配层）
- `lib/features/esim/presentation/**`（第七轮刚收口）
- 任何用户可见文案、颜色、间距、语义标签
- git 写操作：**不 commit、不 push、不 stash、不 reset**

### 依赖锁定

不允许新增或升级任何依赖。`DEPENDENCY_ALLOWLIST` 为空。

## 2. 成功判据与行为契约

**成功判据（全部满足才算完成）**

1. `dart format --output=none --set-exit-if-changed lib test` 退出 0
2. `flutter analyze --no-pub` 0 issues
3. `flutter test --no-pub` 全绿，用例数 ≥ 556（只增不减；既有断言一字不改）
4. `test/design/design_boundary_test.dart` 通过（业务代码仍不直引 `design/one`）
5. 设计层复扫：S4 涉及文件中不再有「其它文件零引用」的公开符号（`GlassBackdrop`、`glassDockScrollPadding` 除外，它们有引用）
6. 四个页面文件（automation / overview / sms / login）不再含 ≥ 40 行的私有 `Widget _xxx()` 构建函数；抽出的组件位于各自 `presentation/widgets/`
7. `lib/` 内 `padLeft(2, '0')` 仅出现在 `lib/core/format/local_time_text.dart`
8. S6 之后 `git status --porcelain` 只列出本轮有意改动的文件；`git ls-files --eol` 无 `w/crlf`（`*.bat` 除外）

**行为契约（必须保持）**

- 所有文案、图标、`Key`、`Semantics` 标签、布局顺序、间距常量与迁移前逐字相同
- 所有回调语义相同：busy 时禁用、确认弹窗仍由页面 State 负责
- 时间显示：分钟精度 `yyyy-MM-dd HH:mm`、秒精度 `yyyy-MM-dd HH:mm:ss`、`toLocal()`、null 回退文案保留在调用点

**有意的改进（单独声明）**：无。本轮零功能变更。

## 3. 规则手册（rulebook · 两个 agent 可能答得不一样的地方都在这里）

| # | 规则 |
|---|---|
| R1 | 新组件文件名 `snake_case`，带功能前缀：`automation_task_card.dart`；类名 `PascalCase` 同前缀：`AutomationTaskCard`（对齐 `SettingsAccessForm`、`SmsContactButton`） |
| R2 | 一个文件一个公开组件；只被该组件使用的辅助 widget 留在同文件里做私有类 |
| R3 | 抽出的组件一律 `final class X extends StatelessWidget`，`const` 构造，命名参数 `required`，`super.key` 放最后 |
| R4 | 叶子组件**不接收** `ChangeNotifier` 控制器；接收数据 + 回调（`ActionState`、`VoidCallback?`、`ValueChanged<T>?`）。`TextEditingController` 可以传（settings 先例） |
| R5 | 测试用的静态 `Key` 留在页面类上（如 `SmsScreen.messageFieldKey`），通过构造参数传给子组件（settings 先例：`languageZhKey: SettingsScreen.languageZhKey`）；不得让 widgets 反向 import 页面文件 |
| R6 | 弹窗（`showOneGlassDialog`）与 `setState` 留在页面 State；组件只发回调 |
| R7 | 相对 import（`'../../../design/...'`），遵守 `directives_ordering`；删掉不再用的 import |
| R8 | 时间格式化只用 `formatLocalMinute(DateTime)` / `formatLocalSecond(DateTime)`；null 回退文案（`'—'`、`'时间不可用'`）留在调用点，逐字不改 |
| R9 | 删死代码：整段删除，不注释掉；删后复扫本文件内其它公开符号是否因此变为零引用（级联），是则一并删；被 `test/` 引用的一律不删 |
| R10 | 删除会导致文档注释里的 `[Symbol]` 引用悬空时，把该处注释改为普通文字或删除该句，不留悬空引用 |
| R11 | 既有测试只允许改 import 路径；断言、期望值、用例数一字不动。需要新测试就新建文件 |
| R12 | 只改自己「所有权清单」内的文件。发现必须改清单外文件才能完成 → 停下，标 `BLOCKED` 并说明，不越权 |
| R13 | 每次编辑后 `dart format <改过的文件>`；提交报告前 `flutter analyze --no-pub` 必须 0 issues |
| R14 | 子代理只跑自己主题的测试文件（`flutter test --no-pub test/features/<feature>/...`），不跑全量；全量由主 Agent 串行跑（唯一 build daemon） |
| R15 | 新文件使用 LF 行尾、UTF-8 无 BOM；不新增任何注释来叙述「本次改了什么」 |
| R16 | 抽出组件时把原有文档注释一并搬走；不新增无信息量注释 |

## 4. gap inventory（默认规则盖不住、要单独处理的点）

| # | 硬点 | 处理 |
|---|---|---|
| G1 | `login_screen` 表单绑定 `_formKey`、4 个 `TextEditingController`、4 个 `FocusNode`、`_https` 开关、`_submit`，并在 `onChanged` 里 `setState` 以重算 `previewOrigin`/`publicHttp` | `LoginForm` 接收全部控制器/焦点/布尔值 + `onChanged: VoidCallback` + `onSubmit`；`previewOrigin`/`publicHttp` 的计算随表单搬进 `LoginForm.build`（纯函数，行为不变）；静态 Key 按 R5 传参 |
| G2 | `glass.dart` 第 126 行注释引用 `[GlassBar]`，而 `GlassBar` 仅被 `GlassSliverAppBar` 使用 | 删 `GlassSliverAppBar` → `GlassBar` 级联删除 → 按 R10 改注释 |
| G3 | `glass_overlays.dart`：`showGlassDialog` 零引用；`showGlassSheet`/`GlassSheet` 仅被 `glass_select.dart` 使用 | 删 `glass_select.dart` 后三者全部级联为零引用 → 删整文件 + `glass.dart` 中的 `export` |
| G4 | `test/design/one_design_test.dart` import 了 `liquid_glass.dart` 并断言 dock 不用 `LiquidGlass` | `LiquidGlass` 保留（R9） |
| G5 | `automation._taskCard` 内部调用 `widget.controller.actionFor(task.id)` 与三个确认弹窗 | `AutomationTaskCard(task:, action:, onToggle: ValueChanged<bool>?, onRun: VoidCallback?, onDelete: VoidCallback?)`；`actionFor` 与弹窗留在 State（R4/R6） |
| G6 | `overview._GaugeTile` 只被 `_UsagePanel` 用；`_SectionFailure` 可能被多处用 | 按 R2：前者作为私有类留在 `overview_usage_panel.dart`；后者若被 ≥ 2 处用则独立文件 |
| G7 | `sms._sendOutcome` 读 `widget.controller.lastSendResult` | `SmsComposer(controller: TextEditingController, action: ActionState, lastSendResult: SmsSendResult?, onChanged: VoidCallback, onSend: VoidCallback?, messageFieldKey: Key)` |
| G8 | `logs._format` 是秒精度、非空参数；另两处是分钟精度、可空参数 | 共享函数提供两个精度，参数非空；可空与回退留调用点（R8） |
| G9 | S6 改写 92 个文件的行尾会让 `git status` 短暂显示全部为改动 | 先加 `.gitattributes`（`* text=auto eol=lf`，`*.bat text eol=crlf`，字体/图片/jar/p12 `binary`），再改写；结束时用 `git status --porcelain` 与 `git diff --numstat` 双重核对内容零变化 |

## 5. 裁判与工具证据

| 项 | 值 |
|---|---|
| 工具链 | Flutter 3.44.9 stable（engine b9499e4c）、Dart 3.12.2 windows_x64（与 README 要求一致） |
| 裁判 1 | `dart format --output=none --set-exit-if-changed lib test` → 基线 `Formatted 178 files (0 changed)` |
| 裁判 2 | `flutter analyze --no-pub` → 基线 `No issues found!` |
| 裁判 3 | `flutter test --no-pub --reporter compact` → 基线 `+556: All tests passed!` |
| 裁判 4 | `test/design/design_boundary_test.dart`（设计层边界棘轮，已含在裁判 3 内） |
| 裁判 5 | 公开符号零引用复扫（PowerShell 脚本，见状态根 `scan_unreferenced.ps1`） |
| 基线快照 | `.xj-cursor/refactor-r8/BASELINE_HASHES.tsv`（178 个 dart 文件 SHA256） |
| 裁判自检 | 第七轮已验证过「故意弄坏 → 红」；本轮 B 试点新增 `local_time_text_test` 亦先 RED 后 GREEN |

## 6. 任务拆分（细颗粒度）

风险分档：低 = 纯搬移/删除；中 = 搬移且含状态绑定。

### B · 试点批（主 Agent 亲自做，先于派发；兼作压力测试试航）

| 步骤 | 内容 | 完成判据 |
|---|---|---|
| B-1 | 新建 `lib/core/format/local_time_text.dart`：`String formatLocalMinute(DateTime value)`、`String formatLocalSecond(DateTime value)`，内部 `toLocal()` + 两位补零 | 文件存在，`analyze` 0 |
| B-2 | 新建 `test/core/format/local_time_text_test.dart`：UTC 输入 → 本地字符串；跨日/补零；两种精度 | 先 RED（函数未建时）后 GREEN |
| B-3 | `automation_screen.dart`：删私有 `_time`，调用点改 `value == null ? '—' : formatLocalMinute(value)` | `automation_screen_test` 绿 |
| B-4 | `sms_message_bubble.dart`：同上，回退 `'时间不可用'` | `sms_screen_test` 绿 |
| B-5 | `logs_screen.dart`：删 `_format`，改 `formatLocalSecond` | `logs_screen_test` 绿 |
| B-6 | 全量三裁判 | 全绿；用例数 > 556 |

试航目的：验证 R7/R8/R13 在真实文件上无歧义；若发现规则漏洞，先修第 3 节再派发。

### S1 · automation 表现层（子代理 A · Fable 5.1 · 风险中）

| 步骤 | 内容 |
|---|---|
| S1-1 | 新建 `widgets/automation_labels.dart`：搬 `_taskType` → `automationTaskTypeLabel`、`_environment` → `automationEnvironmentLabel`、`_runStatus` → `automationRunStatus`（返回同样的 record） |
| S1-2 | 新建 `widgets/automation_action_status.dart`：`AutomationActionStatus(action:)`，`build` 返回原 `_actionContent` 的内容；原函数返回 `List<Widget>`，组件用 `Column(crossAxisAlignment: stretch)` 包同样的子节点，顶部 `SizedBox` 间距保持 |
| S1-3 | 新建 `widgets/automation_run_card.dart`：`AutomationRunCard(run:)`，搬 `_runCard` |
| S1-4 | 新建 `widgets/automation_task_card.dart`：`AutomationTaskCard(task:, action:, onToggle:, onRun:, onDelete:)`，搬 `_taskCard`；`busy` 由组件内 `action.status == submitting` 算 |
| S1-5 | `automation_screen.dart`：删四个搬走的函数与三个格式化函数，改为使用新组件；确认弹窗留在 State |
| S1-6 | `dart format` 改过的文件；`flutter analyze`；`flutter test --no-pub test/features/automation/` |

所有权：`lib/features/automation/presentation/**`、`test/features/automation/presentation/**`。

### S2 · overview 表现层（子代理 B · Fable 5.1 · 风险低）

| 步骤 | 内容 |
|---|---|
| S2-1 | 读 `overview_screen.dart`，列出 `_HostMetrics`、`_HostPanel`、`_UsagePanel`、`_GaugeTile`、`_SectionFailure` 各自的使用方 |
| S2-2 | 按 R2/G6 拆：`widgets/overview_host_metrics.dart`、`overview_host_panel.dart`、`overview_usage_panel.dart`（含私有 `_GaugeTile`）、`overview_section_failure.dart`（若被 ≥ 2 处使用） |
| S2-3 | 类名去下划线加 `Overview` 前缀；构造参数、字段、`build` 逐字搬 |
| S2-4 | `overview_screen.dart` 改 import 与引用；删掉搬走的类 |
| S2-5 | `dart format`；`flutter analyze`；`flutter test --no-pub test/features/overview/` |

所有权：`lib/features/overview/presentation/**`、`test/features/overview/presentation/**`。

### S3 · sms 表现层（子代理 C · Fable 5.1 · 风险中）

| 步骤 | 内容 |
|---|---|
| S3-1 | 新建 `widgets/sms_composer.dart`：`SmsComposer`（参数见 G7），`build` 返回原 `_composer` 的 `OwSection`；`_sendOutcome` 搬进同文件做私有函数或私有组件 |
| S3-2 | `sms_screen.dart`：删 `_composer`/`_sendOutcome`，改用 `SmsComposer(... onChanged: () => setState(() {}), onSend: _confirmSend, messageFieldKey: SmsScreen.messageFieldKey)` |
| S3-3 | `dart format`；`flutter analyze`；`flutter test --no-pub test/features/sms/` |

所有权：`lib/features/sms/presentation/sms_screen.dart`、`lib/features/sms/presentation/widgets/sms_composer.dart`（新）、`test/features/sms/presentation/**`。（`sms_message_bubble.dart` 已在试点批改完，S3 不动它。）

### S4 · 设计层死代码（子代理 D · Fable 5.1 · 风险低）

| 步骤 | 内容 |
|---|---|
| S4-1 | 删 `lib/design/one/glass_select.dart`；`glass.dart` 删 `export 'glass_select.dart';` |
| S4-2 | `glass_overlays.dart`：删 `showGlassDialog`；复扫 → `GlassSheet`/`showGlassSheet` 变零引用 → 删整文件；`glass.dart` 删对应 `export` |
| S4-3 | `glass_chrome.dart`：删 `GlassScaffold`、`glassBodyPadding`、`glassRefreshOffset`、`GlassSliverAppBar`；复扫 → `GlassBar` 零引用 → 删；保留 `GlassBackdrop`、`glassDockScrollPadding`；清理不再用的 import（`services.dart`、可能的 `dart:ui`） |
| S4-4 | `glass.dart` 第 126 行附近注释按 R10 去掉 `[GlassBar]` 悬空引用 |
| S4-5 | `one_tokens.dart`：删 `OneBlur`、`OneElevation`、`OneShadows`（先确认文件内无其它成员引用它们） |
| S4-6 | `glass_action.dart`：删 `PolicySwitchRow`；`soft_label.dart`：删 `SoftLabelStack` |
| S4-7 | 跑状态根 `scan_unreferenced.ps1`，确认 S4 文件内不再有零引用公开符号（`GlassBackdrop`、`glassDockScrollPadding` 有引用属正常） |
| S4-8 | `dart format`；`flutter analyze`；`flutter test --no-pub test/design/` |

所有权：第 1 节 S4 行列出的 7 个文件。**禁止**碰 `liquid_glass.dart`、`ultra_glass_dock.dart`、`one_status_hero.dart`、`glass_surface.dart`。

### S5 · auth 表现层（子代理 E · Fable 5.1 · 风险中）

| 步骤 | 内容 |
|---|---|
| S5-1 | 新建 `widgets/login_form.dart`：`LoginForm`，参数按 G1；`build` 返回原 `_buildForm` 从 `Form(key: formKey, ...)` 起的子树（`Scaffold`/`GlassBackdrop`/`SafeArea`/`LayoutBuilder`/滚动/居中约束这些页面骨架留在 `LoginScreen`） |
| S5-2 | 静态 Key（`hostFieldKey`、`portFieldKey`、`usernameFieldKey`、`passwordFieldKey`、`submitKey`… 以文件实际为准）留在 `LoginScreen`，按 R5 传参 |
| S5-3 | `login_screen.dart`：`_buildForm` 只保留页面骨架 + `LoginForm(...)` |
| S5-4 | `dart format`；`flutter analyze`；`flutter test --no-pub test/features/auth/presentation/` |

所有权：`lib/features/auth/presentation/**`、`test/features/auth/presentation/**`。

### S6 · 换行归一（主 Agent，在 S1–S5 全部验证通过之后）

| 步骤 | 内容 |
|---|---|
| S6-1 | 新建 `.gitattributes`（见 G9） |
| S6-2 | 用 PowerShell 把 `git ls-files --eol` 中 `w/crlf` 的文本文件（排除 `*.bat`）改写为 LF，UTF-8 编码与 BOM 状态保持不变 |
| S6-3 | `git status --porcelain` 只剩本轮有意改动；`git diff --numstat` 对未改内容的文件为空；`git ls-files --eol` 无 `w/crlf` |
| S6-4 | 重跑三裁判 |

## 7. 派发与验证协议

1. **顺序**：B 试点（主 Agent）→ 全量三裁判绿 → 记 `WAVE_HASHES_BEFORE.tsv` → **并行**派 S1–S5（5 个子代理，模型 `claude-fable-5-1`，每个只拿自己的所有权清单 + 本计划书路径）→ 回收。
2. **漂移检查（回收后第一件事，无论子代理报成功还是报错）**：全库哈希对比 `WAVE_HASHES_BEFORE.tsv`；任何改动落在非本主题所有权的文件 → `git checkout -- <file>` 还原并记 `OBSERVATIONS.md`；子代理报错但文件已改 → 逐文件 diff 判断是接管续做还是还原（第七轮经验）。
3. **验证环**：主 Agent 串行跑三裁判 + 裁判 5 复扫；失败 → 定位是哪个主题 → 若是规则漏洞则修第 3 节并让该主题重做；若是实现错误则主 Agent 直接修。
4. **每 ~25 文件漂移自审五问**：还在 SCOPE 内？行为等价？替代测试（去掉这处改动任务是否仍失败）？有没有幻觉改动？有没有滚雪球？本轮总量约 30 文件，回收后做一次。
5. **S6** 最后做，做完再跑一遍三裁判。
6. **账本**：每个主题的 PASS 记 `VERIFY_LEDGER.tsv`（主题、文件、命令、退出码、日志路径、时间）。
7. **回滚**：本轮不 commit；任何文件回滚 = `git checkout -- <file>`；新文件回滚 = 删除。整轮放弃 = `git checkout -- . && git clean -fd lib test docs/refactor .gitattributes`（需用户授权才执行）。

## 8. 需要用户拍板的事项（默认值已选，可否决）

| # | 事项 | 默认 |
|---|---|---|
| D1 | `design/one` 是 Ultra 迁来的视觉原件，是否删其中无人引用的部分 | **删**（仓库以「干净好维护」为准；需要时可从 git 历史找回） |
| D2 | `login_screen` 表单是否抽出 | **抽**（与其它页面对齐；有 `login_screen_test` 兜底） |
| D3 | 换行归一是否本轮做 | **做**（上一轮已决策「启用 git 时一并归一」） |
| D4 | 本轮结束是否 commit | **不 commit**，留给用户；建议信息见第 9 节 |

## 9. 执行记录

### 9.1 时间线

| 步骤 | 执行者 | 结果 |
|---|---|---|
| 侦察 + 基线 | 主 Agent | format 178/0 · analyze 0 · test 556/556；21 个「M」确认为行尾假阳性 |
| B 试点批 | 主 Agent | RED → GREEN；test 559/559（+3）；规则手册无歧义，放量 |
| S1–S5 并行派发 | 5 个子代理（`claude-fable-5-1`） | S3、S4 正常交付报告；S1、S2、S5 在收尾阶段被平台中断（「Named models unavailable / Free plans can only use Auto」），**文件改动已全部完成** |
| 漂移检查 | 主 Agent | 21 处改动（5 修改、2 删除、14 新建）全部落在各自所有权，DRIFT_COUNT=0 |
| 逐字搬移审查 | 主 Agent | 用「被删行 ∈ 新文件」机械核对 4 个页面：残差仅为格式化器压行与规则要求的参数化改名 |
| 判据 6 补齐 | 主 Agent | `login_screen._buildForm`（65 行）内联进 `build`，HTTPS 回调抽为 `_setHttps`；行为不变 |
| 合并验证 | 主 Agent | format 188/0 · analyze 0 · test 559/559 |
| S6 换行归一 | 主 Agent | `.gitattributes` + 90 文件 CRLF→LF；`git diff --numstat` 证明内容零变化；对 64 个内容未变文件刷新 stat（`git diff --cached` 为空） |
| 最终验证 | 主 Agent | format 188/0 · analyze 0 · test **559/559** |

### 9.2 成功判据逐条核对

| # | 判据 | 结果 |
|---|---|---|
| 1 | `dart format` 退出 0 | ✅ 188 files / 0 changed |
| 2 | `flutter analyze` 0 issues | ✅ |
| 3 | 测试全绿且 ≥ 556，既有断言不改 | ✅ 559/559；`test/` 既有文件零改动，仅新增 `local_time_text_test.dart` |
| 4 | `design_boundary_test` 通过 | ✅（含在全量内） |
| 5 | S4 文件内无零引用公开符号 | ✅ 复扫仅剩 extension 名 `OneChannelStatePolicy`（成员隐式调用，允许） |
| 6 | 四页面无 ≥40 行私有 `Widget _xxx()` | ✅ grep 为空；automation 409→207、overview 361→149、sms 332→223、login 392→172 行 |
| 7 | `padLeft(2, '0')` 仅在 `local_time_text.dart` | ✅ |
| 8 | `git status` 只列有意改动；无 `w/crlf` | ✅ 13 M / 2 D / 14 新文件；`git ls-files --eol` 无 `w/crlf`、`w/mixed` |

### 9.3 与规格的偏离（全部为规则内的必然结果，已核实无行为变化）

- S4：`glass_overlays.dart` 内计划未点名的 `GlassDialogBackdrop` 按 R9 级联删除；`glass.dart` 注释因此改两处而非一处（R10）。
- S2：四个格式化函数因被 3 个新组件共用而公开为 `widgets/overview_format.dart`（`overviewFallback/overviewPercent/overviewBytes/overviewRate`），功能片内共享，非跨模块抽象。
- S5：`LoginForm` 27 个构造参数（R4/R5 要求逐个传数据、回调与 Key）；主 Agent 另将 `_buildForm` 内联并抽出 `_setHttps`。
- 子代理只跑了各自主题测试（R14）；全量由主 Agent 串行跑三次（合并后、内联后、S6 后）。

### 9.4 变更清单

新建（14）：`.gitattributes`、本计划书、`lib/core/format/local_time_text.dart`、`test/core/format/local_time_text_test.dart`、`auth/presentation/widgets/login_form.dart`、`automation/presentation/widgets/{automation_task_card,automation_run_card,automation_action_status,automation_labels}.dart`、`overview/presentation/widgets/{overview_host_metrics,overview_host_panel,overview_usage_panel,overview_format}.dart`、`sms/presentation/widgets/sms_composer.dart`。

修改（13）：`design/one/{glass,glass_chrome}.dart`、`design/tokens/one_tokens.dart`、`design/widgets/{glass_action,soft_label}.dart`、`auth/presentation/login_screen.dart`、`automation/presentation/automation_screen.dart`、`logs/presentation/logs_screen.dart`、`overview/presentation/overview_screen.dart`、`sms/presentation/sms_screen.dart`、`sms/presentation/widgets/sms_message_bubble.dart`。

删除（2）：`design/one/glass_select.dart`、`design/one/glass_overlays.dart`。

净变化：`git diff --numstat` 13 个已跟踪文件 +91 / −1263 行；加上新文件后 `lib/` 总行数约 17.5k → 约 17.0k。

### 9.5 未提交 · 建议

按 D4 未 commit。建议信息：`refactor: extract presentation widgets, dedupe time formatting, drop dead design code, normalise EOL`。范围外候选见状态根 `OBSERVATIONS.md`。
