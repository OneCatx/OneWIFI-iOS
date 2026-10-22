package com.oneims.onewifi

import java.io.ByteArrayInputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class UpdateApkDownloadTest {
    private val asset = "https://api.github.com/repos/asrtroh-netizen/OneWIFI-APK/releases/assets/42"
    private val cdn = "https://release-assets.githubusercontent.com/test.apk?signature=synthetic"

    @Test fun `direct asset carries runtime authorization and creates the APK`() = inDirectory { dir ->
        val connection = Reply(asset, 200)
        val apk = UpdateApkDownload.download(dir, asset, "test", "synthetic-token") { connection }
        assertEquals("Bearer synthetic-token", connection.getRequestProperty("Authorization"))
        assertEquals(2048L, apk.length())
        assertTrue(connection.disconnected)
    }

    @Test fun `redirected CDN request never carries authorization`() = inDirectory { dir ->
        val connections = listOf(Reply(asset, 302, cdn), Reply(cdn, 200))
        var requests = 0
        UpdateApkDownload.download(dir, asset, "test", "synthetic-token") { url ->
            connections[requests++].also { assertEquals(it.url.toString(), url) }
        }
        assertEquals(2, requests)
        assertEquals("Bearer synthetic-token", connections[0].getRequestProperty("Authorization"))
        assertNull(connections[1].getRequestProperty("Authorization"))
        assertTrue(connections.all { it.disconnected })
    }

    @Test fun `anonymous asset request still asks for binary rather than JSON metadata`() = inDirectory { dir ->
        val connection = Reply(asset, 200)
        UpdateApkDownload.download(dir, asset, "test", "") { connection }
        assertNull(connection.getRequestProperty("Authorization"))
        assertEquals("application/octet-stream", connection.getRequestProperty("Accept"))
    }

    @Test fun `HTTP redirect is rejected before another request and leaves no partial file`() = inDirectory { dir ->
        var requests = 0
        assertThrows(IllegalArgumentException::class.java) {
            UpdateApkDownload.download(dir, asset, "test", "synthetic-token") {
                requests++
                Reply(asset, 302, "http://example.test/file.apk")
            }
        }
        assertEquals(1, requests)
        assertEquals(0, dir.listFiles()!!.size)
    }

    @Test fun `an invalid initial origin receives neither a request nor credentials`() = inDirectory { dir ->
        var requests = 0
        assertThrows(IllegalArgumentException::class.java) {
            UpdateApkDownload.download(dir, "https://example.test/file.apk", "test", "synthetic-token") {
                requests++
                Reply(asset, 200)
            }
        }
        assertEquals(0, requests)
        assertEquals(0, dir.listFiles()!!.size)
    }

    private fun inDirectory(block: (File) -> Unit) {
        val dir = Files.createTempDirectory("onewifi-update-test-").toFile()
        try { block(dir) } finally {
            dir.listFiles().orEmpty().forEach { check(it.isFile); it.delete() }
            dir.delete()
        }
    }

    private class Reply(address: String, private val status: Int, private val location: String? = null) : HttpURLConnection(URL(address)) {
        var disconnected = false
        override fun connect() {}
        override fun disconnect() { disconnected = true }
        override fun usingProxy() = false
        override fun getResponseCode() = status
        override fun getHeaderField(name: String): String? = if (name == "Location") location else null
        override fun getInputStream() = ByteArrayInputStream(ByteArray(2048) { 42 })
    }
}
