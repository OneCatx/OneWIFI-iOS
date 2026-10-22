package com.oneims.onewifi.activation

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivationBase64CompatibilityTest {
    @After
    fun resetCryptoOverrides() {
        PayloadCrypto.overrideKeyHex = null
        PayloadCrypto.overrideCipherFactoryForTest = null
    }

    @Test
    fun `existing v1 integrity seals keep standard padded Base64`() {
        val seal = ActivationIntegrity.seal(
            "fixture-token", "fixture-fingerprint", "ULTRA", 1700000000000L, "com.example.app",
        )
        assertEquals("v1.E/T+INrMm5VsUPN2b+70JtOFaD7yMaztj+nLEAPbjII=", seal)
        assertTrue(ActivationIntegrity.matches(seal, "fixture-token", "fixture-fingerprint", "ultra", 1700000000000L, "com.example.app"))
        assertFalse(ActivationIntegrity.matches(seal, "different-token", "fixture-fingerprint", "ultra", 1700000000000L, "com.example.app"))
    }

    @Test
    fun `AES 256 GCM NIST vector decrypts without changing wire format`() {
        PayloadCrypto.overrideKeyHex = "00".repeat(32)
        val vector = "AAAAAAAAAAAAAAAAzqdAPU1ga24HTsXTuvOdGNDRyKeZmWvwJluYtdSKuRk="
        assertEquals("\u0000".repeat(16), PayloadCrypto.decryptFromPayload(vector))
    }

    @Test
    fun `payload round trip preserves unicode JSON`() {
        PayloadCrypto.overrideKeyHex = "42".repeat(32)
        val json = "{\"code\":\"测试+/=\",\"ok\":true}"
        val payload = PayloadCrypto.encryptToPayload(json)
        assertTrue(payload.matches(Regex("[A-Za-z0-9+/]+={0,2}")))
        assertEquals(json, PayloadCrypto.decryptFromPayload(payload))
    }
}
