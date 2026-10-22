package com.oneims.onewifi.activation

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import com.oneims.onewifi.BuildConfig

/**
 * 激活态本地持久化（独立 prefs：`onewifi_activation`）。
 * Release：必须 EncryptedSharedPreferences（AES256_SIV / GCM）+ HMAC 封印。
 * Debug：加密失败才回退明文 prefs，便于模拟器排障。
 */
object ActivationStore {

    private const val TAG = "OneWifi-ActivationStore"
    private const val PREF = "onewifi_activation"
    private const val KEY_ACTIVATED = "is_activated"
    private const val KEY_TOKEN = "activation_token"
    private const val KEY_TIME = "activation_time"
    private const val KEY_FINGERPRINT = "device_fingerprint"
    private const val KEY_EDITION = "activation_edition"
    private const val KEY_CODE = "activation_code"
    private const val KEY_SEAL = "activation_seal"
    private const val KEY_LAST_ONLINE_VERIFY = "last_online_verify_ms"

    // MasterKeys + Tink 初始化要走 Keystore/TEE（百毫秒级），进程内建一次即可；建失败不缓存，下次照旧重试。
    @Volatile
    private var encrypted: SharedPreferences? = null

    private var encryptedFactory: (Context) -> SharedPreferences = ::encryptedPrefs

    /**
     * 提前把加密 prefs 建好，让那次 Keystore/TEE 初始化和 Flutter 首帧前的工作重叠，而不是等
     * 首次 `getState` 到达才开始。只是把创建时机提前：读到什么、校验什么都不变。建失败只记日志、
     * 不缓存，真正读取时按 [prefs] 原路重试或回退，所以这里永远不抛。
     */
    fun warm(context: Context) {
        if (encrypted != null) return
        runCatching { encryptedOnce(context.applicationContext) }
            .onFailure { Log.w(TAG, "warm-up skipped, will retry on first read: ${it.message}") }
    }

    fun isActivated(context: Context): Boolean {
        if (!ensureIntegrity(context)) return false
        return prefs(context).getBoolean(KEY_ACTIVATED, false)
    }

    fun getActivationToken(context: Context): String? {
        if (!ensureIntegrity(context)) return null
        return prefs(context).getString(KEY_TOKEN, null)?.takeIf { it.isNotBlank() }
    }

    fun getActivationTime(context: Context): Long {
        if (!ensureIntegrity(context)) return 0L
        return prefs(context).getLong(KEY_TIME, 0L)
    }

    fun getStoredFingerprint(context: Context): String? {
        if (!ensureIntegrity(context)) return null
        return prefs(context).getString(KEY_FINGERPRINT, null)?.takeIf { it.isNotBlank() }
    }

    fun getEdition(context: Context): String? {
        if (!ensureIntegrity(context)) return null
        return prefs(context).getString(KEY_EDITION, null)?.takeIf { it.isNotBlank() }
    }

    fun getStoredCode(context: Context): String? {
        if (!ensureIntegrity(context)) return null
        return prefs(context).getString(KEY_CODE, null)?.takeIf { it.isNotBlank() }
    }

    fun saveActivated(
        context: Context,
        token: String,
        deviceFingerprint: String,
        edition: String? = null,
        code: String? = null,
        activationTimeMs: Long = System.currentTimeMillis(),
    ) {
        val normalized = edition?.trim()?.lowercase().orEmpty()
        val appId = context.packageName
        val seal = ActivationIntegrity.seal(
            token = token,
            fingerprint = deviceFingerprint,
            edition = normalized.ifBlank { null },
            activationTimeMs = activationTimeMs,
            appId = appId,
        )
        val editor = prefs(context).edit()
            .putBoolean(KEY_ACTIVATED, true)
            .putString(KEY_TOKEN, token)
            .putLong(KEY_TIME, activationTimeMs)
            .putString(KEY_FINGERPRINT, deviceFingerprint)
            .putString(KEY_SEAL, seal)
        if (normalized.isNotEmpty()) {
            editor.putString(KEY_EDITION, normalized)
        }
        val storedCode = code?.trim().orEmpty()
        if (storedCode.isNotEmpty()) {
            editor.putString(KEY_CODE, storedCode)
        }
        editor.apply()
    }

    fun getLastOnlineVerifyMs(context: Context): Long =
        prefs(context).getLong(KEY_LAST_ONLINE_VERIFY, 0L)

    fun markOnlineVerified(context: Context, atMs: Long = System.currentTimeMillis()) {
        prefs(context).edit().putLong(KEY_LAST_ONLINE_VERIFY, atMs).apply()
    }

    fun clear(context: Context) {
        prefs(context).edit().clear().apply()
    }

    private fun ensureIntegrity(context: Context): Boolean {
        val p = prefs(context)
        if (!p.getBoolean(KEY_ACTIVATED, false)) return true
        val token = p.getString(KEY_TOKEN, null)?.takeIf { it.isNotBlank() } ?: run {
            clear(context)
            return false
        }
        val fp = p.getString(KEY_FINGERPRINT, null)?.takeIf { it.isNotBlank() } ?: run {
            clear(context)
            return false
        }
        val time = p.getLong(KEY_TIME, 0L)
        val edition = p.getString(KEY_EDITION, null)
        val seal = p.getString(KEY_SEAL, null)
        val appId = context.packageName
        if (seal.isNullOrBlank()) {
            val migrated = ActivationIntegrity.seal(token, fp, edition, time, appId)
            p.edit().putString(KEY_SEAL, migrated).apply()
            return true
        }
        if (!ActivationIntegrity.matches(seal, token, fp, edition, time, appId)) {
            Log.w(TAG, "activation seal mismatch; clearing")
            clear(context)
            return false
        }
        return true
    }

    private fun prefs(context: Context): SharedPreferences {
        encrypted?.let { return it }
        val app = context.applicationContext
        return runCatching { encryptedOnce(app) }.getOrElse { err ->
            if (BuildConfig.DEBUG) {
                Log.w(TAG, "EncryptedSharedPreferences unavailable, debug fallback: ${err.message}")
                plainPrefs(app)
            } else {
                throw IllegalStateException(
                    "EncryptedSharedPreferences required for activation store",
                    err,
                )
            }
        }
    }

    private fun plainPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    private fun encryptedOnce(context: Context): SharedPreferences = synchronized(this) {
        encrypted ?: encryptedFactory(context).also { encrypted = it }
    }

    /** 单测注入：换掉加密 prefs 的创建方式并丢弃已缓存实例；生产路径不得调用。 */
    internal fun overrideEncryptedPrefsForTest(factory: ((Context) -> SharedPreferences)?) {
        synchronized(this) {
            encryptedFactory = factory ?: ::encryptedPrefs
            encrypted = null
        }
    }

    private fun encryptedPrefs(context: Context): SharedPreferences {
        val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
        return EncryptedSharedPreferences.create(
            PREF,
            masterKeyAlias,
            context,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }
}
