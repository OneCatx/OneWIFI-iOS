package com.oneims.onewifi

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.oneims.onewifi.activation.ActivationChannelHandler
import com.oneims.onewifi.activation.ActivationStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val otpCoordinator = OtpNotificationCoordinator(
        hasPermission = ::hasNotificationPermission,
        requestPermission = {
            if (Build.VERSION.SDK_INT >= 33) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), OTP_PERMISSION_REQUEST)
            }
        },
        post = ::postOtp,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OTP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        val code = call.argument<String>("code").orEmpty()
                        if (code.isBlank()) {
                            result.error("invalid_otp", "code is required", null)
                            return@setMethodCallHandler
                        }
                        otpCoordinator.show(
                            OtpMessage(
                                code = code,
                                sender = call.argument<String>("sender").orEmpty(),
                                device = call.argument<String>("device").orEmpty(),
                            ),
                        ) { submitted -> result.success(submitted) }
                    }
                    "cancel" -> {
                        otpCoordinator.cancel()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "githubToken" -> result.success(BuildConfig.GITHUB_UPDATE_TOKEN.trim())
                    "downloadAndInstall" -> {
                        val url = call.argument<String>("url").orEmpty()
                        val version = call.argument<String>("version").orEmpty()
                        if (url.isBlank()) {
                            result.error("invalid_url", "url is required", null)
                            return@setMethodCallHandler
                        }
                        BoardUpdateInstaller.downloadAndInstall(
                            this,
                            url,
                            version,
                            BuildConfig.GITHUB_UPDATE_TOKEN.trim(),
                            result,
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        ActivationChannelHandler(this).register(flutterEngine.dartExecutor.binaryMessenger)
        Thread({ ActivationStore.warm(applicationContext) }, "onewifi-activation-warm").start()
    }

    private fun postOtp(message: OtpMessage): Boolean {
        if (!hasNotificationPermission()) return false
        ensureChannel()
        val manager = NotificationManagerCompat.from(this)
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = getSystemService(NotificationManager::class.java)?.getNotificationChannel(CHANNEL_ID)
            if (channel == null || channel.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        val launch = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val content = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val subtitle = listOf(message.sender, message.device).filter { it.isNotBlank() }.joinToString(" · ")
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_otp)
            .setContentTitle(message.code)
            .setContentText(if (subtitle.isBlank()) "验证码" else subtitle)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message.code))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_SOUND)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(content)
            .build()
        return try {
            manager.notify(OTP_NOTIFICATION_ID, notification)
            true
        } catch (_: SecurityException) {
            // Permission can be revoked between the check above and notify().
            false
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "验证码",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "模组短信里抽出的验证码"
            },
        )
    }

    private fun hasNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == OTP_PERMISSION_REQUEST) {
            val index = permissions.indexOf(Manifest.permission.POST_NOTIFICATIONS)
            otpCoordinator.onPermissionResult(
                index >= 0 && grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED,
            )
        }
    }

    override fun onDestroy() {
        otpCoordinator.destroy()
        super.onDestroy()
    }

    private companion object {
        const val OTP_CHANNEL = "com.oneims.onewifi/otp"
        const val UPDATE_CHANNEL = "com.oneims.onewifi/update"
        const val CHANNEL_ID = "onewifi.otp"
        const val OTP_NOTIFICATION_ID = 61
        const val OTP_PERMISSION_REQUEST = 61
    }
}
