# 2026-09-08 · 性能优化 + 抓 Bug 计划书（第二轮 · 性能猎手 × 系统化排障）

> 状态：**规格已冻结**（第 0–7 节执行期不得改软；第 8 节为执行记录，随进度追加）。
> 方法：性能侧沿用第一轮闭环 —— 先侦察定性 → 建可复现基线与量化目标 → profile / 审计定位真瓶颈 → 一次只改一个变量 → 同基准复测 → 正确性 + 回归 → 收益递减即止。**没有数据，就没有优化。**
> Bug 侧走系统化排障 —— 复现 + 采证 → 对照正常路径 → 竞争假设证伪 → 根因 → **先 RED 再最小修复** → 回归 + 同类扩散。**没有失败测试，就没有 Bug；没有根因，就没有修复。**
> 状态根：`.xj-cursor/perf-r2/`（gitignored；原始测量输出、子任务报告、账本都在那里）。
> 代码基线：`bf90674`（`main`，第九轮重构已提交）。工作区 18 个「M」全为 CRLF 行尾噪声（`git diff --numstat` 为空），源码内容等同 HEAD。

## 0. 侦察结论（有证据，非拍脑袋）

| 事实 | 证据 |
|---|---|
| 第一轮 T1 基线已定案：S1 冷启动 TTID=TTFD p50 **306.5 ms**（≤ 1.0 s → 不立项）；S4 内存 TOTAL PSS 中位 127.7 MB、Graphics 占 52%（仅记录）；S3 APK **18,948,069 B**，`libflutter.so` 61%（无应用侧修法）、`libapp.so` 33%（唯一候选：`--split-debug-info` 构建参数实验，保留门槛 −5% ≈ −947,403 B） | `.xj-cursor/perf-r1/reports/T1-baseline.md` §7 |
| 第一轮 T2 / T3 / T4 静态审计**从未产出**；T5 渲染基准脚手架在 worktree 有 7 个文件（`integration_test/perf_scroll_test.dart`、`support/*` ×5、`test_driver/perf_driver.dart`）+ pubspec 加了 `integration_test` / `flutter_driver`，但**未验收、未跑过真机**，且基于 `4497b4a`，落后 main 一个提交 | `git -C <worktree> status`；`.xj-cursor/perf-r1/reports/` 只有 T1 |
| 最新提交 `bf90674` = 第九轮重构：新增 `lib/core/state/request_notifier.dart`，9 个控制器改继承 `RequestNotifier`，`+308 / −556` 行；三裁判 format 191/0 · analyze 0 · test **584/584** | `git show --stat HEAD`；`docs/refactor/2026-09-08-refactor-plan-round9.md` §11 |
| 第九轮自己记录了 3 条「理论可观察」行为差异（O1 eSIM 切换未验证时动作永久停在 `submitting`；O2 短信失败分支多一次票据判断；O3 设备详情动作成功后多拉一次详情的判断点前移），**测试均未覆盖这些路径** | `.xj-cursor/refactor-r9/OBSERVATIONS.md` |
| 真机在线：小米 `c0b76e3b`（MIX Fold 2 · Android 15 · 120 Hz · 单帧预算 8.33 ms），电量 **53%**、充电中 → 过了第一轮定的「≥ 50% 才测」噪声门 | `adb devices`、`dumpsys battery` |
| 本机：Flutter 3.44.9 stable / Dart 3.12.2 / DevTools 2.57.0 / Git 2.54；`adb` 不在 PATH，实际位于 `E:\sdk\Android\platform-tools\adb.exe` | `flutter --version`、`adb version` |
| 规模：`lib/` 131 个 dart 文件（app / core / design / features×8），`test/` 60 个文件；接口契约文档 `docs/http-api.md` | 目录扫描 |
| PowerShell 5 的 `Get-Content` / `Set-Content` 会破坏 UTF-8 中文并写 BOM | 第九轮 O5 实测 |

**定性**：
- 性能：无「最近变慢」回归线索（第九轮是结构保持型重构，通知次数与请求序列逐一等价），按「本来如此」处理。第一轮已排除冷启动与内存，**剩下未测量的两层是「稳态渲染（玻璃效果 / 长列表）」与「客户端数据层（请求瀑布 / 主 isolate 解析 / 安全存储读取）」**，本轮以 S2 真机基线 + 两份静态审计把它们从「假设」变成「有数据的结论」。
- Bug：**最新鲜、影响面最大的改动 = `RequestNotifier` 重构**，且已知 3 条未被测试覆盖的行为分支 → 抓 Bug 火力第一优先级对准状态层与并发；第二优先级是数据契约与解析边界（DTO / SSE / 时间格式 / 错误码映射）与 UI 边界（空态、错误态、超长文本、溢出）。

## 1. 目标、场景与量化锚点

