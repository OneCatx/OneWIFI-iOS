# OneWIFI HTTP API

OneTools 内部调用契约（ONESIM / OneBoard / Android / PC）。

本仓库 `docs/OneWIFI-HTTP-API.md` 是 HTTP 契约真源；实现在 `internal/server`。Android 客户端另有副本（同级 `onewifi-android/docs/http-api.md`）。不要再对照 MDD，也不要带 `X-MDD-CSRF-Token`。

默认监听 `0.0.0.0:6688`（`ONEWIFI_ADDR`）。官方安装：`/opt/onewifi/bin/onewifi`，数据 `/opt/onewifi/data/onewifi.db`，环境 `/etc/onewifi/env`。进程要用 `onewifi serve`，不要无参进交互菜单。

JSON 写请求：`Content-Type: application/json`；未知字段会被拒绝（`DisallowUnknownFields`）。默认请求体上限 1 MiB。

短信、设备、VoWiFi 状态靠 HTTP 轮询或指定 SSE，**没有**总总线 WebSocket。

## 信封

成功（除 `/healthz`、`/readyz`、`/metrics` 外）：

```json
{ "data": { } }
```

失败：

```json
{ "error": { "code": "unauthorized", "message": "authentication is required" } }
```

常见码：`unauthorized` 401、`invalid_csrf` 403、`invalid_credentials` 401、`too_many_attempts` 429、`not_found` 404、`method_not_allowed` 405、`invalid_request` 400。

## 鉴权

| 客户端 | 怎么带钥匙 | 写操作（非 GET/HEAD/OPTIONS） |
|---|---|---|
| 同源浏览器 | Cookie `onewifi_session` + 头 `X-CSRF-Token`（与 Cookie `onewifi_csrf` 双提交） | CSRF 必过 |
| 安卓 / PC / 其它产品 | `Authorization: Bearer <session_token>` | **不要** CSRF。**不要**同时带会话 Cookie，否则仍走 CSRF |

`sessionToken` **先 Cookie 后 Bearer**。Cookie 在时，多带一个伪造 Bearer **不能**跳过 CSRF。

Bearer 拉 `GET /api/auth/session` **不会**轮换库里的 CSRF（避免手机轮询废掉浏览器标签）。仅 Bearer 的 session 响应也没有 `csrf_token`。

Cookie：`SameSite=Strict`，`HttpOnly` 只管 session；CSRF cookie 可读。HTTPS 模式下 `Secure`。

原生客户端最小路径：

```http
POST /api/auth/login
Content-Type: application/json

{"username":"admin","password":"..."}
```

之后每次请求带 `Authorization: Bearer <session_token>`，不要再带 `Cookie`。

```http
GET /api/devices
Authorization: Bearer <session_token>
```

写操作同样只带 Bearer，不要 `X-CSRF-Token`。

### `POST /api/auth/login`

```json
{ "username": "admin", "password": "..." }
```

成功 `data`：`user`、`csrf_token`、`session_token`、`expires_at`、`authenticated`、`status`。`session_token` 只给客户端存，不进普通日志。浏览器仍会收到 Cookie。

### `GET /api/auth/session`

Cookie 会话：`data` 含 `user`、`csrf_token`、`session_token`、`expires_at`、`authenticated`。

### `POST /api/auth/logout`

Cookie 要 CSRF；仅 Bearer 可直接登出。成功 `{"data":{"logged_out":true}}`。

### 公开探活（不登录）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/healthz` | `{ "status": "ok" }`（不是 `data` 信封） |
| GET | `/readyz` | `{ "status": "ready" }` 或 503 `not_ready` |
| GET | `/api/health` | 鉴权前；库可用时 `data.status=ok` |
| GET | `/metrics` | Prometheus 文本，`onewifi_*`，无设备/SIM 标识 |
| GET | `/api/settings/preferences` | 未登录可读 UI 语言，供登录页 |

### CORS

空配置：只反射局域网 / loopback / `localhost` Origin，带 Credentials。`ONEWIFI_CORS_ORIGINS` CSV 白名单覆盖默认。禁止 `*`。允许头：`Authorization, Content-Type, X-CSRF-Token`。

## 产品授权

