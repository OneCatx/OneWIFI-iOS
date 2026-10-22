package com.oneims.onewifi

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

object BoardUpdateInstaller {
    private val io = Executors.newSingleThreadExecutor()

    fun downloadAndInstall(
        context: Context,
        url: String,
        versionName: String,
        githubToken: String,
        result: MethodChannel.Result,
    ) {
        val app = context.applicationContext
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !app.packageManager.canRequestPackageInstalls()
        ) {
            app.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:${app.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.error("need_permission", "请允许本应用安装未知应用，然后再点更新", null)
            return
        }
        io.execute {
            try {
                val apk = UpdateApkDownload.download(File(app.cacheDir, "updates"), url, versionName, githubToken)
                val apkUri = FileProvider.getUriForFile(
                    app,
                    "${app.packageName}.files",
                    apk,
                )
                val install = Intent(Intent.ACTION_VIEW)
                    .setDataAndType(apkUri, "application/vnd.android.package-archive")
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                app.startActivity(install)
                result.success(null)
            } catch (error: Exception) {
                result.error(
                    "download_failed",
                    "下载失败，请检查网络。",
                    null,
                )
            }
        }
    }

}
