package com.oneims.onewifi

import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** File transfer boundary, independent of the Android installation UI. */
internal object UpdateApkDownload {
    fun download(
        directory: File,
        startUrl: String,
        versionName: String,
        githubToken: String,
        openConnection: (String) -> HttpURLConnection = { URL(it).openConnection() as HttpURLConnection },
    ): File {
        UpdateDownloadPolicy.validateStart(startUrl)
        val token = githubToken.trim()
        require(!token.any { it.isWhitespace() }) { "更新凭据无效。" }
        directory.mkdirs()
        val apk = File(directory, "OneWIFI-v${UpdateDownloadPolicy.fileVersion(versionName)}.apk")
        val part = File.createTempFile("onewifi-", ".part", directory)
        var current = startUrl
        var sendAuth = token.isNotEmpty() && UpdateDownloadPolicy.canAuthorize(startUrl)
        try {
            repeat(8) {
                UpdateDownloadPolicy.requireHttps(current)
                val connection = openConnection(current).apply {
                    instanceFollowRedirects = false
                    connectTimeout = 20_000
                    readTimeout = 60_000
                    setRequestProperty("User-Agent", "OneWIFI-Update")
                    setRequestProperty("Accept", "application/octet-stream")
                    if (sendAuth) {
                        setRequestProperty("Authorization", "Bearer $token")
                    }
                }
                try {
                    val code = connection.responseCode
                    if (code in 300..399) {
                        val location = connection.getHeaderField("Location") ?: error("下载被重定向，但没有地址")
                        current = URL(URL(current), location).toString()
                        sendAuth = false
                        UpdateDownloadPolicy.requireHttps(current)
                        return@repeat
                    }
                    if (code != HttpURLConnection.HTTP_OK) error("下载失败（$code）")
                    connection.inputStream.use { input -> part.outputStream().use { output -> input.copyTo(output) } }
                    if (!part.isFile || part.length() < 1024L) error("下载的安装包不完整")
                    if (apk.exists() && !apk.delete()) error("无法替换旧安装包")
                    if (!part.renameTo(apk)) error("无法保存安装包")
                    return apk
                } finally {
                    connection.disconnect()
                }
            }
            error("下载失败：重定向过多")
        } finally {
            if (part.exists()) part.delete()
        }
    }
}
