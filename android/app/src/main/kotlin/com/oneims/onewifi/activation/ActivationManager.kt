package com.oneims.onewifi.activation

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 激活态门面：格式校验 → 设备指纹 → API → 本地加密持久化。
 */
object ActivationManager {

    private const val TAG = "OneWifi-Activation"
    private const val OFFLINE_GRACE_MS = 7L * 24 * 60 * 60 * 1000
    private const val HTTP_TOO_MANY_REQUESTS = 429
    private const val HTTP_SERVER_ERROR = 500

    /**
     * 服务端已把码绑到本机、本地落盘却失败时的用户文案。不能沿用网络文案：服务端状态已经改了，
     * "稍后重试"会让用户以为是网络问题；这里要说清是本机保存失败、该做的是再激活一次。
     */
    internal const val STORE_SAVE_FAILED_MESSAGE =
        "服务端已接受激活，但本机保存激活状态失败，请重新激活一次；持续出现请清除应用数据后再试"

    @Volatile
    private var apiClient: ActivationApiClient = ActivationApiClient()

    @Volatile
    private var onlineCheck: (Context) -> Boolean = ::hasInternetCapability

    fun configure(baseUrl: String = ActivationApiClient.DEFAULT_BASE_URL) {
        apiClient = ActivationApiClient(baseUrl = baseUrl)
    }

    /**
     * 单测注入：换掉 API 客户端（配合 OkHttp 拦截器短路网络）与联网判断（JVM 里拿不到
     * ConnectivityManager）；传 null 恢复默认。生产路径不得调用。
     */
    internal fun overrideForTest(client: ActivationApiClient?, online: ((Context) -> Boolean)?) {
        apiClient = client ?: ActivationApiClient()
        onlineCheck = online ?: ::hasInternetCapability
    }

    /**
     * 读本机激活态。激活库读不出来时抛 [ActivationStoreException]（已 `Log.e` 带栈），**不**折成 false：
     * 折成 false 会让通道层回一份合法的 `{activated=false}`，已付费用户被打回激活页，而 Dart 侧为
     * PlatformException 写的"沿用旧状态"兜底永远接不到。目前所有调用方都在 `onewifi/activation`
     * 通道的 `reply` 里，异常由它转成 `error("ACTIVATION", message)`；将来若有原生侧直接判断
     * 激活态的调用方（服务 / Tile / 开机路径），必须自己接住它并按"未激活"降级，不得让它成为启动崩溃。
     */
    fun isActivated(context: Context): Boolean =
        readStore(context, "isActivated") { ActivationStore.isActivated(it) }

    /** 同 [isActivated]：读失败抛 [ActivationStoreException]，不回 null。 */
    fun getActivationToken(context: Context): String? =
        readStore(context, "getActivationToken") { ActivationStore.getActivationToken(it) }

    fun getEdition(context: Context): String? {
        if (!isActivated(context)) return null
        return readStore(context, "getEdition") { ActivationStore.getEdition(it) }
    }

    fun getStoredCode(context: Context): String? {
        if (!isActivated(context)) return null
        return readStore(context, "getStoredCode") { ActivationStore.getStoredCode(it) }
    }

    fun membershipBadgeLabel(context: Context): String? =
        when (getEdition(context)?.lowercase()) {
            ActivationApiClient.EDITION_PRO -> "Pro"
            ActivationApiClient.EDITION_ULTRA -> "Ultra"
            else -> null
        }

    /**
     * 清除本机激活态。激活库打不开 / 写不进（release 下 `prefs()` 的 IllegalStateException、
     * EncryptedSharedPreferences 清空时解不开旧键的 SecurityException）同样包成 [ActivationStoreException]：
     * `replyAsync` 会把异常 message 原样当 `error("ACTIVATION", msg)` 回 Dart，设置页照抄显示，
     * 不能让 "EncryptedSharedPreferences required for activation store" 这类内部英文出现在界面上。
     * 读、写用同一句文案：同一个根因（激活库不可用）在 getState / activate 应答 / deactivate 三条路径上
     * 不该给出三种说法。
     */
    fun deactivate(context: Context) {
        try {
            ActivationStore.clear(context.applicationContext)
        } catch (e: Exception) {
            Log.e(TAG, "deactivate: activation store unwritable, surfacing as user-facing store error", e)
            throw ActivationStoreException(e)
        }
    }