无产品级 SLO，锚点一律标注来源属性；目标值在基线冻结后按落数规则写入第 8 节，之后不得改软。

### 1.1 性能

| 编号 | 场景（可复现） | 指标（含分位） | 起点锚点（来源） | 目标落数规则 |
|---|---|---|---|---|
| **S2 稳态渲染**（本轮主战场） | `flutter drive --profile` 跑 `integration_test`：假后端注入真实规模数据（日志 ≥ 300 行、短信 ≥ 200 条、设备 ≥ 30 台），依次滑动 日志 / 短信 / 设备 / 总览 页；1 轮预热 + ≥ 5 轮测量 | 每页每轮 `average / 90th / 99th_percentile_frame_build_time_millis`、同名 `rasterizer` 三项、`missed_frame_build_budget_count`、`missed_frame_rasterizer_budget_count`；跨轮 中位 / 均值 / p95 / 样本标准差 / CV | Flutter 官方：单帧预算 = 1 / 刷新率；本机 120 Hz → 8.33 ms（若系统把 App 限到 60 Hz，以 `dumpsys display` 实测为准 → 16.67 ms） | 若某页 99 分位 build+raster 均 ≤ 预算且丢帧数为 0 → 该页不立项；否则目标 = 该页 99 分位降到预算内 或 下降 ≥ 20%，且丢帧数下降 ≥ 50% |
| **S3 包体·单变量实验** | 同一提交 `bf90674` 连做两次 `flutter build apk --release --target-platform android-arm64`：对照组无额外参数；实验组加 `--split-debug-info=build/symbols`（可选第二个单变量 `--obfuscate`，**分开做**） | APK 字节数（确定性，CV ≈ 0） | 第一轮 T1：18,948,069 B（`4497b4a`）；本轮以对照组重新落数 | 实务变化门 = 减少 ≥ 5%（对照组 × 5%）才「过门」并写入发布文档；否则记入负知识 |
| **S5 数据层** | 由 P2 静态审计给出假设；用 S2 基准的假后端请求计数 / 时间线证实 | 启动 / 切页请求数、串行链长度、单次 JSON 解析耗时（主 isolate）、安全存储读取次数 | 无 | 只对被 S2 时间线证实的项立项 |

**噪声门（本框架工程启发式）**：同一正值指标跨 ≥ 5 轮 `CV = 样本标准差 / 均值 × 100%` ≤ 5% 才冻结；CV > 5% 先控噪（电量 ≥ 50%、`loadavg 1m < 1.5` 再起轮、`am force-stop` 无关应用、轮间间隔 3 s、不碰手机、不折叠），仍不达则如实记录并加大轮数。丢帧计数这类接近 0 的指标改用绝对离散度，CV 不适用。

### 1.2 Bug

| 项 | 规则 |
|---|---|
| 什么算 Bug | 必须有 **RED 证据**：一个描述「期望正确行为」的失败测试（`flutter test` 非 0 退出，输出可贴），或一条可重复的手测步骤。没有 RED 只能叫「疑点」，单独列表，不计入 Bug 数。 |
| 分级 | **P0** 崩溃 / 数据丢失 / 凭据泄漏；**P1** 功能错误、状态卡死（如按钮永久禁用）、请求错发漏发；**P2** 边界与体验（空态错、溢出、时间格式错、错误提示不准）；**P3** 代码卫生（不影响用户）。 |
| 修复规则（Wave 2） | 一次只修一个 Bug；先 RED 后 GREEN；三裁判全绿（`dart format` 退出 0、`flutter analyze` 0 issues、`flutter test` 全绿且用例数只增不减）；修完做「同类扩散」搜索。禁止用判空 / 重试 / try-catch 遮症状。 |
| 边界 | 第九轮 O1 这类「现状如此但产品上可疑」的行为：Bug 猎手负责用 RED 证明**用户可见后果**（如按钮永久禁用），是否改由用户拍板，本计划书不替产品决策。 |

## 2. 范围与铁律

### IN SCOPE

- 只读审计：`lib/**`、`android/app/**`、`pubspec.yaml`、`docs/http-api.md`
- 新增测量与验证基础设施（不改 App 行为）：worktree 内 `integration_test/**`、`test_driver/**`、`pubspec.yaml` 仅允许 SDK 自带的 `integration_test`、`flutter_driver` 两个 dev 依赖；Bug 猎捕 worktree 内新增 `test/**/*_bughunt_test.dart`
- Wave 2 的单变量优化 / 单 Bug 修复：仅限被数据 / RED 证实且用户已选定的项，逐个进行

### OUT OF SCOPE（本轮不许碰）

