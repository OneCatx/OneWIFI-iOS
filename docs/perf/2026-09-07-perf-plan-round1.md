# 2026-09-07 · 性能优化计划书（第一轮 · 性能猎手闭环）

> 状态：**规格已冻结**（第 0–6 节执行期不得改软；第 7 节为执行记录，随进度追加）。
> 方法：先侦察定性 → 建可复现基线与量化目标 → profile / 审计定位真瓶颈 → 一次只改一个变量 → 同基准复测 → 正确性 + 回归 → 收益递减即止。**没有数据，就没有优化。**
> 状态根：`.xj-cursor/perf-r1/`（gitignored；原始测量输出、子任务报告、基准脚本产物都在那里）。
> 代码基线：`4497b4a`（`main`）。工作区 18 个「M」全为 CRLF 行尾噪声（`git diff --numstat` 为空），源码内容等同 HEAD。

## 0. 侦察结论（有证据，非拍脑袋）

| 事实 | 证据 |
|---|---|
| 独立 Flutter Android 客户端，包名 `com.oneims.onewifi`，v0.1.1+2 | `pubspec.yaml`、`android/app/build.gradle.kts:46` |
| 8 个功能片（auth / automation / devices / esim / logs / overview / settings / sms），分层 data / domain / presentation / state；状态用 `ChangeNotifier` + `ListenableBuilder`/Provider；网络用 `package:http` + 自研 `HttpTransport`/`RequestRegistry`/`RequestSlot`/`SseDecoder` | `lib/` 目录树、`lib/app/app_dependencies.dart` |
| 启动路径：`main()` → `OneWifiApp`（`ListenableBuilder(appearance)` 包住整个 `MaterialApp`）→ `MaterialApp.builder` 里 **`GlassBackdrop` 包住全部页面** → `SessionGate.bootstrap()` → 登录页或 `AndroidOneImsShell` | `lib/main.dart`、`lib/app/app.dart:50-90`、`lib/app/session_gate.dart:61-66,108-129` |
| 设计层大量「玻璃」组件（`glass*`、`liquid_glass`、`ultra_glass_dock`、`dot_matrix_face`），模糊/半透明/自绘是 Flutter 光栅线程经典热点 | `lib/design/one/*`、`lib/design/widgets/*` |
| 发布包已做 arm64-only + R8 `isMinifyEnabled`/`isShrinkResources` | `build.gradle.kts:54-55,73-74` |
| 裁判就位：`dart format`、`flutter analyze`、`flutter test`（第八轮记录 556/556 全绿） | `docs/refactor/2026-09-07-refactor-plan-round8.md` §0 |
| 本机环境：Flutter 3.44.9 stable / Dart 3.12.2 / DevTools 2.57.0 / Android SDK 36 / Git 2.54；`adb` 不在 PATH，实际位于 `E:\sdk\Android\platform-tools\adb.exe` | `flutter --version`、`flutter doctor`、`android/local.properties` |
| 真机：小米 22061218C（MIX Fold 2）、Android 15（API 35）、arm64、**120Hz** 屏（单帧预算 8.33ms）、序列号 `c0b76e3b`、已唤醒未锁屏、充电中但电量 16% | `flutter devices`、`adb shell dumpsys power/window/display` |
| 目标包未安装（机上只有 `com.oneims.app`）→ 冷启动可采「全新安装、无 token → 登录页」确定性场景，不依赖网络 | `adb shell pm list packages` |
| 无产品级 SLO 文档 | `docs/` 全文无性能指标 |
| 网络：`maven.google.com` 超时；本地已有 `build/` 与 `android/.gradle/`，Gradle 依赖大概率已缓存 | `flutter doctor` |

**定性**：无「最近变慢」的回归线索（近期提交是重构/本地化/出包配置，未触及渲染或网络热路径），按「本来如此」处理，不做 bisect；怀疑范围按信号分层落在 **前端渲染（玻璃效果 / 列表）** 与 **客户端数据层（请求瀑布 / 主 isolate 解析 / 安全存储读取）** 两层，均为**待证假设**。

## 1. 目标、场景与量化锚点

无 SLO，锚点一律标注来源属性；**最终目标值在基线冻结后按下表公式落数**，写入第 7 节，之后不得改软。