    suspend fun activate(context: Context, code: String): ActivationResult =
        withContext(Dispatchers.IO) {
            val app = context.applicationContext
            val validation = CodeValidator.validate(code)
            if (!validation.ok) {
                return@withContext ActivationResult.Failure(validation.errorMessage)
            }
            if (!isOnline(app)) {
                return@withContext ActivationResult.Failure("当前无网络，请联网后再试")
            }
            val resolved = DeviceFingerprint.resolve(app)
            ActivationPreflight.check(
                isDegraded = resolved.isDegraded,
                cryptoEnabled = PayloadCrypto.isEnabled(),
            )?.let { return@withContext it }
            val fingerprint = resolved.value
            val response = try {
                apiClient.activate(
                    validation.normalized,
                    fingerprint,
                    DeviceFingerprint.legacyFingerprints(app),
                )
            } catch (e: PayloadCryptoException) {
                // 本机加密组件 / 密钥配置问题：不是网络，也不是服务端拒绝。
                logActivationFailure("activate", e)
                return@withContext ActivationResult.Failure(e.message ?: PayloadCryptoException.USER_MESSAGE)
            } catch (e: Exception) {
                logActivationFailure("activate", e)
                return@withContext ActivationResult.Failure(userFacingNetworkError(e))
            }
            if (!response.success || response.token.isNullOrBlank()) {
                return@withContext ActivationResult.Failure(
                    response.message.ifBlank { "激活失败" },
                )
            }
            // 到这里服务端已经把码绑到本机指纹；落盘失败是本机存储问题，和上面的网络 catch 分开归因，
            // 否则用户会被告知"网络异常，请稍后重试"，而服务端状态其实已经改了。
            try {
                ActivationStore.saveActivated(
                    app,
                    response.token,
                    fingerprint,
                    edition = response.edition,
                    code = validation.normalized,
                )
                ActivationStore.markOnlineVerified(app)
            } catch (e: Exception) {
                Log.e(TAG, "activate: server accepted the code but persisting activation locally failed", e)
                return@withContext ActivationResult.Failure(STORE_SAVE_FAILED_MESSAGE)
            }
            ActivationResult.Success(
                token = response.token,
                message = response.message.ifBlank { "激活成功" },
                edition = response.edition,
            )
        }

    /**
     * 复核本机会话：指纹须与激活时一致，随后在线 verify，离线走 7 天宽限。
     *
     * **当前仓内没有生产调用者**（只有单测）——MainActivity / 服务 / Tile / 开机路径都不调它，
     * `getState` 只读库不复核。守卫与测试先于接线补齐，将来接线时不必再回头改语义。
     *
     * 指纹失配的判定只在**本次指纹是强值**时成立：ANDROID_ID 瞬时读不到（settings provider 未就绪、
     * 被 ROM 拦截）时 [DeviceFingerprint.resolve] 给的是同型号全同的弱值，和库里的强指纹必然不等，
     * 但那是"本轮识别不了设备"而不是"换了设备"。此时不清库、也不拿弱值去服务端 verify（服务端会判
     * DEVICE_MISMATCH，同样会把有效激活清掉），只记 `Log.w` 并沿用本机已存的激活态返回 true：
     * 弱值不进缓存（167dd06），下一轮 provider 恢复后自然回到正常的失配 / 在线校验路径。不走
     * [allowOfflineGraceOrClear]：宽限到期会清库，而本机识别信息读不到不是用户该被判未激活的理由。
     */
    suspend fun verifyLocalSession(context: Context): Boolean =
        withContext(Dispatchers.IO) {
            val app = context.applicationContext
            if (!ActivationStore.isActivated(app)) return@withContext false
            val token = ActivationStore.getActivationToken(app) ?: return@withContext false
            val resolved = DeviceFingerprint.resolve(app)
            val fingerprint = resolved.value
            val storedFp = ActivationStore.getStoredFingerprint(app)
            if (storedFp != null && storedFp != fingerprint) {
                if (resolved.isDegraded) {
                    Log.w(
                        TAG,
                        "fingerprint mismatch while ANDROID_ID is unreadable this round; " +
                            "keeping local session, skipping device-binding check until the next verify",
                    )
                    return@withContext true
                }
                Log.w(TAG, "fingerprint mismatch; clearing activation")
                ActivationStore.clear(app)
                return@withContext false
            }
            if (!isOnline(app)) {
                return@withContext allowOfflineGraceOrClear(app)
            }
            try {
                val response = apiClient.verify(token, fingerprint)
                if (!response.valid) {
                    Log.w(TAG, "verify invalid: code=${response.code} msg=${response.message}")
                    ActivationStore.clear(app)
                    return@withContext false
                }
                ActivationStore.markOnlineVerified(app)
                true
            } catch (e: Exception) {
                logActivationFailure("verify", e)
                allowOfflineGraceOrClear(app)
            }
        }