- 任何用户可见文案、颜色、间距、语义标签、业务逻辑与接口契约（Bug 修复除外，且需用户选定）
- 第三方依赖新增 / 升级（`DEPENDENCY_ALLOWLIST` = `integration_test`、`flutter_driver`，仅 dev、仅 worktree）
- `android/signing/**`、`android/key.properties`（只读，不复制、不提交）
- 主工作区 git 写操作：**不 commit、不 push、不 stash、不 reset、不改行尾**（18 个 CRLF 噪声文件原样保留）；Bug 猎捕 worktree 只留工作区改动、不 commit
- 既有 `test/**` 一字不改（Bug 猎捕只新增文件）

### 六条内核（冲突时以它们为准）

1. 先测量后优化：无 profile / 基线数据，不改任何一行「为了性能」的代码。
2. 绑定基线与目标：每个优化都对第 8 节冻结的基线 diff。
3. 单变量：一次只改一个东西，单独测、可归因、可回滚。
4. 正确性优先：三裁判全绿；Bug 修复先 RED 再 GREEN。
5. 防回归、可读性守恒：牺牲可读性的微优化须实测显著收益背书。
6. 收益递减即止：达目标或未过实务变化门（`|增益| > max(2 × max(CV_base, CV_cur), 5%)`）就停。

### 工程纪律（全体子代理）

- 文本文件一律用编辑器写入工具写，UTF-8 无 BOM、LF 行尾；**禁止**用 PowerShell `Set-Content` / `Out-File` / `>` 写含中文的文件（O5）。
- 事实与推断分开写；解析不出的字段写 `NOT AVAILABLE`；未执行的写 `NOT RUN`；禁止编数字。
- 只写自己任务卡「允许写入」列的路径；越权 = 停下标 `BLOCKED` 回报。
- 主工作区只允许 P1 / P2 只读、主 Agent 跑 flutter 命令；P3 独占真机与 worktree 构建；B1 / B2 在各自隔离 worktree 里跑 `flutter test`。

## 3. 主流程与任务拆分（WBS）

```
[T0 计划书]（主 Agent，本文件）
   ↓
[Wave 1 · 并行]（子代理 × 5，模型 claude-fable-5-1；主 Agent 同时做 M1 / M2）
   P1 性能静态审计 · 渲染层（启动链 + 应用壳 + 设计层玻璃效果 + 各功能页列表）     只读
   P2 性能静态审计 · 数据层（HTTP / SSE / JSON / 安全存储 / 轮询 / RequestNotifier）  只读
   P3 S2 稳态渲染基准 · 脚手架验收 + 真机采集（唯一允许碰设备与 worktree 构建的任务）
   B1 Bug 猎捕 · 状态层与并发（RequestNotifier + 9 控制器 + 请求线 + 会话门）       隔离 worktree · RED 测试
   B2 Bug 猎捕 · 数据契约 / 解析 / UI 边界（DTO / SSE / 时间 / 错误码 / 空态 / 溢出）  隔离 worktree · RED 测试
   M1 主 Agent：HEAD 三裁判基线落盘
   M2 主 Agent：S3 单变量实验（对照组 → 实验组，两次构建）
   ↓
[汇总 · 主 Agent · 串行] 合并 P1 / P2 假设 + P3 数据 → 按「Amdahl 占比上限 / 修改成本 / 风险」排序；
   合并 B1 / B2 → 只保留有 RED 的条目，按 P0→P3 排序 → 交用户选定
   ↓
[Wave 2 · 主 Agent · 串行 · 需用户选定]
   Bug：取一个 → 主工作区复现 RED → 最小修复 → 三裁判 → 同类扩散 → 记账
   性能：取影响最大的一个被证实瓶颈 → 单变量修改 → 三裁判 → P3 基准同口径复测 ≥ 5 轮 → 两侧 CV、实务变化门 → 保留 / 回退 → 记账
   ↓
[Wave 3 · 收尾] 前后对比报告、负知识清单、S2 / S3 基准命令固化为发布前门禁
```

### 任务卡

| 任务 | 交付物 | 允许写入 | 禁止 |
|---|---|---|---|
| **P1 渲染层审计** | `.xj-cursor/perf-r2/reports/P1-render-audit.md` | 仅该文件 | 任何源码修改；任何 `flutter` / `adb` / git 写命令 |
| **P2 数据层审计** | `.xj-cursor/perf-r2/reports/P2-data-audit.md` | 仅该文件 | 同上 |
| **P3 S2 基线** | worktree 内脚手架修正（仅 `integration_test/**`、`test_driver/**`、`pubspec.yaml` 两个 dev 依赖）；`.xj-cursor/perf-r2/bench/round<N>/*.json` 原始产物；`.xj-cursor/perf-r2/reports/P3-s2-baseline.md` | 上述路径 | 主工作区任何文件；worktree 内 `lib/**`、既有 `test/**`；git commit |
| **B1 状态层 Bug** | 隔离 worktree 内 `test/**/*_bughunt_test.dart`（只新增）；`.xj-cursor/perf-r2/reports/B1-state-bugs.md` | 上述路径 | `lib/**`；既有 `test/**`；git commit；设备 |
| **B2 契约 / UI Bug** | 隔离 worktree 内 `test/**/*_bughunt_test.dart`（只新增）；`.xj-cursor/perf-r2/reports/B2-contract-ui-bugs.md` | 上述路径 | 同上 |
| **M1 裁判基线** | `.xj-cursor/perf-r2/baseline/{format,analyze,test}.log` | 该目录 | — |
| **M2 S3 实验** | `.xj-cursor/perf-r2/s3/{control,treatment}-*.txt`、`reports/M2-s3-split-debug-info.md` | 该目录；`build/` 由 flutter 自行写 | 改 `lib/ test/ android/ pubspec*` |

