package com.oneims.onewifi

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Guards the Android-only bridge that the host JVM cannot instantiate. */
class NativeCompatibilityTest {
    private fun source(path: String): String {
        val root = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }
            .firstOrNull { File(it, "src/main/kotlin/com/oneims/onewifi/MainActivity.kt").isFile }
            ?: error("Cannot locate app source root")
        return File(root, "src/main/kotlin/com/oneims/onewifi/$path").readText()
    }

    @Test
    fun `min sdk 24 activation does not link API 26 Base64`() {
        for (name in listOf("activation/PayloadCrypto.kt", "activation/ActivationIntegrity.kt")) {
            assertFalse("$name must work before Android O", source(name).contains("java.util.Base64"))
        }
    }

    @Test
    fun `OTP bridge waits for permission results and owns cancellation`() {
        val activity = source("MainActivity.kt")
        assertTrue("First grant must resume pending notifications", activity.contains("override fun onRequestPermissionsResult("))
        assertTrue("Dart must be able to revoke pending notifications", activity.contains("\"cancel\" ->"))
        assertTrue("Activity teardown must revoke pending notifications", activity.contains("override fun onDestroy()"))
    }

    @Test
    fun `pre channel notifications request an audible alert`() {
        assertTrue(source("MainActivity.kt").contains(".setDefaults(Notification.DEFAULT_SOUND)"))
    }
}
