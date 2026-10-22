# iOS / Android 与 Web 对接（2026-10-09）

对照物：`web` 融合部署版（arm64，APNs P8 已上服务器）。

## 1. 苹果推送（已部署）

服务器 `/etc/onewifi/env` 已配置：

| 项 | 值 |
|---|---|
| 环境 | `sandbox`（与 development 描述文件一致，**勿改 production**） |
| Bundle | `Wifi.call.one` |
| Key ID / Team | `R5823PPPP2` / `BR643MG9NV` |
| 私钥 | `/etc/onewifi/apns/AuthKey.p8`（600） |

启动日志应有：

- `APNs configuration enabled` environment=sandbox
- `APNs VoIP push enabled` environment=sandbox

App 侧登记端点（与 Web 一致，**无需改**）：

- 短信 APNs：`PUT /api/onetools/ios/push-endpoint` + `POST …/ack`
- PushKit VoIP：`POST /api/calls/push`（topic `Wifi.call.one.voip`）

## 2. 验证码上岛（灵动岛）

- 已加 `ios/Runner/OtpLiveActivity.swift`（ActivityKit 启停）。
- **已补全** `ios/OneWifiIsland` Widget Extension（Live Activity UI）并挂进 `Runner.xcodeproj`：
  - `OneWifiIslandBundle.swift` / `OtpLiveActivityWidget.swift` / `Info.plist` / entitlements
  - 共享 `ios/Shared/OtpActivityAttributes.swift`（App + Extension 同编）
  - Runner 以 **Embed App Extensions** 嵌入 `OneWifiIsland.appex`
- CI（`.github/workflows/ios.yml`）会编 Runner 并校验 `PlugIns/OneWifiIsland.appex` 是否打进包。
- `OtpNotifier.show` 会启动 Live Activity，失败回退本地通知横幅 + 复制。

GitHub `macos-latest` 可编：`flutter build ios --release --no-codesign` + `xcodebuild … CODE_SIGNING_ALLOWED=NO`，扩展随 Runner 一起编出，签名由你本地做。

## 3. Android

- 推送正常，**不需要改**。
- OTP 配对走 `/api/onetools/sms/stream`，Web 仍在。
- 未使用多待 / 通话历史新 API，无兼容问题。

## 4. Web 新增能力（App 可选接）

| API | 用途 | App |
|---|---|---|
| `GET …/calls/history` | 持久通话记录（尾号） | iOS/Android 可加「历史」 |
| `GET …/calls/history/export` | CSV 导出 | 同上 |
| `/api/multistandby/*` | 实验区，默认 403 | 勿默认接 |
| `/api/settings/experimental` | 实验区开关 | 设置页可选 |

## 5. 验收

1. iPhone 登录后，日志出现 token 登记，短信/APNs sandbox 可达。
2. 来电 PushKit 唤起 CallKit（IPA `0.1.45` / build 50）。
3. 验证码：有扩展则上灵动岛，无扩展则横幅可复制。
4. Android 短信推送保持现状。
