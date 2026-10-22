package com.oneims.onewifi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OtpNotificationCoordinatorTest {
    private class Harness {
        var granted = false
        var prompts = 0
        var acceptsPost = true
        var requestFails = false
        val posted = mutableListOf<OtpMessage>()
        val coordinator = OtpNotificationCoordinator(
            hasPermission = { granted },
            requestPermission = {
                prompts++
                if (requestFails) throw IllegalStateException("Activity unavailable")
            },
            post = { message ->
                if (acceptsPost) posted += message
                acceptsPost
            },
        )

        fun show(code: String = "123456"): MutableList<Boolean> {
            val replies = mutableListOf<Boolean>()
            coordinator.show(OtpMessage(code, "sender", "device")) { replies += it }
            return replies
        }

        fun grant() {
            granted = true
            coordinator.onPermissionResult(true)
        }
    }

    @Test
    fun `already granted posts once and reports actual submission`() {
        val h = Harness().apply { granted = true }
        assertEquals(listOf(true), h.show())
        assertEquals(listOf(OtpMessage("123456", "sender", "device")), h.posted)
        assertEquals(0, h.prompts)
    }

    @Test
    fun `first request remains pending until permission callback`() {
        val h = Harness()
        val replies = h.show()
        assertTrue(replies.isEmpty())
        assertTrue(h.posted.isEmpty())
        assertEquals(1, h.prompts)
        h.grant()
        assertEquals(listOf(true), replies)
        assertEquals(1, h.posted.size)
        h.grant()
        assertEquals(listOf(true), replies)
        assertEquals(1, h.posted.size)
    }

    @Test
    fun `one prompt owns multiple pending notifications in arrival order`() {
        val h = Harness()
        val old = h.show("111111")
        val latest = h.show("222222")
        assertEquals(1, h.prompts)
        h.grant()
        assertEquals(listOf("111111", "222222"), h.posted.map { it.code })
        assertEquals(listOf(true), old)
        assertEquals(listOf(true), latest)
    }

    @Test
    fun `new message cannot overtake pending messages before grant callback`() {
        val h = Harness()
        val old = h.show("111111")
        h.granted = true
        val latest = h.show("222222")
        assertTrue(h.posted.isEmpty())
        assertTrue(latest.isEmpty())
        h.coordinator.onPermissionResult(true)
        assertEquals(listOf("111111", "222222"), h.posted.map { it.code })
        assertEquals(listOf(true), old)
        assertEquals(listOf(true), latest)
    }

    @Test
    fun `denied permission replies false without repeated prompts`() {
        val h = Harness()
        val first = h.show()
        h.coordinator.onPermissionResult(false)
        assertEquals(listOf(false), first)
        assertEquals(listOf(false), h.show())
        assertEquals(1, h.prompts)
        assertTrue(h.posted.isEmpty())
    }

    @Test
    fun `permission granted in settings permits later notification after denial`() {
        val h = Harness()
        h.show()
        h.coordinator.onPermissionResult(false)
        h.granted = true
        assertEquals(listOf(true), h.show())
        assertEquals(1, h.prompts)
        assertEquals(1, h.posted.size)
    }

    @Test
    fun `notification disabled by system reports false`() {
        val h = Harness().apply { granted = true; acceptsPost = false }
        assertEquals(listOf(false), h.show())
        assertTrue(h.posted.isEmpty())
    }

    @Test
    fun `revoked permission before callback cannot submit`() {
        val h = Harness()
        val replies = h.show()
        h.coordinator.onPermissionResult(true)
        assertEquals(listOf(false), replies)
        assertTrue(h.posted.isEmpty())
    }

    @Test
    fun `cancel completes once and late grant cannot resurrect notification`() {
        val h = Harness()
        val replies = h.show()
        h.coordinator.cancel()
        h.coordinator.cancel()
        h.grant()
        assertEquals(listOf(false), replies)
        assertTrue(h.posted.isEmpty())
        assertEquals(listOf(true), h.show("654321"))
        assertEquals(listOf("654321"), h.posted.map { it.code })
    }

    @Test
    fun `destroy denies pending and future notifications even after late grant`() {
        val h = Harness()
        val replies = h.show()
        h.coordinator.destroy()
        h.grant()
        assertEquals(listOf(false), replies)
        assertEquals(listOf(false), h.show())
        assertTrue(h.posted.isEmpty())
    }

    @Test
    fun `queue is bounded and overflow releases oldest result`() {
        val h = Harness()
        val replies = (1..20).map { h.show(it.toString()) }
        assertTrue(replies.take(4).all { it == listOf(false) })
        assertTrue(replies.drop(4).all { it.isEmpty() })
        assertEquals(1, h.prompts)
        h.grant()
        assertEquals((5..20).map { it.toString() }, h.posted.map { it.code })
        assertTrue(replies.drop(4).all { it == listOf(true) })
    }

    @Test
    fun `destroy from overflow reply also releases newly enqueued request`() {
        val h = Harness()
        h.coordinator.show(OtpMessage("first", "sender", "device")) {
            h.coordinator.destroy()
        }
        val replies = (2..17).map { h.show(it.toString()) }
        assertTrue(replies.all { it == listOf(false) })
        h.grant()
        assertEquals(1, h.prompts)
        assertTrue(h.posted.isEmpty())
    }

    @Test
    fun `request failure releases result without a retry storm`() {
        val h = Harness().apply { requestFails = true }
        assertEquals(listOf(false), h.show())
        assertEquals(listOf(false), h.show())
        assertEquals(1, h.prompts)
        assertTrue(h.posted.isEmpty())
    }

    @Test
    fun `cancellation during callback prevents remaining queued submissions`() {
        val h = Harness()
        val first = mutableListOf<Boolean>()
        h.coordinator.show(OtpMessage("111111", "sender", "device")) {
            first += it
            h.coordinator.cancel()
        }
        val second = h.show("222222")
        h.grant()
        assertEquals(listOf(true), first)
        assertEquals(listOf(false), second)
        assertEquals(listOf("111111"), h.posted.map { it.code })
    }
}
