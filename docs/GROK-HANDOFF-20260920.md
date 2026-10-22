# OneWIFI Android 修复交接 · 给 Grok

交接日期：2026-09-20（Asia/Shanghai）

## 1. 你的任务

接手当前工作树，完成剩余的真机验收与交付准备。**不要从头重做已经修复的 BUG，也不要把自动化通过等同于真机通过。**

用户最初反馈短信弹出异常，随后要求通盘检查并修复。两轮排查确认的 23 项代码问题已修复；复审、终审发现的关联边界也已补测修复。代码审查与独立终审均允许交付指定修复包，但没有完成真实手机安装、锁屏/后台、真实 SIM 和音频验收。

优先顺序：

1. 核验工作树与安装包身份，不修改现场。
2. 协调用户提供测试设备、测试网关和允许执行的操作。
3. 做本文件的真机验收，记录版本、条件、预期和实际。
4. 若发现新故障，先稳定复现、补失败用例，再做局部修复和回归。
5. 协助所有者处理旧更新凭据撤销/轮换，但不要未经明确授权自行操作账号。
6. 给出最终验收报告；发布、提交、推送和版本号调整需要另外明确范围。

本交接文档不是对外发布、删除数据、真实发短信、拨号或改 SIM 配置的自动授权。

## 2. 工程位置与重要现场约束

- 工程根目录：`E:\GQ\Ultra\ONEWIFI\android`。这里同时包含 Flutter 的 `lib/`、`test/` 和原生 `android/` 子目录。
- Shell：PowerShell；Flutter：`C:\Flutter\flutter\bin\flutter.bat`；Android SDK：`E:\sdk\Android`。
- 源码基准 HEAD：修复开始时为 `3917514`。**HEAD 不是完整修前状态**，当时已有大量用户未提交修改和未跟踪文件。
- 修前快照：`E:\GQ\Ultra\ONEWIFI\android\.xj-cursor\repair-2026-09-20\baseline`。
- 修复未 commit、未 push、未发布 Release。当前工作树的修改和未跟踪文件必须保留。
- 不得 `git reset --hard`、整体 checkout、清空未跟踪文件，或把所有 `git diff` 都归为本轮修复。
- 真正本轮生产/依赖增量见 `SOURCE-MANIFEST.json`，包含 42 项路径及修前/修后哈希；另有测试、夹具和文档增量。
- `.cursor/rules/secondary-menus.mdc` 要求二级菜单居中弹出；继续使用现有 `showOneGlassPopup` / `showOneGlassDialog`。
- `android/local.properties`、签名配置和安全存储可能含秘密。不要全文输出、上传、写入日志或贴到报告中。

本交接回合重新检查了 APK 哈希，与下节一致；没有重跑全部测试。下节测试数来自上一轮修复的实际执行记录。

## 3. 可交付 APK：必须按哈希识别

文件：

`E:\GQ\Ultra\ONEWIFI\android\build\app\outputs\flutter-apk\OneWIFI-0.1.16-fixed-20260920.apk`

- 包名：`com.oneims.onewifi`
- versionName / versionCode：`0.1.16 / 21`
- minSdk / targetSdk：`24 / 36`
- ABI：`arm64-v8a`
- 大小：`19,930,644 bytes`
- 构建时间：`2026-09-20 03:48:25 +08`
- SHA256：`0FB0053A7475E42904780E5D3188044F0A0550AABD6C771071EDE4FEDD73DFF5`
- 签名：APK v2 验证通过，RSA4096，1 个签名者。
- 签名证书 SHA256：`0fd12e4b250f87faa0555e87714d53e6bb2fcf27433e8bd47ee6bf3b09d9d9b0`

**版本号没有提升，不能只看“0.1.16”就认定已安装修复版。** 历史目录内有同版本旧包；核验实际安装来源、签名和 APK 哈希。新包尚未安装到用户手机。

## 4. 已完成的修复，不要回退

### 短信

- DTO 到控制器保留消息方向和 `last_sms_id`；自己的发件不作为收到的验证码。
- 消息 ID 单调消费；无 ID 时按时间/正文兼容去重，不再用消息总数变化判断新消息。
- 联系人加载与 OTP 轮询共享快照代次，旧响应不能回退状态或重放验证码。
- **较新的空快照也推进代次**，但静默空结果保留 last-good 联系人是用户既有契约；在途 loading/refreshing 必须正常收口，不能以“清空一切”修复。
- 8 秒轮询合并在途请求，不不断取消慢请求。
- 多码按旧到新串行处理，最后保留最新码；关闭/重开/销毁使用 watch epoch 防迟到操作。
- 首次基线由实际摄入时状态决定，不能在请求发起时提前固定 `seed=true`。
- 发信互斥独立于联系人选择；确认、结果、草稿清空绑定联系人和草稿版本；删 A 不关闭 B。

### 原生通知接口

通道 `com.oneims.onewifi/otp`：