| 编号 | 场景（可复现） | 指标（含分位） | 方向 | 起点锚点（来源） | 目标落数规则 |
|---|---|---|---|---|---|
| S1 冷启动 | 全新安装 release APK，无 token；`am force-stop` 后 `am start -W` 到登录页；预热 1 次后测 ≥10 轮 | TTID（`Displayed`）与 TTFD（`Fully drawn`，即 Flutter 首帧）各自的 中位数 / p95 / 均值 / 样本标准差 / CV | 越小越好 | Android vitals 官方「过慢」红线：冷启动 ≥ 5s；本框架启发式起点：TTFD p50 ≤ 1.5s | 若基线 p50 已 ≤ 1.0s：不立项；否则目标 = p50 下降 ≥ 20% 且 p95 不升 |
| S2 稳态渲染 | `flutter drive --profile` 跑 `integration_test` 基准：假后端（`MockClient`）注入真实规模数据（日志 ≥300 行、短信 ≥200 条、设备 ≥30 台），依次滑动 日志 / 短信 / 设备 / 总览 页，各 ≥5 轮 | 每轮 `average/90th/99th_percentile_frame_build_time_millis`、`average/90th/99th_percentile_frame_rasterizer_time_millis`、`missed_frame_build_budget_count`、`missed_frame_rasterizer_budget_count` | 越小越好 | Flutter 官方：60Hz 单帧 16.67ms；本机 120Hz 单帧 8.33ms | 目标 = 99 分位 build+raster 均 ≤ 8.33ms（120Hz）或 ≤ 16.67ms（若系统把 App 限到 60Hz，以实测 vsync 为准）；丢帧数下降 ≥ 50% |
| S3 包体 | `flutter build apk --release --analyze-size --target-platform android-arm64` | APK 字节数；构成占比（`libapp.so` / `libflutter.so` / assets / res / dex） | 越小越好 | 无官方阈值；仅报构成 | 只对占比 ≥ 10% 且有明确修法的项立项；无则不立项 |
| S4 内存 | S1 每轮冷启动后停留登录页 5s，`dumpsys meminfo` | `TotalPss`、`Java Heap`、`Native Heap`、`Graphics`（≥5 轮，中位数 / CV） | 越小越好 | 无官方阈值；仅记录 | 只在 profile 发现泄漏/分配风暴时立项 |
| S5 数据层 | 由 T4 静态审计给出假设；用 S2 假后端基准的请求计数与时间线证实 | 启动/切页请求数、串行链长度、单次 JSON 解析耗时（主 isolate）、安全存储读取次数 | 越少/越短越好 | 无 | 只对被 S2 时间线证实的项立项 |

**噪声门（本框架工程启发式）**：同一正值指标跨 ≥5 轮 `CV = 样本标准差 / 均值 × 100%` ≤ 5% 才冻结；CV > 5% 先控噪（充电至 ≥50%、关闭省电、固定亮度、屏幕常亮、轮间间隔 3s、不碰手机），仍不达则如实记录并加大轮数。**电量 16% 是已知噪声源，基线备注必须写明。**

## 2. 范围与铁律

### IN SCOPE

- 测量与审计：`lib/**`、`android/app/**`、`pubspec.yaml`、`assets/**`（只读）
- 新增测量基础设施（不改 App 行为）：`integration_test/**`、`test_driver/**`；`pubspec.yaml` 仅允许新增 **SDK 自带** 的 `integration_test`、`flutter_driver` 两个 dev 依赖
- 第 3 阶段单变量优化：仅限被数据证实的瓶颈，逐个进行

### OUT OF SCOPE（本轮不许碰）

- 任何用户可见文案、颜色、间距、语义标签、业务逻辑与接口契约
- 第三方依赖新增/升级（`DEPENDENCY_ALLOWLIST` = `integration_test`、`flutter_driver`，仅 dev）
- `android/signing/**`、`android/key.properties`（只读，不复制、不提交）
- git 写操作：**不 commit、不 push、不 stash、不 reset、不改行尾**（18 个 CRLF 噪声文件原样保留）

### 六条内核（冲突时以它们为准）

1. 先测量后优化：无 profile / 基线数据，不改任何一行「为了性能」的代码。
2. 绑定基线与目标：每个优化都对第 7 节冻结的基线 diff。
3. 单变量：一次只改一个东西，单独测、可归因、可回滚。
4. 正确性优先：`dart format --output=none --set-exit-if-changed lib test` 退出 0；`flutter analyze --no-pub` 0 issues；`flutter test --no-pub` 全绿且用例数只增不减。
5. 防回归、可读性守恒：牺牲可读性的微优化须实测显著收益背书。
6. 收益递减即止：达目标或未过实务变化门（`|增益| > max(2 × max(CV_base, CV_cur), 5%)`）就停。

