import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.isFile) {
        propertiesFile.inputStream().use { load(it) }
    }
}

// 签名凭据只从两处读取：android/key.properties（已被 gitignore）或环境变量
// ONEWIFI_UPLOAD_*。密钥本体在 android/signing/（.p12 已被 gitignore）。
// 读不到凭据时宁可产出未签名包，也不用任何硬编码回退制造「已签名」的假象。
fun signingValue(prefix: String, key: String): String? {
    val propertyValue = signingProperties.getProperty("$prefix.$key")
    if (!propertyValue.isNullOrBlank()) {
        return propertyValue
    }
    val envKey = "ONEWIFI_${prefix.uppercase()}_${
        key.replace(Regex("([a-z])([A-Z])"), "$1_$2").uppercase()
    }"
    return System.getenv(envKey)?.takeIf { it.isNotBlank() }
}

fun hasSigningValues(prefix: String): Boolean {
    return listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .all { !signingValue(prefix, it).isNullOrBlank() }
}

fun readLocalProp(key: String): String? {
    val file = rootProject.file("local.properties")
    if (!file.isFile) return null
    return file.readLines()
        .map { it.trim() }
        .firstOrNull { it.startsWith("$key=") }
        ?.substringAfter("=", "")
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
}

android {
    namespace = "com.oneims.onewifi"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.oneims.onewifi"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val activationBaseUrl = (
            readLocalProp("onewifi.activationBaseUrl")
                ?: System.getenv("ONEWIFI_ACTIVATION_URL")
                ?: "https://47.103.206.115"
        ).trimEnd('/')
        val payloadCryptoKey = readLocalProp("onewifi.payloadCryptoKey")
            ?: System.getenv("ONEWIFI_PAYLOAD_CRYPTO_KEY")
            ?: ""
        val activationSpkiPin = readLocalProp("onewifi.activationSpkiPin")
            ?: System.getenv("ONEWIFI_ACTIVATION_SPKI_PIN")
            ?: ""
        // 私有 APK 仓读取令牌，对齐 Ultra / OneTools：只从 local.properties / 环境变量注入。
        val githubUpdateToken = readLocalProp("github.update.token")
            ?: System.getenv("GITHUB_UPDATE_TOKEN")
            ?: ""
        fun escapeField(value: String) = value.replace("\\", "\\\\").replace("\"", "\\\"")
        buildConfigField("String", "ONE_ACTIVATION_BASE_URL", "\"${escapeField(activationBaseUrl)}\"")
        buildConfigField("String", "PAYLOAD_CRYPTO_KEY", "\"${escapeField(payloadCryptoKey)}\"")
        buildConfigField("String", "ACTIVATION_SPKI_PIN", "\"${escapeField(activationSpkiPin)}\"")
        buildConfigField("String", "GITHUB_UPDATE_TOKEN", "\"${escapeField(githubUpdateToken)}\"")
        ndk {
            // Sideload 只发 arm64。三 ABI 胖包里约 50MB 是未压缩 .so；
            // R8 只裁 dex（本包 classes.dex 已压到 <1MB），裁不掉 Flutter 引擎。
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    signingConfigs {
        create("upload") {
            signingValue("upload", "storeFile")?.let { storeFile = file(it) }
            storePassword = signingValue("upload", "storePassword")
            keyAlias = signingValue("upload", "keyAlias")
            keyPassword = signingValue("upload", "keyPassword")
        }
    }

    buildTypes {
        release {
            // Dart 代码 AOT 进 libapp.so，R8 只作用于 Android 侧 dex；开启的目的是
            // 裁掉未用到的 AndroidX/插件代码并抬高原生侧逆向门槛。keep 规则见
            // proguard-rules.pro。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            if (hasSigningValues("upload")) {
                signingConfig = signingConfigs.getByName("upload")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.security:security-crypto:1.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}