- `show({code, sender, device}) → bool`：true 表示通知已提交；false 表示拒绝、取消或不能提交。
- `cancel() → void`：撤销待授权通知，不保证撤回已经提交给系统的通知。
- Kotlin 权限队列等待授权结果，允许后补发，拒绝/销毁/取消不谎报成功，队列有界 16 条。
- Dart `AndroidSmsOtpSink` 仅在 true 且未取消时复制剪贴板、更新交付结果。
- API24/25 补通知声音前提；激活 Base64 改用已有 Okio，线格式和 HMAC 保持兼容。

### eSIM 与通话

- 卡身份使用完整、不透明 target，不使用脱敏尾号作草稿/cache 键。
- APN/IP 草稿按卡归属；切卡重置，确认期间换卡取消旧提交，同卡刷新保留编辑。
- `savePolicy()` 返回本次是否成功；策略提交纳入 busy，未执行/失败不写成功缓存。
- 旧卡晚到结果、非活动卡保存和旧读不污染当前策略。
- 通话切设备失效旧上下文，拒绝当前设备与旧 callId 混合操作。
- 媒体连接 single-flight、代次校验、迟到 socket 关闭、回调按 socket 实例归属。
- 通话页主动加载设备并正确替换监听。

### 设置、更新与安全

- 设置按字段修订代次合并查询结果，不覆盖期间完成的保存；无关设置不清授权码草稿。
- 更新检查 30 秒总截止，覆盖 token、响应头和响应体；离页取消。第二次下载凭据读取也检查取消，不能离页后才启动原生安装。
- 更新下载固定 GitHub 仓库资产授权范围；跳转不带 token，拒绝 HTTP 降级；匿名请求仍使用 `Accept: application/octet-stream`。
- APK 不再编译 `GITHUB_UPDATE_TOKEN`，原生读取构建 token 的方法已删除。改为本机运行时安全存储和设置入口。
- HTTPS 默认系统验证；自签按明确的完整 origin 和叶证书 DER SHA256 绑定，网关/Mihomo/WSS 共用策略。
- 有 pin 时强绑定，公信 CA 不能绕过错误 pin；配置改变关闭旧连接，错误 pin 不自动降级或自动信任新证书。
- 登出只清 bearer 命名空间，不删除证书指纹和更新凭据。

## 5. 验证事实及证据索引

修复最后一轮：

- `flutter analyze --no-pub`：No issues found，exit 0。
- `flutter test --no-pub --reporter failures-only`：**804 passed**，exit 0。
- 原生 JUnit：**37 tests / 0 failures / 0 errors / 0 skipped**。
- release 构建、签名核验均通过。
- 新 APK DEX/lib/assets 共 75 个条目仅在内存比对旧更新凭据：没有匹配；BuildConfig 无旧更新凭据字段。
- 独立 `deep-reviewer` 与 `final-audit`：PASS，范围仅代码及指定 APK 交付。

按以下顺序阅读（均在工程根目录下）：

1. `.xj-cursor/repair-2026-09-20/VERIFICATION.md`：修复映射、验证结果、边界。
2. `.xj-cursor/repair-2026-09-20/final-audit.md`：最高终审、23 项追踪与回滚限制。
3. `.xj-cursor/repair-2026-09-20/review-full.md`：复审返工与闭合记录。
4. `.xj-cursor/repair-2026-09-20/SOURCE-MANIFEST.json`、`ARTIFACT-CHECK.json`：源与制品身份。
5. 同目录 `flutter-final-output.txt`、`native-final-output.txt`、`release-final-output.txt`、`artifact-final-signature.txt`。
6. `docs/SECURITY-CONNECTIONS.md`：证书指纹与本机更新凭据的用户操作说明。
7. 原始两轮诊断：`.xj-cursor/bug-audit-2026-09-20/REPORT.md`、`EXTRA-REPORT.md`。

注意：原始诊断目录中的临时复现和旧分域报告是历史证据，部分接口/预期已随修复调整。**以正式 `test/` 下回归、当前源码和最终终审为准**，不要运行旧探针后把旧接口报错当新 BUG。

若在另一台机器交接，`.xj-cursor/` 可能被 Git 忽略且未随源码传过去。须另行确认拿到这些报告、必要 baseline 和修复源码；不要直接打包整个目录，里面包含修前文件与本地诊断资料，需要先检查敏感内容。

## 6. 剩余事项：明确未完成

### A. 真机验收（最高优先）

上轮没有 ADB 设备，以下全部未做实机验收。先确认测试手机、网关与操作许可，保留安装前版本/数据；不要先卸载或清数据。