## 3. 主流程与任务拆分（WBS）

```
[T0 计划书]（主 Agent，本文件）
   ↓
[Wave 1 · 并行 · 只读为主]（子代理 × 5，模型 Fable 5.1）
   T1 基线采集（唯一允许碰设备与构建的任务）
   T2 静态审计 · 启动链 + 应用壳 + 设计层玻璃效果
   T3 静态审计 · 各功能页与列表渲染
   T4 静态审计 · 数据层（HTTP / SSE / JSON / 安全存储 / 轮询）
   T5 建 S2 稳态渲染基准（integration_test 脚手架；隔离 worktree 里开发，不碰设备）
   ↓
[Wave 2 · 主 Agent · 串行] 汇总 T2–T4 假设 + T1 数据 → 按「预估收益(Amdahl 占比上限) / 修改成本 / 风险」排序
   → 合入 T5 脚手架 → 在真机跑 S2 基线 ≥5 轮 → 用时间线证实/否决前 3 个假设
   ↓
[Wave 3 · 主 Agent · 串行] 取影响最大的 1 个瓶颈 → 单变量修改 → 裁判三连（format/analyze/test）
   → 同基准复测 ≥5 轮 → 两侧 CV、实务变化门 → 保留 / 回退 → 记入第 7 节
   → 未达目标且仍有高影响项：对当前版本重新 profile 再取第一名
   ↓
[Wave 4 · 收尾] 前后对比报告、回退清单（负知识）、把 S1/S2 基准命令固化为发布前门禁（`NOT RUN` 条件写明）
```

### 任务卡

| 任务 | 交付物 | 允许写入 | 禁止 |
|---|---|---|---|
| T1 基线 | `.xj-cursor/perf-r1/baseline/`（逐轮原始输出）+ `.xj-cursor/perf-r1/reports/T1-baseline.md`（S1 / S3 / S4 汇总，含 CV 与环境标签） | 仅上述目录；`build/` 由 flutter 自行写 | 改 `lib/ test/ android/ pubspec*`；`flutter clean`；git 写操作 |
| T2 审计·启动与壳 | `.xj-cursor/perf-r1/reports/T2-startup-shell.md` | 仅该文件 | 任何源码修改；任何 `flutter` 命令 |
| T3 审计·页面与列表 | `.xj-cursor/perf-r1/reports/T3-screens-lists.md` | 仅该文件 | 同上 |
| T4 审计·数据层 | `.xj-cursor/perf-r1/reports/T4-data-layer.md` | 仅该文件 | 同上 |
| T5 渲染基准脚手架 | 隔离 worktree 分支：`integration_test/perf_scroll_test.dart`、`test_driver/perf_driver.dart`、`integration_test/support/**`、`pubspec.yaml`（仅加两个 SDK dev 依赖）；`flutter analyze` 0 issues | 上述文件 | `lib/**`、既有 `test/**`；设备；主工作区 |

审计报告统一条目格式（**每条都是待证假设，不是修改许可证**）：

`编号 | 影响等级(高/中/低) | 位置(文件:行) | 反模式/现象 | 证据(≤5 行代码摘录) | 影响机制(UI 线程/光栅线程/主 isolate/IO/内存) | 置信度 | 需要什么测量来证实(具体命令/工具/指标) | 单变量修法草案 | 预估收益上限(按占比推断)`

## 4. 测量协议（T1 · 逐字执行）

环境标签：Windows 11 25H2 主机；小米 22061218C / Android 15 / 120Hz；USB 直连 `c0b76e3b`；充电中；记录 `dumpsys battery` 电量与 `settings get global low_power`；屏幕常亮、亮度固定、测量期间不触碰手机、不开其它 App。

