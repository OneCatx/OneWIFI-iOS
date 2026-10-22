# OneWIFI Android 签名密钥

`onewifi-release.p12` 是 `com.oneims.onewifi` 的发布签名（PKCS12，RSA 4096，别名 `onewifi`）。

证书 SHA-256：`0F:D1:2E:4B:25:0F:87:FA:A0:55:5E:87:71:4D:53:E6:BB:2F:CF:27:43:3E:8B:D4:7E:E6:BF:3B:09:D9:D9:B0`

口令只写在 `android/key.properties`（已被 gitignore）。本目录的 `.p12` 同样被 gitignore，**不要提交、不要发到聊天或云盘**。

构建读取顺序见 `android/app/build.gradle.kts`：先 `key.properties`，再环境变量 `ONEWIFI_UPLOAD_*`。读不到就打出未签名包。

`storeFile` 相对 `android/app/`：`../signing/onewifi-release.p12`。

密钥丢失后无法给已装用户升级。仓库外仍保留一份备份目录，本树内这份只为让工程能独立出包。