同一张阿里云 `product=onewifi` 码占两席：`client_kind=router`（本网关）+ `android`（手机 App）。售卖入口仍是设置页「向销售获取」；飞牛发卡后再核销。网关把码交给阿里云，授权落在 `app_settings.product.license`，不绑浏览器。

- `GET /api/license` → `{activated, code, edition, client_kind}`（不含 token）
- `POST /api/license` `{ "code": "XXXX-XXXX-XXXX-XXXX" }` 占软路由席
- `DELETE /api/license` 只清本机，不触网

环境变量 `ONEWIFI_ACTIVATION_URL` 默认 `https://47.103.206.115`。

## 设备

- `GET /api/devices` → `data.device_limit`、`data.devices`
- `GET /api/dashboard/devices`、`GET /api/dashboard/host`
- `GET /api/devices/discovered`
- `POST /api/devices/actions/rescan`
- `POST /api/devices` body `{ "config": { ... } }` 登记模组
- `PATCH /api/devices/{id}` 局部字段；`PUT` 写完整 `config`；`DELETE` 只删登记，不碰物理模组
- **没有** `GET /api/devices/{id}`（405）。读详情：`GET …/overview` 或 `GET …/status` 或 `GET …/config`
- `GET /api/devices/{id}/overview`、`GET …/status`、`GET …/config`
- `GET /api/devices/{id}/overview/stream` SSE
- `POST /api/device-mgmt/discovered/fix-usbnet`（发现态 USB 网卡修复）
- `POST /api/devices/{id}/actions/refresh`
- `POST /api/devices/{id}/actions/at`、`…/actions/ussd`、`…/ussd/continue`、`…/ussd/cancel`
- `POST /api/devices/{id}/actions/reboot`（OpenStick 410 不支持）
- `GET|PATCH /api/devices/{id}/flight-mode`
- `GET|PATCH /api/devices/{id}/network`
- `GET /api/devices/{id}/network/apns`
- `GET /api/devices/{id}/network/public-ip`
- `GET|PATCH /api/devices/{id}/usbnet-mode`
- `GET|PUT /api/devices/{id}/operator_selection`；`POST …/reregister`；`GET …/scan`；`GET …/scan/stream`
- `PATCH /api/devices/{id}/vowifi` body `{ "enabled": true }`
- `POST /api/devices/{id}/vowifi/actions/reconnect`
- `GET /api/devices/{id}/vowifi/e911/websheet`（E911 网页）
- `GET /api/devices/{id}/calls` → `{ calls: [...] }`
- `POST /api/devices/{id}/calls/dial` `{ "number": "+4477…" }`
- `POST /api/devices/{id}/calls/answer` `{ "id": "…" }`
- `POST /api/devices/{id}/calls/hangup` `{ "id": "…" }`
- `POST /api/devices/{id}/calls/dtmf` `{ "id": "…", "digit": "1" }` → `data.sent=true`。仅接通且协商 telephone-event 的通话可用；每次一个 `0–9 * # A–D` 字符，不自动重放失败按键。
- `GET /api/devices/{id}/calls/media?id=` → `data: { id, codec, format, stream, dtmf }`。`dtmf` 表示是否协商了远端按键音。同一 URL 带 `Upgrade: websocket` 时升级为二进制 PCM 通道（`pcm_s16le_8000_mono`，320 字节/20 ms 帧）。JSON 探测仍返回元数据。浏览器 `WebSocket()` 不能带 `Authorization`：分源或仅 Bearer 会话可在升级请求上使用 `access_token` 查询参数，或 `Sec-WebSocket-Protocol: bearer.<session>`。Cookie 会话仍走同源 Cookie。iOS 原生 HTTP/SSE/WS **始终只用 Authorization 头**，不把 token 放 URL，不带 Cookie。通话错误码：`invalid_dial_number`、`invalid_call_id`、`call_not_found`、`call_state`、`vowifi_runtime_unavailable`、`dtmf_unavailable`、`call_media_busy`。同一设备/通话的媒体只允许一个连接，占用返回 409，不自动重连争抢。已结束通话再 hangup 视为成功。

USB SIM 读卡器没有蜂窝 AT / 选网 / 重启；走 WiFi Calling + IMS 短信。410 没有 AT 重启。

### iOS 原生全局通话订阅

