package com.oneims.onewifi

import java.net.URI

internal object UpdateDownloadPolicy {
    private const val REPO = "asrtroh-netizen/OneWIFI-APK"

    fun canAuthorize(raw: String): Boolean = runCatching {
        val uri = requireHttps(raw)
        uri.host.equals("api.github.com", ignoreCase = true) &&
            uri.rawQuery == null && uri.rawFragment == null &&
            Regex("^/repos/$REPO/releases/assets/[0-9]+$").matches(uri.rawPath)
    }.getOrDefault(false)

    fun validateStart(raw: String) {
        val uri = requireHttps(raw)
        val publicAsset = uri.host.equals("github.com", ignoreCase = true) &&
            uri.rawPath.startsWith("/$REPO/releases/download/") &&
            uri.rawPath.lowercase().endsWith(".apk") && uri.rawQuery == null
        require(canAuthorize(raw) || publicAsset) { "安装包地址不受信任。" }
    }

    fun requireHttps(raw: String): URI {
        val uri = URI(raw)
        require(uri.scheme.equals("https", ignoreCase = true) &&
            !uri.host.isNullOrBlank() && uri.userInfo == null &&
            uri.port in listOf(-1, 443) && uri.rawFragment == null) {
            "安装包下载必须使用安全的 HTTPS 地址。"
        }
        return uri
    }

    fun fileVersion(raw: String): String = raw.replace(Regex("[^A-Za-z0-9._-]"), "_").take(80).ifBlank { "update" }
}