### 审计范围与检查清单

**P1 渲染层**（范围：`lib/main.dart`、`lib/app/**`、`lib/design/**`、`lib/features/*/presentation/**`）
- 启动链：首帧之前与之后各做了什么（`SessionGate.bootstrap`、安全存储读取、`MaterialApp.builder` 里 `GlassBackdrop` 包住全部页面、根部 `ListenableBuilder(appearance)` 的重建范围）
- 玻璃 / 模糊：`BackdropFilter` / `ImageFilter.blur` 的个数、嵌套、是否位于可滚动区域内；触发 `saveLayer` 的 `Opacity` / `ShaderMask` / 抗锯齿 `ClipPath` / `ClipRRect`；自绘 `CustomPainter.shouldRepaint` 是否恒 true；缺失或误用的 `RepaintBoundary`
- 动画：持续跑的 `AnimationController` / `Ticker`（如点阵表情、液态玻璃）在不可见时是否停止；`vsync` 挂载点
- 列表：`ListView` vs `ListView.builder`、`shrinkWrap`、`itemExtent` / `prototypeItem`、列表项内的重活（格式化 / 排序 / 正则 / 图片解码）、非 `const` 构造
- 订阅范围：`ListenableBuilder` / `Provider` 是否整页订阅导致任一字段变化整页重建；`MediaQuery.of` 在根部导致键盘弹出整树重建
- 字体 / 资源：自带字体加载时机、大图无尺寸

**P2 数据层**（范围：`lib/core/**`、`lib/features/*/data/**`、`lib/features/*/state/**`、`lib/app/app_dependencies.dart`）
- 请求瀑布：启动与切页时的串行 `await` 链（可并行却串行）、切 Tab 重复拉取、无缓存 / 无条件刷新
- 主 isolate 解析：日志 ≥ 300 / 短信 ≥ 200 条时 `jsonDecode` + DTO 映射的耗时与分配；是否值得 `compute`（只作假设）
- SSE：`SseDecoder` 的字符串拼接是否 O(n²)、缓冲增长、按块解码、重连策略与退避
- 轮询 / 定时器：日志 watch 的间隔、失败后是否继续、dispose 是否取消
- 安全存储：`flutter_secure_storage` 每次读取都是平台通道调用，启动 / 切页各读几次；`BaseUrlStore` 同理
- HTTP 客户端复用（每请求新建 `Client` vs keep-alive）、`RequestRegistry` 开销、`notifyListeners` 风暴（循环内多次通知）、每次 build 都排序 / 拷贝列表

**B1 状态层与并发**（范围：`lib/core/state/**`、`lib/core/http/request_slot.dart`、`request_registry.dart`、`lib/features/*/state/**`、`lib/app/session_gate.dart`、`lib/app/app_dependencies.dart`；裁判参考 `test/core/state/**`、`test/features/*/state/**`、`test/support/**`）
- 线索（非绑定假设，须自行核实或证伪）：O1 eSIM `switchProfile` 在 `!result.verified` 时动作永久停留 `submitting`（用户可见后果？）；O2 / O3 微差异是否真的不可达；两次快速调用同一动作的票据竞态与取消语义；请求在途时 dispose（通知是否落在已 dispose 的 `ChangeNotifier` 上）；动态槽 map（automation `_writes`、device_list `_overviewReads`）是否无界增长；日志 watch 定时器在失败 / dispose 后是否残留；`silent` 刷新失败被吞导致陈旧数据无提示；`SessionGate.bootstrap` 的错误路径与会话中途失效（401）的处理；`isStale` 语义

