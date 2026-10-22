package com.oneims.onewifi.activation

import android.util.Log
import com.oneims.onewifi.BuildConfig
import okio.ByteString.Companion.decodeBase64
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import java.security.SecureRandom

/**
 * AES-256-GCM 载荷加密，对齐家族 activation-api `app/crypto.py`。
 *
 * 线格式：{"payload":"<base64(nonce(12) || ciphertext || tag(16))>"}
 *
 * 32 字节密钥来自 BuildConfig（local.properties / `_secrets`），不进 git。
 * 密钥缺失时 [isEnabled] 为 false，请求走明文，服务端可回落。
 *
 * 有密钥时加解密**失败即抛** [PayloadCryptoException]，不回 null：回 null 曾让调用方把请求体
 * 退成明文却仍打 `X-Encrypted: 1`，或把解不开的密文信封当业务响应解析（审计 E3）。
 */
internal object PayloadCrypto {

    private const val TAG = "PayloadCrypto"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_IV_LENGTH = 12
    private const val GCM_TAG_LENGTH_BITS = 128

    /** 单测注入；生产路径必须保持 null。 */
    @Volatile
    var overrideKeyHex: String? = null

    /** 单测注入：替换 Cipher 的获取方式以模拟本机加密组件故障；生产路径必须保持 null。 */
    @Volatile
    internal var overrideCipherFactoryForTest: ((transformation: String) -> Cipher)? = null

    /** @throws PayloadCryptoException 密钥缺失或本机 Cipher 失败。 */
    fun encryptJson(jsonBody: String): JSONObject =
        JSONObject().put("payload", encryptToPayload(jsonBody))

    /** @throws PayloadCryptoException 信封没有 payload、密文残缺或解不开（密钥不匹配）。 */
    fun decryptJson(envelope: JSONObject): String {
        val payload = envelope.optString("payload", "")
        if (payload.isBlank()) throw PayloadCryptoException("encrypted response has no payload field")
        return decryptFromPayload(payload)
    }

    /** 纯密文往返，便于 JVM 单测不依赖 android.jar 的 JSONObject 桩。 */
    fun encryptToPayload(jsonBody: String): String {
        val key = requireKey()
        return try {
            val cipher = cipherFor(Cipher.ENCRYPT_MODE, key)
            val plaintext = jsonBody.toByteArray(Charsets.UTF_8)
            val ciphertext = cipher.doFinal(plaintext)
            val iv = cipher.iv
            val combined = iv + ciphertext
            combined.toByteString().base64()
        } catch (e: Exception) {
            Log.w(TAG, "encrypt failed: ${e.message}")
            throw PayloadCryptoException("encrypt failed: ${e.javaClass.simpleName}", e)
        }
    }

    fun decryptFromPayload(payload: String): String {
        val key = requireKey()
        if (payload.isBlank()) throw PayloadCryptoException("encrypted payload is blank")
        return try {
            val combined = payload.decodeBase64()?.toByteArray()
                ?: throw PayloadCryptoException("encrypted payload is not valid Base64")
            if (combined.size < GCM_IV_LENGTH + 16) {
                throw PayloadCryptoException("encrypted payload too short: ${combined.size} bytes")
            }
            val iv = combined.copyOfRange(0, GCM_IV_LENGTH)
            val ciphertextWithTag = combined.copyOfRange(GCM_IV_LENGTH, combined.size)
            val cipher = cipherFor(Cipher.DECRYPT_MODE, key, iv)
            val plaintext = cipher.doFinal(ciphertextWithTag)
            String(plaintext, Charsets.UTF_8)
        } catch (e: PayloadCryptoException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "decrypt failed: ${e.message}")
            throw PayloadCryptoException("decrypt failed: ${e.javaClass.simpleName}", e)
        }
    }

    private fun requireKey(): ByteArray =
        keyBytes() ?: throw PayloadCryptoException("payload key not configured or invalid")

    fun isEnabled(): Boolean = keyBytes() != null

    internal fun configuredKeyHex(): String {
        val override = overrideKeyHex
        // null = 走 BuildConfig；非 null（含空串）= 单测注入，空串必须能关掉加密。
        if (override != null) return override.trim()
        return runCatching { BuildConfig.PAYLOAD_CRYPTO_KEY }.getOrDefault("").trim()
    }

    private fun keyBytes(): ByteArray? {
        val hex = configuredKeyHex()
        if (hex.isBlank()) return null
        return try {
            val bytes = hex.hexToByteArray()
            if (bytes.size != 32) {
                Log.w(TAG, "key must be 32 bytes, got ${bytes.size}")
                return null
            }
            bytes
        } catch (e: Exception) {
            Log.w(TAG, "invalid hex key: ${e.message}")
            null
        }
    }

    private fun cipherFor(mode: Int, key: ByteArray, iv: ByteArray? = null): Cipher {
        val cipher = overrideCipherFactoryForTest?.invoke(TRANSFORMATION) ?: Cipher.getInstance(TRANSFORMATION)
        val keySpec = SecretKeySpec(key, "AES")
        if (mode == Cipher.ENCRYPT_MODE) {
            val randomIv = ByteArray(GCM_IV_LENGTH).also { SecureRandom().nextBytes(it) }
            val spec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, randomIv)
            cipher.init(mode, keySpec, spec)
        } else {
            requireNotNull(iv) { "IV required for decryption" }
            val spec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)
            cipher.init(mode, keySpec, spec)
        }
        return cipher
    }

    private fun String.hexToByteArray(): ByteArray {
        require(length % 2 == 0) { "hex string must have even length" }
        return ByteArray(length / 2) { i ->
            substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }
}
