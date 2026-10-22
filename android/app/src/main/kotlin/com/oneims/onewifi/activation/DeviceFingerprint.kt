package com.oneims.onewifi.activation

import android.annotation.SuppressLint
import android.content.Context
import android.media.MediaDrm
import android.os.Build
import android.provider.Settings
import android.util.Log
import java.security.MessageDigest
import java.util.UUID

/**
 * 版本化设备指纹。v2 主指纹避开 Widevine；旧算法仅作受控迁移候选。
 */
object DeviceFingerprint {

    private const val TAG = "OneWifi-Fingerprint"

    private val WIDEVINE_UUID: UUID =
        UUID.fromString("edef8ba9-79d6-4ace-a3c8-27dcd51d21ed")

    @Volatile
    private var cached: String? = null

    @Volatile
    private var androidIdReader: (Context) -> String? = ::readAndroidId

    /**
     * 一次指纹读取的结果。[value] 就是 [get] 返回的 v2 指纹（算法、格式不变）；[isDegraded] 为 true
     * 表示本次 ANDROID_ID 读不到，[value] 是同型号全同的弱指纹——调用方拿它去和库里的强指纹比较
     * 必然不等，但那是"本轮识别不了设备"，不是"换了设备"，不能据此清库或上报绑定变化。
     */
    data class Resolved(val value: String, val isDegraded: Boolean)

    fun get(context: Context): String = resolve(context).value

    /** 同 [get]，但把"本次值是否退化"一起交给调用方。缓存里只会有强指纹，命中缓存即不退化。 */
    fun resolve(context: Context): Resolved {
        cached?.let { return Resolved(it, isDegraded = false) }
        synchronized(this) {
            cached?.let { return Resolved(it, isDegraded = false) }
            val androidId = androidId(context.applicationContext)
            val value = sha256Hex(stableMaterial(androidId))
            // 拿不到 ANDROID_ID 时算出来的是同型号全同的弱指纹。值本身照旧返回（算法不变），但不进
            // 进程级缓存：缓存会把这次读失败钉到进程结束，用户重试激活、下次 verify 都只能拿弱值；
            // 不缓存则下一次 get() 重读 Settings，provider 恢复后自然回到强指纹。
            val degraded = androidId.isEmpty()
            if (!degraded) {
                cached = value
            } else {
                Log.w(TAG, "ANDROID_ID unavailable; returning model-level fingerprint without caching")
            }
            return Resolved(value, isDegraded = degraded)
        }
    }

    fun legacyFingerprints(context: Context): List<String> {
        val app = context.applicationContext
        return listOf(
            sha256Hex(legacyMaterial(app, includeWidevine = true)),
            sha256Hex(legacyMaterial(app, includeWidevine = false)),
        ).distinct().filterNot { it == get(app) }
    }

    fun clearCacheForTests() {
        cached = null
    }

    /** 单测注入：换掉 ANDROID_ID 的读取方式（JVM 里 Settings.Secure 是返回 null 的桩）并清缓存；生产路径不得调用。 */
    internal fun overrideAndroidIdReaderForTest(reader: ((Context) -> String?)?) {
        synchronized(this) {
            androidIdReader = reader ?: ::readAndroidId
            cached = null
        }
    }

    private fun stableMaterial(androidId: String): String =
        listOf(
            "v2",
            "product=${ActivationApiClient.PRODUCT}",
            "androidId=$androidId",
            "manufacturer=${Build.MANUFACTURER.orEmpty()}",
            "model=${Build.MODEL.orEmpty()}",
            "device=${Build.DEVICE.orEmpty()}",
        ).joinToString("|")

    @SuppressLint("HardwareIds", "MissingPermission")
    private fun legacyMaterial(context: Context, includeWidevine: Boolean): String {
        val androidId = androidId(context)
        val serial = hardwareSerialOrEmpty()
        val values = mutableListOf("serial=$serial")
        if (includeWidevine) values += "drm=${widevineDeviceIdHex()}"
        values += listOf(
            "androidId=$androidId",
            "board=${Build.BOARD.orEmpty()}",
            "hardware=${Build.HARDWARE.orEmpty()}",
            "manufacturer=${Build.MANUFACTURER.orEmpty()}",
            "model=${Build.MODEL.orEmpty()}",
            "device=${Build.DEVICE.orEmpty()}",
            "product=${Build.PRODUCT.orEmpty()}",
        )
        return values.joinToString("|")
    }

    /** 读不到（settings provider 未就绪 / 被 ROM 拦截）回空串，但带栈记一条日志——之前是静默吞掉。 */
    private fun androidId(context: Context): String =
        runCatching { androidIdReader(context) }
            .onFailure { Log.w(TAG, "ANDROID_ID unreadable; fingerprint degrades to model-level material", it) }
            .getOrNull().orEmpty().trim()

    @SuppressLint("HardwareIds")
    private fun readAndroidId(context: Context): String? =
        Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)

    private fun widevineDeviceIdHex(): String =
        runCatching {
            val drm = MediaDrm(WIDEVINE_UUID)
            try {
                drm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
                    .joinToString("") { b -> "%02x".format(b) }
            } finally {
                runCatching { drm.release() }
            }
        }.getOrNull().orEmpty()

    @SuppressLint("HardwareIds", "MissingPermission")
    private fun hardwareSerialOrEmpty(): String {
        val fromApi = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Build.getSerial()
            } else {
                @Suppress("DEPRECATION")
                Build.SERIAL
            }
        }.getOrNull().orEmpty()
        if (isUsableSerial(fromApi)) return fromApi.trim()
        @Suppress("DEPRECATION")
        val legacy = runCatching { Build.SERIAL }.getOrNull().orEmpty()
        if (isUsableSerial(legacy)) return legacy.trim()
        return ""
    }

    private fun isUsableSerial(value: String?): Boolean {
        val v = value?.trim().orEmpty()
        if (v.length < 4) return false
        val lower = v.lowercase()
        return lower != "unknown" &&
            lower != "null" &&
            lower != "0123456789abcdef" &&
            !lower.startsWith("unknown")
    }

    private fun sha256Hex(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { b -> "%02x".format(b) }
    }
}
