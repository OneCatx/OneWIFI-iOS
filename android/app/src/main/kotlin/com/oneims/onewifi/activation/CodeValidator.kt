package com.oneims.onewifi.activation

/**
 * 激活码格式校验：旧版四组码，或带 `-PRO` / `-ULTRA` 后缀的新版码。
 * 纯本地、无网络。权威进网前还会再判一次。
 */
object CodeValidator {

    private val BASE_CODE = Regex("^[A-Z0-9]{16}$")
    private val EDITION = Regex("^(PRO|ULTRA)$")

    fun validate(raw: String): CodeValidationResult {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            return CodeValidationResult(ok = false, errorMessage = "请输入激活码")
        }
        val normalized = normalize(trimmed) ?: return CodeValidationResult(
            ok = false,
            errorMessage = "格式应为 XXXX-XXXX-XXXX-XXXX，可选 -PRO/-ULTRA 后缀",
        )
        return CodeValidationResult(ok = true, normalized = normalized)
    }

    fun normalize(raw: String): String? {
        val compact = raw.trim().replace("-", "").replace(" ", "").uppercase()
        val edition = when {
            compact.length == 16 -> null
            compact.length > 16 -> compact.substring(16).takeIf(EDITION::matches) ?: return null
            else -> return null
        }
        val baseCode = compact.take(16)
        if (!BASE_CODE.matches(baseCode)) return null

        val normalizedBase = baseCode.chunked(4).joinToString("-")
        return edition?.let { "$normalizedBase-$it" } ?: normalizedBase
    }
}