```powershell
$adb = 'E:\sdk\Android\platform-tools\adb.exe'; $dev = 'c0b76e3b'; $pkg = 'com.oneims.onewifi'
$out = '.xj-cursor\perf-r1\baseline'; New-Item -ItemType Directory -Force $out | Out-Null

# S3 包体（同时产出 release APK；--analyze-size 与 --split-per-abi 互斥，本项目用 abiFilters，无冲突）
flutter build apk --release --analyze-size --target-platform android-arm64 2>&1 | Tee-Object "$out\s3-analyze-size.log"
Get-Item build\app\outputs\flutter-apk\app-release.apk | Select-Object Length | Tee-Object "$out\s3-apk-bytes.txt"
# 若 release 签名失败：改 --profile 并在报告标注「构建类型=profile」

# 安装（全新）
& $adb -s $dev uninstall $pkg 2>$null
& $adb -s $dev install -r build\app\outputs\flutter-apk\app-release.apk
& $adb -s $dev shell svc power stayon usb          # 测完恢复：svc power stayon false

# S1 冷启动（1 轮预热 + 10 轮测量；每轮：force-stop → 清 logcat → am start -W → 等 5s → 抓 Displayed/Fully drawn → S4 meminfo）
foreach ($i in 0..10) {
  & $adb -s $dev shell am force-stop $pkg; Start-Sleep 3
  & $adb -s $dev logcat -c
  & $adb -s $dev shell am start -W -n "$pkg/.MainActivity" | Tee-Object "$out\s1-round$i-amstart.txt"
  Start-Sleep 5
  & $adb -s $dev logcat -d -s ActivityTaskManager:I ActivityManager:I | Select-String 'Displayed|Fully drawn' | Tee-Object "$out\s1-round$i-logcat.txt"
  & $adb -s $dev shell dumpsys meminfo $pkg | Tee-Object "$out\s4-round$i-meminfo.txt"
}
```

- 第 0 轮为预热（安装后首启），**不计入统计**。
- `Displayed` = TTID；`Fully drawn` = Flutter 首帧（引擎在首帧回调里调 `reportFullyDrawn`）。两者都记；若 `Fully drawn` 缺失，如实写 `NOT AVAILABLE` 并解释。
- 汇总：每个指标 10 轮的 最小 / 中位 / 均值 / p95 / 样本标准差 / CV；CV > 5% 时标红并写明噪声来源。
- 可选补充（不阻塞）：`flutter run --profile --trace-startup -d c0b76e3b` 若能非交互退出，收 `build/start_up_info.json`（`timeToFirstFrameMicros` 等）；挂住则终止并标 `NOT RUN`。

## 5. 风险与对策

| 风险 | 对策 |
|---|---|
| 电量 16%、可能触发省电/降频 → S1/S4 噪声 | 记录电量与省电开关；CV > 5% 时等电量 ≥ 50% 复测；不得拿高噪声数据下结论 |
| Gradle 依赖未缓存 + `maven.google.com` 超时 → 构建失败 | 依赖构建的项标 `NOT RUN`，不编数字 |
| `flutter pub get` 拉 `flutter_driver` 传递依赖失败 | 单条命令临时加 `PUB_HOSTED_URL=https://pub.flutter-io.cn`（Flutter 官方中国镜像文档）；仍失败则 T5 交付源码 + `NOT RUN` |
| 多个任务并发跑 `flutter` 命令争用 `.dart_tool/` | 只有 T1 在主工作区跑 `flutter`；T5 在隔离 worktree；T2–T4 不跑任何 `flutter` 命令 |
| 审计条目被当成事实直接改代码 | 报告格式强制「置信度 + 需要什么测量」；Wave 3 前必须有 S1/S2 数据证实 |
| 折叠屏内外屏切换改变分辨率/刷新率 | 测量期间不折叠；报告记录 `dumpsys display` 的当前模式 |

## 6. 成功判据（全部满足才算本轮完成）

1. 第 7 节有冻结基线：S1（≥10 轮）、S3、S4（≥5 轮）；S2（≥5 轮）在 T5 合入后补齐。
2. 每个保留的优化都有：基线值 → 优化后值、两侧 CV、是否过实务变化门、裁判三连结果。
3. 未过门禁的尝试已回退并记入「负知识」。
4. 基准命令固化为可一条命令重跑的脚本或文档段落。
5. 工作区无新增 `*.apk` 入库、无 git 写操作、行尾噪声文件未被改动。

## 7. 执行记录（随进度追加）

- 2026-09-07 · T0 计划书冻结；Wave 1 派发：T1–T5 → 子代理（Fable 5.1）。
- 2026-09-07 · 首次派发受账号并发限制中断：T1 原始数据已落盘（S1 第 0–10 轮、S3、S4 第 0–10 轮，13:19–13:28）但无汇总报告；T5 worktree `perf/integration-scroll-benchmark` 已建、无改动；T2–T4 未产出。
- 2026-09-07 · 第二次派发（主 Agent 接续，不改 §0–6）：T1 改为「基线汇总」（只处理已落盘数据，不再碰设备）；T2 / T3 / T4 只读审计；T5 在既有 worktree 内开发。子代理模型 Fable 5.1。
