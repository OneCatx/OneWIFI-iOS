# iOS CallKit 通话接入规格

日期：2026-10-08。基线：`ios` / `737f415`。

## 执行授权与范围

用户最新明确要求：已有 P12，不处理证书；CallKit 必须加入；推送是唯一明确的平台限制；参照 Android 当前完整通话实现，使用 Astra 子代理直接实施。以此继续已经呈现的“原生统一通话、CallKit、后台已接通音频”方向，不再等待规划往返。本文记录执行约束，不扩大为部署、推送、购买开发者服务或改动证书的授权。

实现：App 内拨号、全设备来电发现、CallKit 系统接听/拒接/挂断、应用内同一组操作、通话期间后台/锁屏音频、静音、听筒/扬声器/可用蓝牙路由、真实远端 DTMF、通话状态及全局返回入口。切页/切卡只改变展示，不结束本机通话。

不实现：APNs/PushKit、空闲后台保活、挂起/杀进程后的新来电保证、SIP 客户端、会议/保持/转接/视频、默认电话应用、通话录音。系统本身控制锁屏呈现和专注模式；不能绕过系统拒绝后伪称 CallKit 成功。后台音频仅用于真实通话，不播放静音维持待机。

本次只改 iOS 仓库；Android 和 WEB 正在其他任务中开发，只读参考。不部署网关、不接家庭设备、不修改签名/P12、不提交或推送。保留原有 `artifacts/`。

## 已核实的现状

- iOS 有可达 CallsScreen、会话级 CallsController、HTTP 呼叫控制和 Swift PCM 桥；来电发现由进入通话页选卡触发，目前无系统通话入口。
- 现有 Swift 桥自己激活音频，PCM 逐帧经过 Dart。新链路必须退出这种双控制风险；旧链路仅保留给非 iOS 路径/原有回归。
- Android 当前原生协调器已经承接 Telecom、全设备事件、PCM、静音/路由/DTMF；本次复用契约和状态约束，不复制 Android 常驻服务。
- 网关承担 SIP/IMS/RTP。`web/internal/vowifi/ims/call_runtime.go` 的 AnswerCall 对 ringing 和最终响应状态加锁检查；已 active 的其他端通话不会被本请求幂等冒领。只在明确 dial/answer 成功后取得本机 owner。
- Windows 能运行 Flutter/Dart，不能证明 Swift/Xcode/CallKit/真机声音。原生 XCTest 先写，实际执行单列 NOT RUN；可执行 Dart/桥接及工程契约检查先失败后通过，不冒称原生运行测试。

## 架构裁决

采用原生完整协调：Flutter 页面与会话配置 → 原生 CallSessionChannel → CallKitCoordinator → CallKit / CallGatewayClient / CallPCMTransport。

Flutter 负责界面、登录凭据及既有证书信任配置的唯一持久源；原生只持有当前会话的内存副本。原生负责信令、系统事务和媒体。PCM 不经过 Flutter。所有可变通话状态在主线程串行更新；网络/音频工作使用自己的串行边界，回调携带代次。

备选“Flutter 信令 + CallKit 桥”可减少 Swift 文件，但系统动作和后台通话依赖 Dart 往返，且形成两套执行入口，因此不采用。第三方 CallKit 包仍需解决同样的会话/媒体归属，且新增依赖，本轮直接使用系统框架。

## 系统动作与归属

