# 追加在 Flutter SDK 自带的 flutter_proguard_rules.pro 之后。
#
# Dart 代码不在 R8 作用范围内（AOT 编译进 libapp.so），这里只影响 Android 侧类：
# MainActivity 与几个 Flutter 插件（flutter_secure_storage、
# shared_preferences 自带 consumer 规则）。

# ── 本应用的原生入口 ──
# MainActivity 由 AndroidManifest 按类名引用，没有反射。整体保留是因为这批代码
# 不到几百行，混淆省下的体积可以忽略。
-keep class com.oneims.onewifi.** { *; }

# OkHttp（激活客户端）。R8 全量压缩时这些可选平台实现不在运行时 classpath。
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# ── 崩溃栈可读性 ──
# 保留行号并统一源文件名，便于按 build/app/outputs/mapping/release/mapping.txt
# 还原线上崩溃栈。
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