**B2 数据契约 / 解析 / UI 边界**（范围：`lib/core/http/{json_shape,sse_decoder,backend_error_codes,http_transport}.dart`、`lib/core/format/**`、`lib/core/security/**`、`lib/core/config/**`、`lib/features/*/data/**`、`lib/features/*/domain/**`、`lib/features/*/presentation/**`；契约真源 `docs/http-api.md`）
- DTO 对照契约：字段名 / 可选字段 / 未知枚举值是否崩；数字以字符串到达、int vs double、秒 vs 毫秒时间戳、负数 / 零 / 空数组 / 超大数
- SSE：事件跨块切分、CRLF vs LF、多行 `data:`、注释行、`id:` / `retry:`、多字节 UTF-8 在块边界被切开、关闭时残留半个事件
- HTTP：超时、非 2xx 且非 JSON 响应体、错误码到 `StateFailure` 的映射、日志脱敏是否漏 token
- 配置：`BaseUrl` 尾斜杠、http/https、IP:端口、大小写、空白
- 时间：`local_time_text` 的时区 / 夏令时 / 跨午夜 / 未来时间
- UI：窄屏 `RenderFlex` 溢出、用户数据 `Text` 无 `maxLines` / 省略、空态 / 错误态 / 加载态是否可达且正确、本地化键缺失

## 4. 报告条目格式（统一，便于主 Agent 机器合并）

**性能假设条目（P1 / P2 · 每条都是待证假设，不是修改许可证）**

`编号 | 影响等级(高/中/低) | 位置(文件:行) | 反模式/现象 | 证据(≤5 行代码摘录) | 影响机制(UI 线程/光栅线程/主 isolate/IO/内存) | 置信度 | 需要什么测量来证实(具体命令/工具/指标) | 单变量修法草案 | 预估收益上限(按占比推断)`

**Bug 条目（B1 / B2 · 只有 CONFIRMED 才算 Bug）**

`编号 | 等级(P0–P3) | 状态(CONFIRMED/REFUTED/UNDECIDED) | 位置(文件:行) | 期望行为 | 实际行为 | RED 测试文件 + 命令 + 失败输出摘录(≤10 行) | 根因假设(5-Why 一句话链) | 最小修复草案(不实施) | 同类扩散(同模式的其它位置) | 用户可见后果`

REFUTED 的条目保留在报告末尾「已证伪」小节（测试文件可保留作回归，须在报告标明）；UNDECIDED 写清缺什么证据。

## 5. 测量协议

### 5.1 S2（P3 · 逐字执行）

环境标签：记录 `dumpsys battery`（电量 / 状态）、`settings get global low_power`、`dumpsys display`（当前模式与刷新率）、`cat /proc/loadavg`、前台窗口；测量前 `am force-stop com.oneims.ultra.lite` 与被测包；屏幕常亮、不折叠、不触碰。

```powershell
$adb = 'E:\sdk\Android\platform-tools\adb.exe'; $dev = 'c0b76e3b'
$wt  = 'C:\Users\Administrator\.cursor\worktrees\onewifi-android\perf-scroll-harness'
$out = 'E:\GQ\Ultra\onewifi-android\.xj-cursor\perf-r2\bench'

# 0. worktree 对齐 main（分支无自有提交，pubspec 本地改动与 main 不冲突）
git -C $wt merge --ff-only main
# 1. 依赖与静态检查（网络失败时：$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'；仍失败用 --offline）
Set-Location $wt; flutter pub get; flutter analyze --no-pub     # 必须 0 issues
# 2. 预热 1 轮 + ≥5 轮测量；每轮前 loadavg 1m < 1.5 才起轮，轮间 3 s
foreach ($i in 0..5) {
  & $adb -s $dev shell cat /proc/loadavg
  flutter drive --profile -d $dev --driver=test_driver/perf_driver.dart --target=integration_test/perf_scroll_test.dart
  New-Item -ItemType Directory -Force "$out\round$i" | Out-Null
  Copy-Item build\*.timeline_summary.json "$out\round$i\"     # 每页一个 summary；若脚手架输出路径不同以实际为准
  Start-Sleep 3
}
```

- 第 0 轮为预热，**不计入统计**；每页每指标跨第 1–5 轮算 中位 / 均值 / p95 / 样本标准差 / CV；CV > 5% 标红并写噪声来源。
- 若 `flutter drive` 无法非交互退出或挂住：终止、记 `NOT RUN`、说明卡在哪一步；不编数字。
- 若假后端暴露请求计数 / 时间线：一并落盘（供 S5）。

### 5.2 S3（M2 · 主 Agent）

```powershell
# 对照组（bf90674，无额外参数）
flutter build apk --release --target-platform android-arm64
(Get-Item build\app\outputs\flutter-apk\app-release.apk).Length   # → s3\control-bytes.txt
# 实验组（唯一变量：--split-debug-info）
flutter build apk --release --target-platform android-arm64 --split-debug-info=build\symbols
(Get-Item build\app\outputs\flutter-apk\app-release.apk).Length   # → s3\treatment-bytes.txt
```

过门 = 实验组比对照组少 ≥ 5%。若过门：正确性验证 = 该参数不改 Dart 语义（官方文档明示只是把符号搬出 APK），代价是崩溃堆栈需 `flutter symbolize` + 保留 `build/symbols` —— 写进发布文档；`--obfuscate` 作为第二个独立单变量另测（时间允许）。