1. 原生全局一个 CXProvider / CXCallController，本机最多一个 ringing/claiming/owned call。UUID 映射绑定 session generation、origin、deviceId、callId，不能用号码推断拥有权。
2. App 拨号/接听/挂断/静音/DTMF 都提交系统事务；perform 回调是唯一业务执行入口。request transaction 成功不是后端成功；状态快照显示实际结果。
3. 拨号先确认权限及新鲜设备状态，再发一次 dial；明确成功绑定 callId。接听先确认仍为 incoming ringing，再发一次 answer，成功且未终态才拥有通话。超时/结果未知不自动重发、不以随后看到 active 推断成功。
4. 新鲜 SSE 中出现 remote active 只显示，不连接媒体、不自动挂断。其他端先接听/远端取消则结束本地来电 UI。第二来电不抢占旧通话，不自动挂掉他端已接通通话。
5. end/reject 立即停止本机音频，向明确目标发一次 hangup；远端未确认时显示“本机已结束，远端状态待确认”，不伪报成功。
6. 每个 CallKit action 只完成一次。超时/reset/换会话后迟到结果不能 fulfill 或复活旧通话。明确已取得 owner 的迟到拨号结果可向原目标有限清理；未知归属不得盲目补偿挂断。
7. 配置 `.playAndRecord` / `.voiceChat`，但只有 `didActivate` 才允许启动通话硬件；`didDeactivate` 立即停收放音。禁止新路径自行 `setActive(true/false)` 与 CallKit 争抢。
8. 麦克风许可 = 当前 owner + 后端 active + 系统音频激活 + 用户授权。振铃不录音，early_media 只下行。静音立即清上行残帧并发送零值帧，不泄露旧声音。
9. 系统中断先停硬件、保留已证归属；只有新系统激活且当前状态仍允许才恢复。系统 reset、认证过期、登出、换源/信任变更关闭本机通话。
10. 不声明 hold/group/video 能力。DTMF 仅当前本机 active 且元数据确认支持时执行；逐键确认，不因超时重放整串。

## 网关协议与故障

- GET `/api/calls/events`：Bearer 头，SSE `event: snapshot`，data 为完整 `{devices:[{device_id,label,ready,calls:[...]}]}`。快照全量替换，ID 只在本连接递增；重连从新水位开始，不发送 Last-Event-ID，不重放过期来电。
- 状态：ringing、dialing、early_media、answering、active、ended、failed；ended_at 存在也是终态。未知状态不开放接听/媒体。终态不被旧回包覆盖。
- POST `/api/devices/{id}/calls/{dial,answer,hangup,dtmf}`；body 分别为 `{number}`、`{id}`、`{id}`、`{id,digit}`。POST 无隐式重试。号码及ID始终字符串；路径段和查询分别编码。
- GET `/api/devices/{id}/calls/media?id=...` 校验元数据后，同路径升级 WS。格式固定 `pcm_s16le_8000_mono`，上行320字节/20ms；下行只接受非空偶数长度二进制，最多6400字节。下行积压最多25个20ms块，上行待发送最多20帧；超界明确失败，不能无界堆积。
- 同设备/通话只有一个媒体连接；`call_media_busy` 不反复抢占。断流停止音频并清楚报告，不通过旧 Dart 路径抢回媒体。
- SSE 合法快照才算 ready；401/403清会话；404/501/204表明新通话服务不可用并提示后端版本，不悄悄切回旧轮询/音频。断网按1/2/4/8/16/30秒退避，合法数据/心跳保持新鲜；超过35秒无数据标 stale，禁新接听/拨号，活动通话超过20秒仍未恢复则清理本地并尽力结束已证目标。
- SSE 编码支持分块UTF-8、BOM、CR/LF、注释和多行data；单事件上限1MiB、256设备、每设备256条、总4096条。截断事件不应用。

## 安全与生命周期