`GET /api/calls/events`，Bearer 鉴权，返回 `text/event-stream`。`event: snapshot` 的 data 是直接的 `{ "devices": [...] }`（这里**不套 HTTP 的 data 信封**）。每项包含 `device_id`、`label`、`ready`、`calls`；每个事件全量替换设备/通话视图。状态包含 `ringing`、`dialing`、`early_media`、`answering`、`active`、`ended`、`failed`，`media_ready` 未出现时视为 false。

事件 id 只在本连接中递增；重连取得当前快照，不发送 Last-Event-ID，不回放旧来电。无变化时服务端约每 15 秒发送注释心跳。iOS 在首份合法快照前不开放新拨号/接听；服务缺失或协议不兼容时明确提示，不回退到旧轮询/旧音频执行器。上述扩展要求网关已部署相应接口，客户端源码集成不代表网关已经升级。

iOS 对临时 HTTP 408/429 及 5xx（501 除外）沿用封顶退避重连。数字秒数形式的 `Retry-After` 在 30 秒上限内作为最小延迟；HTTP-date 或无效值沿用原退避。401/403 使认证失效；204/404/501 表示通话事件服务不可用；错误响应类型、畸形快照和 TLS/ATS 错误停止自动重试。用户主动刷新只重建事件订阅，不重放拨号、接听、挂断或 DTMF 请求。

原生到 Flutter 的本地快照保持 `schemaVersion=1`，新增可选字符串 `eventError`（缺失为 `""`），用于固定的监听错误分类；它不是网关 SSE 数据字段，也不替代已有通话 `error`。本地 `refreshEvents` 命令沿用当前认证与 `generation` 校验；不更换会话、不清理终态历史、不延长活动通话的离线安全期限。新命令须随同版本 Dart/Swift 一起构建。

只有本机明确 dial/answer 成功才取得媒体归属。发现其他端已经 active 的通话仅展示，不自动连接或挂断。App 与系统 CallKit 操作共用原生状态；真正的通话音频由 CallKit 系统激活控制。空闲退后台停止订阅；已接通通话使用后台音频模式。未接 APNs/PushKit，不能保证 App 挂起或退出后收到新来电。

## eSIM

前缀 `/api/devices/{id}/esim`

- `GET …/esim` 概览（含缓存的 eUICC 铭牌）
- `GET …/esim/profiles`
- `PATCH …/esim/profiles/{iccid}` 改名
- `DELETE …/esim/profiles/{iccid}`
- `POST …/esim/actions/switch` `{ "iccid": "…", "aid_hex" 或 "aidHex" }`
- `POST …/esim/actions/disable`
- `POST …/esim/actions/download` SSE（`Accept: text/event-stream`），body 含 `smdp`、`matching_id` 等
- `GET …/esim/notifications`
- `POST …/esim/notifications/{seq}/actions/retry`

切卡是高副作用。内部客户端不要对实验室设备乱 POST。

## 短信

- `GET /api/sms/contacts?device_id=&limit=`
- `GET /api/sms/thread?device_id=&peer=&imsi=&iccid=`
- `POST /api/sms/send` `{ "device_id", "phone", "message" }`（`device_id` 必填）
- `DELETE /api/sms/messages/{id}`
- `GET|PUT /api/settings/sms` → `{auto_clear_modem_storage}`，缺省开启。同步入库成功后删除模组 SM/ME 副本，网页记录保留；未匹配的送达报告不删。设备概览可带 `sms_storage: {sm,me}`（`used`/`total`）。
- `GET|PUT /api/settings/vowifi` → `{mtu_compatibility}`，缺省 false。全局，保存后重连 VoWiFi 才生效。PUT 必须带该字段。
- `GET /api/onetools/sms/stream` SSE。鉴权：`Authorization: Bearer <配对令牌>`（**不是** session）。这条路由在 `requireAuthenticated` **之前**，浏览器 Cookie 进不来。渠道关 → 403 `channel_disabled`；令牌错 / 没带 → 401。事件：`connected`、`sms`（`{deviceId, deviceLabel, number, content, atMs}`）。`deviceLabel` 是卡备注（eSIM nickname），没有则退回设备名。服务端不抽码，只推入库短信正文。
- 配对令牌在 `GET|PUT /api/settings/notifications` 的 `onetools` 渠道（字段 `pairing_token`，另有非密钥 `public_base_url` 作出门配对用的公网基址）。GET 脱敏令牌成 `********`；渠道启用且库里还没有令牌时签发。轮换令牌会踢掉现有 SSE。网页出示两种配对码（链接 `onetools://onewifi?u=&t=`、JSON `{v,u,t}`），手机粘贴，没有扫码。
- `GET|POST /api/settings/notifications/onetools/pairing`（需登录）。GET 按**这次请求的 Host**（或 `X-Forwarded-*`）填 URI 的 `u=`；公网地址由网页用 `public_base_url` 改写 `u=`，不轮换令牌。POST 轮换令牌。

