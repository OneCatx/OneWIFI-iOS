# OneWIFI Android

Standalone Android-only Flutter client for the OneWIFI WEB service.

## Requirements

- Flutter 3.44.9 / Dart 3.12.2
- JDK 17 (`JAVA_HOME`, for example `C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot`)
- Android SDK (`ANDROID_HOME`, for example `E:\sdk\Android`)
- Android API 24 or newer on device

## Service origin

The client default is `http://192.168.1.88:6699`. The WEB backend's separate
default listen address is `0.0.0.0:6688`; the client never silently falls back
between these ports. Public cleartext HTTP origins are rejected.

HTTP contract: `docs/http-api.md`.

## Development

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

## Release APK

Signing reads `android/key.properties` (local, not committed) and
`android/signing/onewifi-release.p12` (gitignored). See
`android/app/build.gradle.kts` and `android/signing/README.md`.

```powershell
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot'
$env:ANDROID_HOME = 'E:\sdk\Android'
flutter build apk --release --no-pub --obfuscate --split-debug-info=build/symbols
```

Output: `build/app/outputs/flutter-apk/app-release.apk` (arm64-v8a only via
`ndk.abiFilters`; do not also pass `--split-per-abi`, Gradle rejects both).
Copy the APK out of the tree; do not check it in. Release already runs R8 +
resource shrink. `--split-debug-info` moves Dart symbols out of `libapp.so`;
keep `build/symbols` for `flutter symbolize`. The rest of the size is the
Flutter engine in `lib/arm64-v8a/`. Private update token comes from
`android/local.properties` `github.update.token` (same as Ultra / OneTools).

## Hosting

- Source (private): `OneCatx/OneWIFI-Android`
- APK releases (private, no source): `asrtroh-netizen/OneWIFI-APK`

The in-app Settings > OneBoard > APK button opens
`https://github.com/asrtroh-netizen/OneWIFI-APK/releases/latest`.

Montserrat is distributed under the SIL Open Font License 1.1. See
`assets/fonts/OFL.txt`.

本地维护（磁盘卫生）：见 [docs/LOCAL-HYGIENE.md](docs/LOCAL-HYGIENE.md)。
