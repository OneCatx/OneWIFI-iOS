package com.oneims.onewifi

import java.util.ArrayDeque

internal data class OtpMessage(val code: String, val sender: String, val device: String)

/** Owns permission-delayed submissions and their replies. All calls run on the main thread. */
internal class OtpNotificationCoordinator(
    private val hasPermission: () -> Boolean,
    private val requestPermission: () -> Unit,
    private val post: (OtpMessage) -> Boolean,
) {
    private data class Pending(val message: OtpMessage, val complete: (Boolean) -> Unit)

    private val pending = ArrayDeque<Pending>()
    private var permissionRequested = false
    private var permissionInFlight = false
    private var destroyed = false

    fun show(message: OtpMessage, complete: (Boolean) -> Unit) {
        if (destroyed) {
            complete(false)
            return
        }
        if (!permissionInFlight && hasPermission()) {
            complete(post(message))
            return
        }
        // Once denied/dismissed, subsequent SMS polls must not repeatedly open the system dialog.
        if (permissionRequested && !permissionInFlight) {
            complete(false)
            return
        }
        pending.addLast(Pending(message, complete))
        if (pending.size > MAX_PENDING) pending.removeFirst().complete(false)
        if (destroyed || permissionInFlight) return
        permissionRequested = true
        permissionInFlight = true
        try {
            requestPermission()
        } catch (_: RuntimeException) {
            // The Activity may no longer be able to launch a permission dialog.
            permissionInFlight = false
            cancel()
        }
    }

    fun onPermissionResult(granted: Boolean) {
        if (!permissionInFlight || destroyed) return
        if (!granted || !hasPermission()) {
            permissionInFlight = false
            cancel()
            return
        }
        // Remove before reply: reentrant cancellation can still revoke all remaining submissions.
        while (!destroyed && pending.isNotEmpty()) {
            val item = pending.removeFirst()
            item.complete(hasPermission() && post(item.message))
        }
        permissionInFlight = false
    }

    fun cancel() {
        val cancelled = pending.toList()
        pending.clear()
        cancelled.forEach { it.complete(false) }
        // Keep the in-flight dialog owner until its callback; a new show may join that dialog.
    }

    fun destroy() {
        destroyed = true
        permissionInFlight = false
        cancel()
    }

    private companion object {
        const val MAX_PENDING = 16
    }
}