OpenStick 410 原生后端不提供这条 SMS API。WiFi Calling 就绪时走 IMS SMS，否则蜂窝。

## 保号任务

- `GET|POST /api/automatic-tasks`
- `GET /api/automatic-tasks/runs`
- `GET|PUT|DELETE /api/automatic-tasks/{id}`
- `POST /api/automatic-tasks/{id}/run`

`task_type` 接受 `sms`、`call`、`public_ip`（`public_ip` 还要开发者模式 + `environment=cellular`）。`call` 必须 `environment=vowifi`，payload 含 `phone` 与可选 `duration_seconds`（默认 10，范围 5–60）。

USB SIM 读卡器只能 `environment=vowifi` + `sms` 或 `call`。

## 卡策略 / APN

- `GET /api/cards/policies`
- `GET|PUT /api/cards/{iccid}/policy`（`ip_version` 用 `IP` / `IPV6` / `IPV4V6`，不是 `v4/v6`；可选 `mbn_profile`，省略键=不改库，空串/`auto`=自动）
- `GET|POST|PATCH|DELETE /api/cards/{iccid}/apns`、`…/apns/{id}`

## 上游代理

- `GET|POST /api/upstream-proxies`
- `GET|PUT|DELETE /api/upstream-proxies/{id}`
- `POST /api/upstream-proxies/{id}/actions/probe`
- `GET|PUT /api/upstream-proxy-probe`
- `GET /api/upstream-proxy-countries`
- `GET|POST /api/upstream-proxy-country-rules`；单条 `…/{code}`
- `GET|PUT /api/upstream-proxy-profile-bindings`

## 出口代理（开发者模式）

`GET|POST /api/export-proxies`、`GET /api/export-proxies/status`、`PUT|DELETE /api/export-proxies/{id}`。未开开发者模式 → 403 `developer_mode_required`。

## 系统 / 设置

- `GET /api/system/info` → `version`、`build_time`、`os`、`architecture`、`uptime`、`developer` 等（没有单独 `/api/version`）
- `GET /api/system/update/check`、`POST /api/system/update/apply`
- `GET|PUT /api/settings/developer-mode` → `{enabled, plugins_need_restart}`。已登录即可开关；漫游数据立刻生效。插件 / 出口代理仍要重启进程。`onewifi develop on|off` 写同一份库。
- `GET|PUT /api/settings/notifications`；渠道含 `onetools`（`pairing_token`、`public_base_url`）。`GET|POST /api/settings/notifications/onetools/pairing`。`POST /api/settings/notifications/{channel}/test`
- `GET /api/traffic/analysis`
- `GET /api/logs/history`、`GET /api/logs/stream`
- `GET /api/extensions`；安装 URL / 上传包；`PUT|DELETE /api/extensions/{id}`；`/api/extensions/{id}/backend` 反代

## 明确不做

- `/ws` 总总线（历史方言，已移除）
- 把大整数 ID 当 JS number；ICCID / IMEI / IMSI 一律当字符串

## 以后要出的 Linux 资产名（先不编）

本轮**不构建、不打包、不上传**。以后 Release 文件名按自更新 `assetNamesFor`：

| 用户要的架构 | Release 文件名 | 备注 |
|---|---|---|
| linux-386 | `onewifi-linux-386` | |
| linux-amd64 | `onewifi-linux-amd64` | |
| linux-arm64 | `onewifi-linux-arm64` | 首选 |
| linux-aarch64 | `onewifi-linux-aarch64` | 与 arm64 同指令集；自更新在 arm64 主机上把它当备选名 |
| linux-armv7 | `onewifi-linux-armv7` | 另认旧名 `onewifi-linux-arm` |