## 6. 风险与对策

| 风险 | 对策 |
|---|---|
| 子代理因账号并发限制被中断 | 回收时先看每个报告文件是否存在、是否完整；缺的由主 Agent 串行补做或重派，不虚构协作 |
| 多任务并发跑 `flutter` 争用 `.dart_tool/` | 主工作区只有主 Agent 跑；P3 在 perf worktree、B1 / B2 在各自隔离 worktree，各有独立 `.dart_tool/` |
| `flutter pub get` 拉 `flutter_driver` 传递依赖失败（网络） | 官方中国镜像 `PUB_HOSTED_URL`；仍失败 `--offline`；仍失败 P3 交付脚手架 + `NOT RUN` |
| 脚手架基于 `4497b4a`，控制器构造已被第九轮改动 | P3 第 0 步 ff 到 main 后跑 `flutter analyze`，编译不过就改脚手架适配（只改 `integration_test/**`） |
| 真机电量 53% 接近门槛 | 充电中；每轮记录电量；掉到 < 50% 停测并记录 |
| 静态审计 / 疑点被当成事实直接改代码 | 报告格式强制「置信度 + 需要什么测量」与「RED 证据」；Wave 2 只处理有数据 / 有 RED 的项，且需用户选定 |
| Bug 猎手为了让测试红而写错期望 | 每条 RED 必须引用契约来源（`docs/http-api.md`、既有测试、类文档注释）说明「为什么这才是期望」；主 Agent 逐条复核 |
| 两次 release 构建与 P3 的 profile 构建并发拖慢主机 | APK 字节数确定性，不受影响；构建耗时本轮不作指标 |

## 7. 成功判据（全部满足才算 Wave 1 完成）

1. `P1` / `P2` 报告各 ≥ 8 条、≤ 25 条格式合规的假设，按影响排序，前 5 条写明证实手段。
2. `P3` 报告含环境标签、四页 × 6 指标 × ≥ 5 轮的统计表、CV 标注、与预算对照、每页「立项 / 不立项」判定；或明确 `NOT RUN` 与卡点。
3. `B1` / `B2` 报告：每条 CONFIRMED 都有可复跑的 RED 命令与失败输出；REFUTED / UNDECIDED 分列；无 `lib/**` 改动。
4. `M1` 三裁判日志落盘；`M2` 两组字节数与过门判定落盘。
5. 主工作区 `git status` 与开工前一致（18 个 CRLF 噪声 + 本计划书 + 无其它）；无 `*.apk` 入库。

## 8. 执行记录（随进度追加）

