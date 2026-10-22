# iOS CallKit Implementation Plan

> 执行：subagent-driven-development；用户已指定 Astra 并要求直接开始。

**Goal:** 在无 APNs/PushKit 的前提下接通原生 CallKit、后台已接通音频及完整 App 通话控制。

**Architecture:** 原生统一协调、网络和PCM，Flutter仅配置/意图/快照。所有权、系统音频激活和后端状态分开。

**Tech Stack:** 既有 Flutter/Dart；Swift、CallKit、AVFAudio、URLSession；既有HTTP/SSE/PCM网关。

## Global Constraints

CallKit必做；不接APNs/PushKit；不改P12/签名材料；不改Android/WEB；不访问真实设备或家庭网关；不提交/推送；保留artifacts。单通话/单媒体所有者；系统didActivate前不得启动音频；远端active不冒领；非幂等操作不自动重试；凭据仅origin限定Authorization；保留现有证书信任语义。Windows原生运行验证标NOT RUN。

## 文件地图与交接

任务1（网络/音频）：`ios/Runner/Calls/CallGatewayModels.swift`、`CallGatewayClient.swift`、`CallEventStream.swift`、`CallPCMTransport.swift`；对应 `ios/RunnerTests/CallTransportTests.swift`。精确接口见 `.xj-cursor/call-integration-2026-10-08/interfaces.md`。

任务2（系统协调）：`ios/Runner/Calls/CallKitCoordinator.swift`、`CallKitPlatform.swift`、`CallSessionChannel.swift`；对应 `ios/RunnerTests/CallCoordinatorTests.swift`。不得修改任务1或Flutter文件。

任务3（Flutter接入）：`lib/features/calls/**`、`lib/app/app_dependencies.dart`、`session_gate.dart`、`android_oneims_shell.dart`、相关 calls/app 测试；不修改Swift。

实施确认的最小接缝：任务3还负责 `lib/core/security/session_resource.dart`、`lib/features/auth/state/session_controller.dart`、`lib/core/http/gateway_io_client.dart` 及定向测试，用于登出/换源立即清理原生资源和当前源证书信任变更同步；保留原认证行为。现有 SessionGate 已持有唯一 CallsController，不需要修改它。

主代理：AppDelegate/SceneDelegate/Info.plist/project.pbxproj集成、工程契约测试、文档与回归；不与代理共写任务文件。独立责任域并行，所有对外签名先在接口文档冻结；不得回退其他人的改动。整仓Flutter运行统一由主代理安排，代理仅跑定向测试。

## 任务步骤与验收

### 1. 网关及媒体边界

- [x] 编写 XCTest：SSE分块/重复序号/截断/全量替换；URI/header/redirect/pin；PCM偶数长度/320字节重组/静音清残帧/上限。27项已编写，Windows执行为 NOT RUN，不伪造RED。
- [x] 实现接口文档定义的配置/快照模型与URLSession；成功与失败回调均落主线程，取消后不回写新实例。
- [x] 实现PCM原生WS、转换、缓冲及设备路由，未收到系统激活不启动硬件，绝不setActive。
- [x] 检查源文件接线/无token URL/无逐帧Flutter路径；报告现有可执行证据与原生NOT RUN边界。

### 2. CallKit与唯一协调器

- [x] 编写状态/系统动作XCTest：未接听零录音、double answer、终态抢先、late response、外部active、provider reset、未知结果；另补媒体认证失效、结束提示归属及连续同码动作失败。48项已编写，Windows执行为 NOT RUN。
- [x] 按接口注入gateway/media，建立单UUID/代次/owner/action完成账本，App命令只投系统事务。
- [x] 接入所有perform动作、didActivate/deactivate、系统中断/路由、前后台发现启停、认证/超时清理。
- [x] 输出schemaVersion1全量快照与Method/EventChannel；系统请求受理不能当远端成功。

### 3. Flutter原生投影和真实页面

- [x] 先扩展可执行Dart测试：iOS路径不会启动旧轮询/媒体；跨页跨卡owner不变；旧revision/畸形快照丢弃；未就绪操作禁用；全局返回入口可达。
- [x] 运行定向测试，实测新增行为失败后补原生session/config/binding、strict snapshot decode、controller分支及页面。
- [x] 复跑相同测试通过；补真实MethodChannel模拟及页面操作，不以mock自身断言代替业务状态。auth/trust双顺序竞争观察到3项真实RED，再GREEN；新登录恢复、changeOrigin、unauthorized清理也有业务断言。最终挂断提示修复另有6项真实RED→GREEN，连续同码动作失败覆盖原生pending→Flutter新结果的消费者契约。
- [x] 主代理重新执行format/analyze/全量测试；失败按根因回归修复，不更改其它代理文件。

### 4. 集成、审查和交付

- [x] 先写并运行工程契约检查，实测 4 FAIL（尚未有CallKit入口/原生生命周期/工程成员/后台音频声明），集成后同命令 4 PASS。仅静态工程检查。
- [x] 新原生coordinator在AppDelegate强持有并接messenger，SceneDelegate传生命周期；新iOS入口不注册旧CallAudioBridge执行器；补audio后台、LAN用途/有限ATS和Xcode成员。
- [x] 全仓format检查完成：18个未修改的历史文件不符合当前formatter，与HEAD逐一比较无差异，未顺带重排。本次改动16个Dart文件格式检查0变化；最终 `flutter analyze --no-pub` 无问题；`flutter test --no-pub --reporter expanded` 882项通过。
- [ ] 冻结diff；Astra独立任务规格/质量审查、deep-reviewer、final-audit；Important问题修复后再审。
- [x] 记录Mac/iPhone验收清单和源码/构建/安装/运行边界；本轮不声称未执行的iOS编译/系统通话/真实声音通过，见 `docs/ios-callkit-validation.md`。

## 进度

唯一账本：`.xj-cursor/call-integration-2026-10-08/progress.md`。已完成任务不重复派发；无新授权不commit。

最终修复后的整合验证（2026-10-08）：Flutter全套882 PASS、analyze无问题、16个修改范围Dart文件格式0变化。原生27项运输器及48项协调器测试已编写但NOT RUN。856/868/874及各次定向运行均为过程证据，不替代最终全套结果。最新复审与终审结论以本地账本为准，原生构建/真机验证仍未完成。
