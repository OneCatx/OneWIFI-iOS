# iOS 主出包路径：GitHub Actions 未签名 IPA

**主路径 = GitHub Actions**（本机 Xcode 仅调试/签名补充，不冒充正式出包）。

版本以 `pubspec.yaml` 为准（当前 `0.1.28+33`）；`.github/workflows/ios.yml` 写死的 `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER` 必须与之同步。

## 触发 CI

Workflow：`.github/workflows/ios.yml`（job `unsigned-app`，`macos-latest`）。

1. **手动**：GitHub → 仓库 `Actions` → 左侧选 `ios` → `Run workflow`（`workflow_dispatch`）。
2. **推送**：向下列分支 `push` 即可自动跑：
   - `ios`（正式出包分支）
   - `diagnose/ios-call-tls`
   - `codex/otp-live-activity-compact-layout`

建议日常未签名 IPA 用 **`ios` 分支 push** 或对该分支 `workflow_dispatch`。

## 下载 artifact

1. 打开对应 run：`Actions` → `ios` → 选中成功的 run。
2. 页底 **Artifacts** → 下载 **`onewifi-ios-unsigned`**（内含 `OneWIFI-unsigned.ipa`，保留 14 天）。
3. 本机用自己的 provisioning profile / 证书签名后再装机（CI 产物刻意 `--no-codesign` / `CODE_SIGNING_ALLOWED=NO`）。

## 可选：发布到 OneWIFI-APK

当 run 在 `ios` 或 `diagnose/ios-call-tls` 上，且仓库 secret **`IPA_RELEASE_TOKEN`** 已配置时，workflow 会把未签名 IPA 上传到 `asrtroh-netizen/OneWIFI-APK` release；token 未设则跳过，不影响 artifact 上传。

## 本轮核对要点（P1–P4）

| 项 | 状态 |
|---|---|
| `flutter build ios --release --no-codesign` | 在 |
| OneWifiIsland 扩展单独 xcodebuild + 打进 `PlugIns` | 在 |
| artifact `onewifi-ios-unsigned` | 在 |
| `IPA_RELEASE_TOKEN` 发布 step（缺 token 则 skip） | 在 |
| 版本与 `pubspec` `0.1.28+33` 一致 | 已对齐（P4 再核未漂） |
| CallKit / APNs / Island 主路径未废除 | P4 确认保留 |
