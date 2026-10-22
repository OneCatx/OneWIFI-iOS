package com.oneims.onewifi

import org.junit.Assert.*
import org.junit.Test

class UpdateDownloadPolicyTest {
    private val asset = "https://api.github.com/repos/asrtroh-netizen/OneWIFI-APK/releases/assets/42"

    @Test fun `runtime credential is only authorized for the exact asset endpoint`() {
        assertTrue(UpdateDownloadPolicy.canAuthorize(asset))
        for (bad in listOf(
            asset.replace("api.github.com", "api.github.com.example.test"),
            asset.replace("OneWIFI-APK", "other"),
            asset.replace("https://", "http://"),
            "$asset?redirect=1", "$asset#fragment",
            asset.replace("api.github.com", "user:password@api.github.com"),
            asset.replace("api.github.com", "api.github.com:444"),
        )) assertFalse(UpdateDownloadPolicy.canAuthorize(bad))
    }

    @Test fun `public release asset is allowed but never authorized`() {
        val publicUrl = "https://github.com/asrtroh-netizen/OneWIFI-APK/releases/download/v1/OneWIFI.apk"
        UpdateDownloadPolicy.validateStart(publicUrl)
        assertFalse(UpdateDownloadPolicy.canAuthorize(publicUrl))
    }

    @Test fun `redirect cannot downgrade transport or contain credentials`() {
        for (bad in listOf("http://example.test/a", "https://user@example.test/a", "file:///a")) {
            assertThrows(IllegalArgumentException::class.java) { UpdateDownloadPolicy.requireHttps(bad) }
        }
        UpdateDownloadPolicy.requireHttps("https://release-assets.githubusercontent.com/a?signature=synthetic")
    }

    @Test fun `release version cannot create a path outside updates directory`() {
        val name = UpdateDownloadPolicy.fileVersion("../../example/thing")
        assertFalse(name.contains('/'))
        assertFalse(name.contains('\\'))
    }
}
