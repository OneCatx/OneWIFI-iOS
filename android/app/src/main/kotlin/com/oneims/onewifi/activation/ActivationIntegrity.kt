package com.oneims.onewifi.activation

import okio.ByteString.Companion.toByteString
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * 本地激活记录完整性封印：防止只改 prefs 布尔伪造已激活。
 * 密钥材料来自应用身份 + 设备指纹派生，不是服务端机密。
 */
internal object ActivationIntegrity {

    private const val VERSION = "v1"

    fun seal(
        token: String,
        fingerprint: String,
        edition: String?,
        activationTimeMs: Long,
        appId: String,
    ): String {
        val payload = canonical(token, fingerprint, edition, activationTimeMs)
        val mac = hmac(payload, appId, fingerprint)
        return "$VERSION.$mac"
    }

    fun matches(
        seal: String?,
        token: String,
        fingerprint: String,
        edition: String?,
        activationTimeMs: Long,
        appId: String,
    ): Boolean {
        if (seal.isNullOrBlank() || !seal.startsWith("$VERSION.")) return false
        val expected = seal(token, fingerprint, edition, activationTimeMs, appId)
        return constantTimeEquals(seal, expected)
    }

    private fun canonical(
        token: String,
        fingerprint: String,
        edition: String?,
        activationTimeMs: Long,
    ): String =
        listOf(
            VERSION,
            token.trim(),
            fingerprint.trim(),
            edition?.trim()?.lowercase().orEmpty(),
            activationTimeMs.toString(),
        ).joinToString("|")

    private fun hmac(payload: String, appId: String, fingerprint: String): String {
        val keyMaterial = MessageDigest.getInstance("SHA-256").digest(
            "onewifi-act-seal|$appId|$fingerprint".toByteArray(Charsets.UTF_8),
        )
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(keyMaterial, "HmacSHA256"))
        val raw = mac.doFinal(payload.toByteArray(Charsets.UTF_8))
        return raw.toByteString().base64()
    }

    private fun constantTimeEquals(a: String, b: String): Boolean {
        if (a.length != b.length) return false
        var r = 0
        for (i in a.indices) {
            r = r or (a[i].code xor b[i].code)
        }
        return r == 0
    }
}
