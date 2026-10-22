package com.oneims.onewifi.activation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CodeValidatorTest {
    @Test
    fun `normalizes grouped code`() {
        val result = CodeValidator.validate("  ab12-cd34-ef56-gh78  ")
        assertEquals(true, result.ok)
        assertEquals("AB12-CD34-EF56-GH78", result.normalized)
    }

    @Test
    fun `rejects placeholder sales text`() {
        val result = CodeValidator.validate("KEY-1")
        assertEquals(false, result.ok)
        assertNull(CodeValidator.normalize("向销售获取"))
    }

    @Test
    fun `error copy mentions suffix not prefix`() {
        val result = CodeValidator.validate("ULTRA-AB12-CD34-EF56-GH78")
        assertEquals(false, result.ok)
        assertEquals(true, result.errorMessage.contains("后缀"))
        assertEquals(false, result.errorMessage.contains("开头"))
    }

    @Test
    fun `accepts four groups with ultra suffix`() {
        val result = CodeValidator.validate("AB12-CD34-EF56-GH78-ULTRA")
        assertEquals(true, result.ok)
        assertEquals("AB12-CD34-EF56-GH78-ULTRA", result.normalized)
    }
}

class ActivationPreflightTest {
    @Test
    fun `degraded fingerprint never reaches the wire`() {
        val result = ActivationPreflight.check(isDegraded = true, cryptoEnabled = true)
        assertEquals("无法读取本机识别信息，请重启设备后重试", (result as ActivationResult.Failure).message)
    }

    @Test
    fun `missing payload key refuses plaintext`() {
        val result = ActivationPreflight.check(isDegraded = false, cryptoEnabled = false)
        assertEquals("本机未配置激活加密密钥，拒绝明文提交", (result as ActivationResult.Failure).message)
    }
}

class ActivationReplyMapsTest {
    @Test
    fun `failed write keeps message when snapshot is missing`() {
        val map = ActivationReplyMaps.write(
            ok = false,
            message = ActivationManager.STORE_SAVE_FAILED_MESSAGE,
            activated = false,
            code = null,
            membershipBadge = null,
            encrypted = false,
        )
        assertEquals(false, map["ok"])
        assertEquals(ActivationManager.STORE_SAVE_FAILED_MESSAGE, map["message"])
        assertEquals(false, map["activated"])
    }
}

class ActivationPayloadTest {
    @Test
    fun `android seat is onewifi product`() {
        val payload = ActivationApiClient.activatePayload(
            "AB12-CD34-EF56-GH78",
            "f".repeat(64),
        )
        assertEquals("onewifi", payload["product"])
        assertEquals("android", payload["client_kind"])
    }
}
