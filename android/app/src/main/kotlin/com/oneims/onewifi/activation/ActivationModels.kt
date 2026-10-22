package com.oneims.onewifi.activation

data class ActivationResponse(
    val success: Boolean,
    val token: String?,
    val message: String,
    val edition: String = ActivationApiClient.COMMERCIAL_EDITION,
)

data class VerificationResponse(
    val valid: Boolean,
    val message: String,
    val code: String = "",
)

/**
 * 与 activation-api `ErrorCode` 对齐。只增不改；未知码走通用文案。
 */
object ActivationErrorCodes {
    const val INVALID_CODE_FORMAT = "INVALID_CODE_FORMAT"
    const val WEAK_FINGERPRINT = "WEAK_FINGERPRINT"
    const val CODE_NOT_FOUND = "CODE_NOT_FOUND"
    const val CODE_REVOKED = "CODE_REVOKED"
    const val BOUND_OTHER_DEVICE = "BOUND_OTHER_DEVICE"
    const val EDITION_MISMATCH = "EDITION_MISMATCH"
    const val CLAIMED_CONCURRENTLY = "CLAIMED_CONCURRENTLY"
    const val BINDING_CHANGED = "BINDING_CHANGED"
    const val SEAT_KIND_REQUIRED = "SEAT_KIND_REQUIRED"
    const val SEAT_KIND_INVALID = "SEAT_KIND_INVALID"
    const val TOKEN_NOT_FOUND = "TOKEN_NOT_FOUND"
    const val TOKEN_EXPIRED = "TOKEN_EXPIRED"
    const val DEVICE_MISMATCH = "DEVICE_MISMATCH"
}

class ActivationHttpException(
    val httpCode: Int,
    val errorCode: String,
    val rawBody: String,
) : java.io.IOException(
    "HTTP " + httpCode + (if (errorCode.isNotBlank()) " [$errorCode]" else ""),
)

/**
 * 本机激活库不可用：Keystore 失效、备份还原后密文解不开、release 下 EncryptedSharedPreferences
 * 建不出来。读路径上这是"读失败"而不是"未激活"——[ActivationManager] 抛它而不是回 false / null，通道层经
 * `replyAsync` 变成 `error("ACTIVATION", message)`，Dart 侧据此沿用上次状态；`deactivate` 清库失败
 * 同样包成它，让写路径的存储故障也说中文（契约见 `contracts/activation-channel.md`）。
 * message 面向用户（写方法会原样显示），不带内部细节。
 */
class ActivationStoreException(cause: Throwable) : RuntimeException(USER_MESSAGE, cause) {
    companion object {
        const val USER_MESSAGE = "本机激活状态暂时无法读取，请稍后重试（持续出现请清除应用数据后重新激活）"
    }
}

/**
 * 本机载荷加解密失败：Cipher 拿不到 / 初始化失败、响应密文解不开（密钥不匹配、信封残缺）。
 * 这是"本机加密组件"的问题，不是网络问题，也不是服务端拒绝——[ActivationApiClient] 抛它而不是
 * 退成明文发送或把密文信封当业务响应解析；[ActivationManager] 据此给用户加密类文案。
 * [detail] 只进日志；`message` 面向用户，不带内部细节。
 */
class PayloadCryptoException(val detail: String, cause: Throwable? = null) : RuntimeException(USER_MESSAGE, cause) {
    companion object {
        const val USER_MESSAGE = "本机加密组件异常，无法完成激活通信；请更新或重启应用后重试，持续出现请联系客服"
    }
}

data class CodeValidationResult(
    val ok: Boolean,
    val normalized: String = "",
    val errorMessage: String = "",
)

object ActivationPreflight {
    fun check(isDegraded: Boolean, cryptoEnabled: Boolean): ActivationResult.Failure? = when {
        isDegraded -> ActivationResult.Failure("无法读取本机识别信息，请重启设备后重试")
        !cryptoEnabled -> ActivationResult.Failure("本机未配置激活加密密钥，拒绝明文提交")
        else -> null
    }
}

object ActivationReplyMaps {
    fun write(
        ok: Boolean,
        message: String,
        activated: Boolean,
        code: String?,
        membershipBadge: String?,
        encrypted: Boolean,
    ): Map<String, Any?> = mapOf(
        "ok" to ok,
        "message" to message,
        "activated" to activated,
        "code" to code,
        "membershipBadge" to membershipBadge,
        "encrypted" to encrypted,
    )
}

sealed class ActivationResult {
    data class Success(
        val token: String,
        val message: String,
        val edition: String = ActivationApiClient.COMMERCIAL_EDITION,
    ) : ActivationResult()

    data class Failure(val message: String) : ActivationResult()
}