    fun isOnline(context: Context): Boolean = onlineCheck(context)

    private fun hasInternetCapability(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun allowOfflineGraceOrClear(app: Context): Boolean {
        val lastOnline = ActivationStore.getLastOnlineVerifyMs(app)
        val activatedAt = ActivationStore.getActivationTime(app)
        val anchor = when {
            lastOnline > 0L -> lastOnline
            activatedAt > 0L -> activatedAt
            else -> 0L
        }
        if (anchor <= 0L || System.currentTimeMillis() - anchor > OFFLINE_GRACE_MS) {
            ActivationStore.clear(app)
            return false
        }
        return true
    }

    private fun userFacingNetworkError(e: Exception): String {
        if (e is ActivationHttpException) return activationRejectionMessage(e)
        val msg = e.message.orEmpty()
        return when {
            msg.contains("Failed to connect", ignoreCase = true) ||
                msg.contains("Connection refused", ignoreCase = true) ->
                "无法连接激活服务器，请检查网络后重试"
            msg.contains("timeout", ignoreCase = true) ->
                "连接超时，请稍后重试"
            else -> "网络异常，请稍后重试"
        }
    }

    private fun activationRejectionMessage(e: ActivationHttpException): String =
        when (e.errorCode) {
            ActivationErrorCodes.INVALID_CODE_FORMAT ->
                "激活码格式不对，请按 XXXX-XXXX-XXXX-XXXX 重新输入"
            ActivationErrorCodes.CODE_NOT_FOUND ->
                "激活码不存在，请核对后重新输入"
            ActivationErrorCodes.CODE_REVOKED ->
                "该激活码已被吊销，请联系购买渠道处理"
            ActivationErrorCodes.BOUND_OTHER_DEVICE ->
                "该激活码安卓席已绑定其它手机；换机请联系客服解绑后重试"
            ActivationErrorCodes.SEAT_KIND_REQUIRED,
            ActivationErrorCodes.SEAT_KIND_INVALID ->
                "激活席位无效，请更新应用后再试"
            ActivationErrorCodes.EDITION_MISMATCH ->
                "激活码档位与当前版本不匹配，请确认购买的是 Pro 还是 Ultra"
            ActivationErrorCodes.WEAK_FINGERPRINT ->
                "无法读取本机识别信息，请重启设备后重试"
            ActivationErrorCodes.CLAIMED_CONCURRENTLY,
            ActivationErrorCodes.BINDING_CHANGED ->
                "该激活码正在其它设备上激活，请稍后重试"
            else -> when {
                e.httpCode == HTTP_TOO_MANY_REQUESTS -> "操作过于频繁，请稍后再试"
                e.httpCode >= HTTP_SERVER_ERROR -> "激活服务暂时不可用，请稍后重试"
                else -> "激活被拒绝，请稍后重试或联系客服"
            }
        }

    private fun logActivationFailure(stage: String, e: Exception) {
        when (e) {
            is ActivationHttpException ->
                Log.w(TAG, "$stage rejected: http=${e.httpCode} code=${e.errorCode} body=${e.rawBody}")
            is PayloadCryptoException ->
                Log.e(TAG, "$stage aborted by local payload crypto: ${e.detail}", e)
            else -> Log.w(TAG, "$stage failed", e)
        }
    }

    /**
     * 激活库的读路径统一出口：任何异常（release 下 `prefs()` 的 IllegalStateException、
     * EncryptedSharedPreferences 解密失败的 SecurityException 等）先记 `Log.e` 带栈，再包成
     * [ActivationStoreException] 上抛。原始异常保留在 cause 里，方便从 logcat 定位是 Keystore 还是密文的问题。
     */
    private inline fun <T> readStore(context: Context, op: String, read: (Context) -> T): T =
        try {
            read(context.applicationContext)
        } catch (e: Exception) {
            Log.e(TAG, "$op: activation store unreadable, surfacing as error instead of not-activated", e)
            throw ActivationStoreException(e)
        }
}
