# 本地维护

## 本地干净（E:\GQ\Ultra）

### 这是什么

独立 Android-only 客户端。工作目录 `E:\GQ\Ultra\onewifi-android`。包名 `com.oneims.onewifi`。不是 `onewifi-app` 的副本，文件清单对比后仍是独立产品，保留、不改名、不归档。

### 真源

git 根就是本目录：`E:\GQ\Ultra\onewifi-android`。本机有 `.git`。README 写的源码仓 `OneCatx/OneWIFI-Android` 与本机 `origin` 一致。上级 `E:\GQ\Ultra` 不是 git 仓，不能对整个 Ultra 做 `git init`。不要对本目录再 `git init`。

### 远端

- `origin` → https://github.com/OneCatx/OneWIFI-Android.git（私有源码）。父提交 `416eaee` 是既有 arm64 出包，不是本卫生任务；禁止 amend。卫生契约单独本地 commit。**禁止 git push**（含禁止 `git push origin`）。
- APK：`asrtroh-netizen/OneWIFI-APK`。源码仓不存正式 APK。

### 上级地图

`E:\GQ\Ultra\README.md` 分类 **A. 产品仓（有 git）**。路径仍 `E:\GQ\Ultra\onewifi-android`。不改名、不归档。

### 根目录允许

源码与工程文件可留在仓根，例如：

- `E:\GQ\Ultra\onewifi-android\README.md`
- `E:\GQ\Ultra\onewifi-android\pubspec.yaml`、`analysis_options.yaml`
- `E:\GQ\Ultra\onewifi-android\lib\`
- `E:\GQ\Ultra\onewifi-android\test\`
- `E:\GQ\Ultra\onewifi-android\docs\`
- `E:\GQ\Ultra\onewifi-android\android\`
- `E:\GQ\Ultra\onewifi-android\assets\`

### 根目录禁止

- `*.apk`（gitignore，不入库）
- 把 `build\` 当交付物
- 提交 `*.p12` / `key.properties`
- 改名或 move 到 `_archive`

### 产物落点

`E:\GQ\Ultra\onewifi-android\build\app\outputs\flutter-apk\`。拷出后不要入库。不要堆回 `E:\GQ\Ultra\` 根。

### 密钥

已 gitignore、永不提交：

- `E:\GQ\Ultra\onewifi-android\android\signing\onewifi-release.p12`（工作副本）
- `E:\GQ\Ultra\onewifi-android\android\key.properties`
- 仓外备份 `E:\GQ\Ultra\onewifi-signing\`

丢失则无法给已装用户升级。不要在本文写口令。不要挪 p12。

### 不要堆回上级

不要在 `E:\GQ\Ultra\` 根再放本项目的 APK / 文档 / zip。整盘备份 `E:\GQ\Ultra\Ultra.zip` 不是本项目产物、不要删。不要把本目录改名或归档。

### 日常怎么收

1. 不要 `git push origin`
2. `git status`：仓根没有 `*.apk`，没有把 p12 从 gitignore 拿掉
3. 产物只看 `build\app\outputs\flutter-apk\`，不要入库
4. 工作副本密钥留在 `android\signing\`；仓外备份留在 `onewifi-signing\`
5. 不要改名、不要归档
6. 新垃圾不要丢到 `E:\GQ\Ultra\` 根