- [ ] 安装身份：核对设备 ABI、签名、实际安装包与交付哈希；同版本号不能作为充分证明。
- [ ] Android13+首次通知：初始未授权、允许、拒绝、关闭系统通知/渠道、取消等待、重新进入，检查每次结果与提示。
- [ ] 短信前台/切后台/锁屏：记录 OS/ROM、电池策略、进程是否存活、渠道重要性和免打扰；区分“未检测”“未提交”“有通知无横幅”。
- [ ] 多设备/多联系人连续验证码：重复快照不重弹，旧响应不回退，最终剪贴板对应最新有效码；日志不要记正文、码值或完整号码。
- [ ] 关闭推送、退出账号、重开：旧请求和授权回调不能继续复制或展示；不要以任意 sleep 掩盖竞态。
- [ ] 短信发送/删除切联系人：先用模拟后端验证，不为复现而给真实号码重复发短信。真实发送需确认目标、费用与允许次数。
- [ ] eSIM：优先测试卡/模拟后端；换卡 APN/IP、同尾号卡、保存中再操作、失败提示、确认期间换卡。真实切卡/删除/策略写入需单独确认并准备原配置恢复。
- [ ] 通话：设备切换、冷启动设备加载、挂断/退出后 socket 释放；真实拨号须确认目标与费用。音频能力见下方产品边界。
- [ ] API24/25：激活读取/保存及 Base64 兼容、通知展示；使用授权的测试账号，不随意占用真实授权席位。
- [ ] HTTPS：公信证书无需 pin；自签未配拒绝、正确 pin 接通 HTTP/WSS、错误 pin 拒绝、换证重新核对；Mihomo 不同地址不能借用网关 pin。
- [ ] 更新：本机配置凭据、私仓权限错误、正常检查、弱网超时、离页取消、未知来源授权后重试、系统安装；触发安装前获得用户同意。

每个场景记录：设备/系统/ROM、APK 身份、前置状态、操作步骤、预期、实际、脱敏证据、PASS/FAIL/NOT RUN。

### B. 旧凭据处置

- 新 APK 不含旧凭据，**不代表旧凭据已失效**；历史 APK 未删除、未撤回。
- 请所有者在 GitHub 确认旧凭据并撤销/轮换；不要通过聊天传递实际 token。
- 新凭据只给指定安装包仓库必要的只读权限，经 APP 本机入口保存；不放回 Gradle、dart-define、assets 或明文配置发行包。
- 未经明确授权，不操作用户 GitHub 账号，也不把“提醒了”写成“已撤销”。

### C. 产品边界，不要未经确认扩成新需求

- 仍按联系人最新消息轮询，不是完整短信事件流；同一联系人在两次轮询间的多条消息可能被后续预览覆盖。
- 杀掉 APP 进程后停止监视是原设计；没有新增常驻服务。若要求杀进程后照样推送，先单独设计/确认。
- 本次修通话信令和媒体连接，不是补齐全部麦克风采集/音频播放；不能仅凭 socket 接通声称已能正常双向通话。
- 没有穷举所有证书/重定向排列；过期证书实物握手、跨端口真实 TLS、跳转回 API 第三跳可按需要补覆盖。
- 全 APP 零 BUG、所有 ROM 兼容、生产放量均没有被证明。

## 7. 常用命令（PowerShell）

只读身份核验：

```powershell
Set-Location -LiteralPath 'E:\GQ\Ultra\ONEWIFI\android'
git status --short
Get-FileHash -LiteralPath 'build/app/outputs/flutter-apk/OneWIFI-0.1.16-fixed-20260920.apk' -Algorithm SHA256
& 'E:\sdk\Android\platform-tools\adb.exe' devices -l
```

自动化回归：

```powershell
flutter analyze --no-pub
flutter test --no-pub --reporter failures-only
```

Windows 原生测试使用已验证的进程级 JDK 配置，避免 `Unable to establish loopback connection`。不需要修改系统环境变量：

```powershell
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot'
$env:JAVA_TOOL_OPTIONS = '-Djava.nio.channels.spi.SelectorProvider=sun.nio.ch.WindowsSelectorProvider -Djava.net.preferIPv4Stack=true -Djdk.net.unixdomain.tmpdir=C:/Windows/Temp'
Push-Location -LiteralPath 'E:\GQ\Ultra\ONEWIFI\android\android'
try { .\gradlew.bat :app:testDebugUnitTest --no-daemon --console=plain }
finally { Pop-Location }
```

确有源码变更且要生成新候选包时再构建：

```powershell
flutter build apk --release --no-pub
```

构建会替换 `app-release.apk`。不要未经核验覆盖当前独立命名交付包；新包应另存新文件、重新记录哈希、签名、版本和凭据扫描结果。更改源码后，旧终审和旧测试结果不自动适用于新包。

测试定位：短信 `test/features/sms/`；卡策略 `test/features/esim/presentation/esim_policy_regression_test.dart`；通话 `test/features/calls/`；设置 `settings_async_regression_test.dart`；更新 `board_update_timeout_test.dart`；TLS `test/core/http/gateway_io_client_test.dart`；原生 `android/app/src/test/`。

## 8. 给用户的最终回报格式

不要只说“没问题”。请交付：

1. 本次验收的确切 APK 哈希、设备与系统。
2. 已完成场景及每项证据，未完成项及原因。
3. 新发现问题的最小复现、根因、改动文件、失败→通过结果。
4. 是否改源码、重新构建、安装、执行真实业务操作或操作凭据，以及相应授权。
5. 当前可交付/可发布范围；不要把受控验收通过扩张为所有环境保证。

建议开场：先读上述证据并核对工作树，再向用户确认可用测试设备和允许的真机操作。不要先重构、清理目录、升级依赖、发布或重做两轮修复。
