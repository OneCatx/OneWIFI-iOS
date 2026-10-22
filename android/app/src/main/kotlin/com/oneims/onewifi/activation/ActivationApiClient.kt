package com.oneims.onewifi.activation

import android.util.Log
import com.oneims.onewifi.BuildConfig
import okhttp3.CertificatePinner
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * OneWifi 激活客户端。路径走家族 `/api/activate`、`/api/verify`，
 * `product=onewifi` 且 `client_kind=android`，与软路由席位共用一张码。
 */
class ActivationApiClient(
    baseUrl: String = DEFAULT_BASE_URL,
    private val client: OkHttpClient = defaultClient(),
) {
    private val root = baseUrl.trimEnd('/')

    fun activate(
        code: String,
        deviceFingerprint: String,
        legacyFingerprints: List<String> = emptyList(),
    ): ActivationResponse {
        val payload = activatePayload(code, deviceFingerprint, legacyFingerprints)
        val body = JSONObject()
            .put("code", payload.getValue("code"))
            .put("device_fingerprint", payload.getValue("device_fingerprint"))
            .put("fingerprint_version", payload.getValue("fingerprint_version"))
            .put("legacy_device_fingerprints", payload.getValue("legacy_device_fingerprints"))
            .put("product", payload.getValue("product"))
            .put("client_kind", payload.getValue("client_kind"))
            .toString()
        return postJson(PATH_ACTIVATE, body) { json ->
            parseActivationResponse(json)
        }
    }

    fun verify(token: String, deviceFingerprint: String): VerificationResponse {
        val payload = verifyPayload(token, deviceFingerprint)
        val body = JSONObject()
            .put("token", payload.getValue("token"))
            .put("device_fingerprint", payload.getValue("device_fingerprint"))
            .put("product", payload.getValue("product"))
            .toString()
        return postJson(PATH_VERIFY, body) { json ->
            parseVerificationResponse(json)
        }
    }

    /**
     * @throws PayloadCryptoException 有密钥但本机加密失败 / 密文响应解不开。有密钥就必须发密文、
     *   收到密文就必须解开：加密失败不得退成明文还打着 `X-Encrypted: 1`，解密失败不得把信封
     *   当业务响应解析。未配置密钥（[PayloadCrypto.isEnabled] 为 false）时照旧明文、不打头。
     */
    private fun <T> postJson(path: String, jsonBody: String, parse: (JSONObject) -> T): T {
        val useEncryption = PayloadCrypto.isEnabled()
        val wireBody = if (useEncryption) PayloadCrypto.encryptJson(jsonBody).toString() else jsonBody
        val requestBody = wireBody.toRequestBody(JSON_MEDIA)

        val requestBuilder = Request.Builder()
            .url("$root$path")
            .header("Content-Type", "application/json; charset=utf-8")
            .header("Accept", "application/json")
            .header("User-Agent", "OneWifi-Activation/1.0")
            .header(HEADER_PRODUCT, PRODUCT)
        if (useEncryption) {
            requestBuilder.header("X-Encrypted", "1")
        }
        val request = requestBuilder.post(requestBody).build()

        var lastError: Exception? = null
        repeat(MAX_ATTEMPTS) { attempt ->
            try {
                client.newCall(request).execute().use { response ->
                    val raw = response.body?.string().orEmpty()
                    if (!response.isSuccessful) {
                        throw ActivationHttpException(
                            httpCode = response.code,
                            errorCode = response.header(HEADER_ERROR_CODE).orEmpty().trim(),
                            rawBody = raw.take(MAX_ERROR_BODY_CHARS),
                        )
                    }
                    val json = if (raw.isBlank()) JSONObject() else JSONObject(raw)
                    val respEncrypted = response.header("X-Encrypted") == "1"
                    val effectiveJson = if (respEncrypted && useEncryption) {
                        JSONObject(PayloadCrypto.decryptJson(json))
                    } else {
                        json
                    }
                    return parse(effectiveJson)
                }
            } catch (e: Exception) {
                lastError = e
                // PayloadCryptoException 的 message 是用户文案，日志里要的是 detail；它不是瞬时错误，下面直接抛出、不重发。
                val reason = (e as? PayloadCryptoException)?.detail ?: e.message
                Log.w(TAG, "attempt ${attempt + 1}/$MAX_ATTEMPTS failed: $reason")
                if (attempt < MAX_ATTEMPTS - 1 && isTransient(e)) {
                    Thread.sleep(RETRY_BACKOFF_MS * (attempt + 1L))
                } else {
                    throw e
                }
            }
        }
        throw lastError ?: IOException("unknown network error")
    }

    private fun isTransient(e: Exception): Boolean = when (e) {
        is ActivationHttpException -> e.httpCode >= 500
        is IOException -> true
        else -> false
    }

    companion object {
        val DEFAULT_BASE_URL: String
            get() = BuildConfig.ONE_ACTIVATION_BASE_URL.trimEnd('/')

        const val COMMERCIAL_EDITION = "ultra"
        const val EDITION_PRO = "pro"
        const val EDITION_ULTRA = "ultra"

        const val PATH_ACTIVATE = "/api/activate"
        const val PATH_VERIFY = "/api/verify"

        /** 与 OneIMS / OneTools 隔离的产品线；软路由席位共用同一张码。 */
        const val PRODUCT = "onewifi"
        const val CLIENT_KIND = "android"
        const val HEADER_PRODUCT = "X-Product"

        fun activatePayload(
            code: String,
            deviceFingerprint: String,
            legacyFingerprints: List<String> = emptyList(),
        ): Map<String, Any> =
            mapOf(
                "code" to code,
                "device_fingerprint" to deviceFingerprint,
                "fingerprint_version" to 2,
                "legacy_device_fingerprints" to legacyFingerprints,
                "product" to PRODUCT,
                "client_kind" to CLIENT_KIND,
            )

        fun verifyPayload(token: String, deviceFingerprint: String): Map<String, Any> =
            mapOf(
                "token" to token,
                "device_fingerprint" to deviceFingerprint,
                "product" to PRODUCT,
            )

        private const val TAG = "OneWifi-ActivationApi"
        private const val MAX_ATTEMPTS = 3
        private const val RETRY_BACKOFF_MS = 400L
        private const val HEADER_ERROR_CODE = "X-Error-Code"
        private const val MAX_ERROR_BODY_CHARS = 200
        private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()

        fun defaultClient(): OkHttpClient {
            val builder = OkHttpClient.Builder()
                .connectTimeout(8, TimeUnit.SECONDS)
                .readTimeout(12, TimeUnit.SECONDS)
                .writeTimeout(12, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
            val host = activationHost()
            val pin = BuildConfig.ACTIVATION_SPKI_PIN.trim()
            if (!BuildConfig.DEBUG && host.isNotBlank() && pin.isNotBlank()) {
                builder.certificatePinner(
                    CertificatePinner.Builder().add(host, pin).build(),
                )
            }
            return builder.build()
        }

        private fun activationHost(): String {
            val url = DEFAULT_BASE_URL
            return runCatching { java.net.URI(url).host.orEmpty() }.getOrDefault("")
        }

        fun parseActivationResponse(json: JSONObject): ActivationResponse =
            ActivationResponse(
                success = json.optBoolean("success", false),
                token = json.optString("token").takeIf { it.isNotBlank() },
                message = json.optString("message", ""),
                edition = json.optString("edition").takeIf { it.isNotBlank() }
                    ?: COMMERCIAL_EDITION,
            )

        fun parseVerificationResponse(json: JSONObject): VerificationResponse =
            VerificationResponse(
                valid = json.optBoolean("valid", false),
                message = json.optString("message", ""),
                code = json.optString("code", ""),
            )
    }
}