- 2026-09-08 12:45 · 侦察（§0）；规格冻结（§1–7）；状态根 `.xj-cursor/perf-r2/` 建立。
- 2026-09-08 12:52 · Wave 1 派发：P1 / P2 / P3（generalPurpose）、B1 / B2（隔离 worktree）→ 5 个子代理并行，模型 `claude-fable-5-1`；主 Agent 同时做 M1 / M2。
- 2026-09-08 12:53 · **M1 裁判基线**（`bf90674`，主工作区）：`dart format` 退出 0 · `flutter analyze` 0 issues · `flutter test` **584/584**（28 s）。日志 `.xj-cursor/perf-r2/baseline/`。
- 2026-09-08 12:59 · **M2 S3 单变量实验**（报告 `reports/M2-s3-split-debug-info.md`）：对照组 **18,948,069 B**（与第一轮逐字节同尺寸；中间产物新编译，尺寸相同是页对齐吸收了 −250 行 Dart）；`--split-debug-info` → **18,030,565 B（−917,504 B，−4.84%）**，按 5% 门禁（≥ 947,404 B）**差 29,900 B 未过门 → 负知识**；叠加 `--obfuscate` → 17,965,029 B（−5.19%，过门，但 obfuscate 自身只贡献 64 KiB）。`lib/` 无 `runtimeType` 等类型名依赖（grep 0 命中）；真机冒烟 `NOT RUN`。是否采纳属产品决策，见报告 §4。
- 2026-09-08 13:04 · **P2 数据层审计**回收（`reports/P2-data-audit.md`）：20 条假设（高 3 / 高中 1 / 中 3 / 中低 3 / 低中 2 / 低 8），附启动与各页请求时间线。前三：H01 每个 HTTP 请求前串行 2 次平台通道读取（SP + 安全存储，零缓存；设备页 30 台 = 62 次）；H02 设备列表按台数扇出 N 路 `/esim` 并逐个通知（30 台 = 32 次整页重建）；H03 日志页每 5 s 全量重拉 500 行 JSON（**是轮询不是 SSE**）+ 每 tick 两次整页重建。修正认知：主壳 5 页签（总览 / 设备 / 短信 / 保号 / 设置），日志是设置下二级页，eSIM 是设备详情内面板。
- 2026-09-08 13:17 · **B1 状态层 Bug 猎捕**回收（`reports/B1-state-bugs.md`；worktree `bughunt-b1-state`，分支 `bughunt/b1-state`，6 个新测试文件，`+3 -8`）：**CONFIRMED 5**（P1 2 · P2 1 · P3 2）、REFUTED 6、UNDECIDED 1。P1：B1-01 设置页任一节读取失败被 `_ignore` 吞成 `data` + 默认值，用户保存会把默认值 PUT 回网关；B1-02 自动化任务运行记录被挤出首页 20 条后永久 `submitting(reconciling)`，三个按钮禁用到重启。P2：B1-03 `silent` 轮询顶替非 silent 刷新并失败后 `refreshing` 成为终态。P3：B1-04 = 第九轮 O1（生产不可达）；B1-05 `AutomationController._writes` 删任务后槽不回收。O2 / O3、dispose 竞态、日志定时器、401 路径均 REFUTED。
- 2026-09-08 13:33 · **B2 契约 / UI Bug 猎捕**回收（`reports/B2-contract-ui-bugs.md`；worktree `bughunt-b2-contract-ui`，分支 `bughunt/b2-contract-ui`，7 个新测试文件 35 用例 `+17 -18`）：**CONFIRMED 7**（P1 3 · P2 1 · P3 3）、REFUTED 8、UNDECIDED 5。P1：B2-01 「检查更新」用 `GET` 打契约 `POST`；B2-02 「修改密码」用 `POST` 打契约 `GET|PUT`——**两条与既有 `settings_api_test.dart` 断言矛盾，须用真实网关 / WEB 路由表定案后才进 Wave 2**；B2-03 通知设置回写把多条 `urls` 截成 1 条（保存即丢数据，可升 P0）。P2：B2-04 ≥ 16 位纯数字短信被当「系统短信」隐藏正文。P3：SSE 解码器 3 处偏离 WHATWG、`BaseUrlPolicy` 把 localhost 当公网、缺 `Content-Type` 时按 latin1 解码。其余 44 条路由 × 方法与文档一致。
- 2026-09-08 13:56 · 原 P1 自 13:12 起无任何新动作（转录停滞 44 分钟），判定停滞；补派 **P1b**（同模型，限时 30 分钟，先写骨架再追加）。
- 2026-09-08 14:12 · **P1b 渲染层审计**回收（`reports/P1-render-audit.md`）：11 条假设（高 2 / 中 4 / 低 5），6 项检查全部有结论。关键事实：**全应用无 `ListView.builder` / `SliverList`**——日志页 ≤ 500 行、短信页 ≥ 200 张联系人卡都展开在 `ListView` 单个 child 内的一个 `Column` 里（无视口裁剪、整块重建、新日志插顶导致 1000 个段落全部重排）；5 页全部顶层 `AnimatedBuilder(controller)` 整页订阅；**无自有常驻动画**（证伪「静止后仍有帧 = 常驻 Ticker」，更可能是 5 s 轮询的成对重建帧）；真模糊克制（每页 1–2 个 `BackdropFilter`，列表项内 0 个）。R01（日志页）与 R02（短信页）为高影响，与 P2 H03 / P3 预热轮「build p99 超预算、光栅在预算内」相互印证。
- 2026-09-08 12:56–14:37 · **P3 S2 真机基线**：脚手架已 ff 到 `bf90674` 并适配（改动仅 `integration_test/**`、`test_driver/**`）；真机 120 Hz 确认。连续遭遇环境阻碍：① worktree 在 C 盘、pub 缓存在 E 盘 → Kotlin 增量编译跨盘崩（改为单独构建 profile APK + `flutter drive --use-application-binary` 绕过）；② MIUI「USB 安装」确认弹窗需自动点击；③ `--no-build` 已废弃；④ DDS；⑤ Timeline 环形缓冲溢出只保留最后 2.9 s；⑥ FrameTiming 与 Timeline 两套口径需对齐；⑦ **14:05 起设备从 adb 消失**——同一台电脑上另一个项目（`E:\GQ\One`、`E:\GQ\Ultra\Onetools`）正并发跑 Gradle 并向同一部手机安装 `com.oneims.ultra.lite`，疑其经 Shizuku 把 adbd 切到 TCP 导致 USB 断连。仅有预热轮日志页一份有效数据（attempt 6：build avg 2.54 / p90 6.06 / **p99 9.06 ms**、最差帧 26.3 ms、超 8.33 ms 预算 7 帧；raster p99 5.93 ms；319 帧全为 120 Hz）。**5 轮正式测量 NOT RUN**；P3 报告 `reports/P3-s2-baseline.md` 撰写中，待设备重新独占后按其「重跑一条命令」补测。
- 漂移检查（14:05）：主工作区 `git status` = 18 个 CRLF 噪声 + `?? docs/perf/`，`git diff --numstat` 为空；3 个 worktree（perf / b1 / b2）均无提交；`lib/**` 与既有 `test/**` 零改动；无 `*.apk` 入库。
- 2026-09-08 14:21 · 事故：本文件与两份报告被外部进程（疑为编辑器旧缓冲自动保存）原样回写，§8 的 12:52–14:12 记录丢失一次，14:40 重写。**教训：子代理 / 主 Agent 写完的文件不要在编辑器里长期打开。**
- 2026-09-08 15:32 · **用户裁定：真机 / S2 / P3 永久略过**。不再跑 adb、`flutter drive`、5 轮正式测量、设备冒烟；S3 是否采纳也不再以真机冒烟为前置。性能项仅保留静态审计 + 预热轮一份数据，不做 S2 裁决。
- 2026-09-08 15:32 · **Wave 2 已修两条可抹网关配置的 P1**（未提交）：B2-03 通知 `urls` 全量回写；B1-01 `load()` 分节失败不再吞成默认值，保存前按脏通道重拉或拒绝。`flutter analyze --no-pub` 0 issues；`flutter test --no-pub` **588/588**（基线 584 + 4 个新 RED）。改动仅 `settings_dto.dart` / `gateway_settings.dart` / `settings_controller.dart` + 两个新 `*_bughunt_test.dart`。
- 2026-09-08 15:40 · **B1-02**：`_reconcileRuns` 在首页找不到 id ≥ minimum 的 run 时，把 `submitting(reconciling)` 回退 idle（不碰 in-flight / 失败未知）。RED → GREEN：`automation_reconcile_bughunt_test.dart`。未提交。