- 原生 HTTP/SSE/WS 使用同一个受控 URLSession/配置；拒绝重定向，Authorization 只发当前 origin；媒体地址由固定API路径构造，不使用服务端任意URL。
- 有叶证书 pin 时校验 SHA256/有效期/绑定origin，失败不得回退CA；无pin使用系统验证。信任设置仍由既有 Dart 存储管理，原生不另存 token/pin。业务事件快照不得含 token、pin、DTMF内容或PCM；受控的原生/Flutter通话快照按界面展示和控制需要携带号码，与下文桥契约一致，不能作为诊断数据输出。诊断日志不得带凭据、完整号码、DTMF或PCM。
- 新原生通话允许 HTTPS 以及私网/回环 HTTP；公开 HTTP 提示改HTTPS，不默默开放全局 ATS。现有登录源码仅警告公开HTTP，不能将新限制冒称旧行为；不改其他业务网络策略。为本地访问声明用途和有限 ATS 本地例外，实测核对iOS26。
- 前台登录后即监听，不依赖打开通话页；空闲退后台停止监听。已呈现来电/处理中事务保留当前系统交互窗口，已有真实通话使用 audio background mode 持续。不把 SSE 或定时器当唤醒手段。
- 回前台先获取新快照再展示来电；进程重启不从持久记录恢复媒体所有权。登出/换源先清原生资源、失效旧代次；旧目标清理只能使用旧会话，不能发送新token到旧网关。

## 桥与界面

通道 `com.oneims.onewifi/call_session`，事件 `com.oneims.onewifi/call_session/events`。复用 Android 的 configure/clear/snapshot/command 结构，iOS快照附 schemaVersion=1。generation/revision 为本地排序，与SSE id分开；Flutter丢弃旧代次/旧revision。

方法：configure(origin, token, expiresAt毫秒或null, certificateFingerprint或null)、clear、snapshot、requestPermissions、dial(generation,deviceId,number)、answer/hangup(generation,deviceId,id,uuid)、mute(generation,muted,uuid)、route(generation,endpoint,uuid)、dtmf(generation,digit,uuid)。命令正常返回只表示受理；实际动作/音频状态从快照读取。针对当前通话的 UUID 在用户意图产生时捕获并由原生核对；即使同一会话里连续拨号时后端 ID 都尚为空，旧按钮/弹窗也不能操作新通话。待拨号挂断允许 ID 为空，但必须同时匹配当前本机 ID 与 UUID。

快照包含：schemaVersion、generation、revision、status、eventStatus、canReceiveCalls、foreground、permissions、devices、local、error。local 对齐 Android NativeLocalCall 的 deviceId/id/number/label/direction/phase/error/muted/audioReady/dtmfSupported/sentFrames/receivedFrames/endpoint/endpoints/startedAt，可增加 uuid/owned/actionPending。事件不含凭据。

界面保持现有风格；通话页显示监听就绪、权限、所有设备的当前通话、本机唯一通话的静音/路由/DTMF；其它页有返回通话入口。二级菜单使用现有居中 `showOneGlassPopup`。系统和App按钮读同一份状态；未协商DTMF禁用，不用按键音冒充发送成功。

## 验收与回滚

必须覆盖：冷登录来电、两入口接听只执行一次、远端取消/其他端接听、双击、跨页跨卡、旧回调、未知操作结果、登出/证书切换、无权限、无网/401/协议错、坏PCM/积压、系统中断/reset、DTMF失败、路由移除。

Flutter单测/组件测和分析须本轮新鲜通过；Swift XCTest和工程接线检查分别留证。Mac编译、匹配签名安装、iPhone双向音频/蓝牙/锁屏10分钟验证不得由Windows测试替代。源→工程成员→生成App配置→安装版本→运行轨迹逐层记账。

回滚仅在结束本机通话后成组回退新原生入口、Flutter iOS分支和配置；不在通话中自动切旧链路。无数据库迁移。已发起的外部呼叫必须单独确认终态，代码回滚不等于撤销呼叫。

## 来源

- 本地事实：`.xj-cursor/call-integration-2026-10-08/android-contract-scout.md`、`ios-entry-scout.md`、`design-analysis.md`；候选建议以本文裁决为准。
- [Apple CallKit通话流程](https://developer.apple.com/documentation/callkit/making-and-receiving-voip-calls)
- [Apple CallKit动作](https://developer.apple.com/documentation/callkit/cxcallaction)
- [Apple后台音频](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord)
- [Apple本地网络隐私](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [Apple本地ATS例外](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
