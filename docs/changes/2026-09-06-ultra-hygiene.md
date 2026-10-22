# 2026-09-06 · 本地干净契约

本轮只加本地干净契约：新建 `docs/LOCAL-HYGIENE.md`，根 README 加一行链接。

- 不 `git init`（本机已有 `.git`）
- 卫生三文件单独 commit；message：`docs: add local hygiene contract for Ultra parent`
- 不 `git push`（含禁止 `git push origin`）
- 不 amend 父提交 `416eaee`
- 不改 Dart / Kotlin
- 不改发版命令与 GitHub 仓名
- 不改 `.gitignore`（已有 `*.apk` `*.p12`）
- 不移动 `android/signing/onewifi-release.p12`
- 不 `git add` `*.p12` / `*.apk` / `android/signing/`