### 8.1 Wave 1 汇总排序（供 Wave 2 选定）

**Bug（只列 CONFIRMED，按等级 → 用户可见后果排序）**

| # | 等级 | 一句话 | 修复前置 | 修复成本（推断） |
|---|---|---|---|---|
| B2-03 | P1（可升 P0） | 通知设置保存把 webhook / bark / wecom 多条 `urls` 截成 1 条，网关上的第 2+ 条地址被静默抹掉 | 无 | 小 |
| B1-01 | P1（可升 P0） | 设置页某一节读取失败被吞成默认值且无提示；用户保存会把默认值 PUT 回网关 | 无 | 中 |
| B1-02 | P1 | 自动化任务运行记录被挤出首页 20 条后永久「提交中」，三个按钮禁用到重启 | 产品确认「回退 idle」 | 小 |
| B2-01 | P1（待仲裁） | 「检查更新」用 `GET` 打契约 `POST` | 用真实网关 / WEB 路由表定案 | 极小 |
| B2-02 | P1（待仲裁） | 「修改密码」用 `POST` 打契约 `GET|PUT` | 同上 | 极小 |
| B2-04 | P2 | ≥ 16 位纯数字短信被当「系统短信」隐藏正文 | 产品确认判定规则 | 小 |
| B1-03 | P2 | `silent` 轮询顶替刷新并失败后「正在刷新」进度条常驻 | 无 | 小 |
| B1-04 / B1-05 / B2-05 / B2-06 / B2-07 | P3 | 契约缺口 / 槽不回收 / SSE 规范偏离 / localhost 判定 / latin1 回退 | 无 | 各极小 |

**性能（按 Amdahl 占比上限 × 证据强度排序；全部仍需 S2 数据裁决）**

| # | 来源 | 一句话 | 已有证据 | 单变量修法 |
|---|---|---|---|---|
| R01 + H03 | P1b / P2 / P3 预热轮 | 日志页 500 行全展开在一个 `Column`、5 s 轮询每 tick 两次整页重建 | 预热轮 build p99 9.06 ms > 8.33、7 帧超预算、光栅在预算内 | 先 R01-A（`SliverList.builder` 逐行）或 H03-b（数据未变不通知），一次一个 |
| R02 + H02 + H05 | P1b / P2 | 短信页 200 卡全展开 + 整页订阅设备控制器，30 台设备 = N+4 次整页重建 5000+ widget | 结构事实；未测 | R02 逐卡 builder；或 H02-a 扇出后汇聚一次通知 |
| H01 + H06 | P2 | 每个 HTTP 请求前串行 2 次平台通道读取，零缓存 | 结构事实；未测耗时 | 内存缓存装饰器（`CachedTokenStore` / `CachedBaseUrlStore`） |
| H04 | P2 | 切 Tab 无条件重拉（除保号页） | 结构事实 | 新鲜度守卫 |
| S3 | M2 | `--split-debug-info` −4.84%（未过 5% 门）；+`--obfuscate` −5.19%（过门，需真机冒烟） | 已测 | 产品决策 |
