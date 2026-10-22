# 2026-09-07 · 界面文案全部中文化

README 一直写着「本包界面仍是简体中文」，但登录页整页、状态门面的胶囊/阶段标签、
错误提示表和登录地址校验报错还是英文。本次把这些用户可见的英文全部改为中文，
不改任何行为。

- 登录页：`Sign in` → 登录、`Host / IP` → 主机 / IP、`Your session expired` → 登录已过期，请重新登录 等 15 条
- 状态门面（`OneStatusHero` 门面层）：`Ready` → 就绪、`Alert` → 注意、`Working` → 处理中、`Off` → 关闭
- `StateFailure.message` 11 条（如 `The service could not be reached.` → 无法连接到服务。）
- `BaseUrlPolicy` 校验报错 9 条（如 `Port must be between 1 and 65535.` → 端口范围 1–65535。）
- 概览缺省值 `Not reported` → 未上报；短信发送者 `Me` → 我、`Received a system SMS` → 收到一条系统短信

刻意保留英文：`HTTPS`、通知通道字段名（Bot token / Chat ID / Webhook URL 等第三方术语）、
语言切换项 `English` 及网关语言设为英文时的 `Language saved`、eUICC 厂商名；
开发者才会看到的 `StateError` / `ArgumentError` 文本不动。

顺带：`LoginForm` 的 7 个测试 Key 合成 `LoginFormKeys` 记录；设置页 HTTPS 一节抽成
`SettingsHttpsTiles`；`deviceTypeLabel` 私有化。

验证：`dart format` 189/0、`flutter analyze` 0 issues、`flutter test` 559/559
（9 个测试文件仅更新期望文本，用例数不变）。真机窄屏换行未验证。
