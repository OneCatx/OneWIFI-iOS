package com.oneims.onewifi.activation

import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** MethodChannel `onewifi/activation`。权威校验在原生。 */
class ActivationChannelHandler(private val activity: Activity) {
    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getState" -> reply(result) { activationStateMap() }
                "activate" -> {
                    val code = call.argument<String>("code").orEmpty()
                    reply(result) {
                        when (val outcome = ActivationManager.activate(activity, code)) {
                            is ActivationResult.Success -> activationWriteMap(ok = true, message = outcome.message)
                            is ActivationResult.Failure -> activationWriteMap(ok = false, message = outcome.message)
                        }
                    }
                }
                "deactivate" -> reply(result) {
                    ActivationManager.deactivate(activity)
                    activationWriteMap(ok = true, message = "已清除本机激活")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun reply(result: MethodChannel.Result, block: suspend () -> Any?) {
        io.launch {
            val outcome = runCatching { block() }
            if (!isActive) return@launch
            activity.runOnUiThread {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = {
                        val message = (it as? ActivationStoreException)?.message
                            ?: it.message
                            ?: ActivationStoreException.USER_MESSAGE
                        result.error("ACTIVATION", message, null)
                    },
                )
            }
        }
    }

    private fun activationStateMap(): Map<String, Any?> {
        val activated = ActivationManager.isActivated(activity)
        return mapOf(
            "activated" to activated,
            "code" to ActivationManager.getStoredCode(activity),
            "membershipBadge" to ActivationManager.membershipBadgeLabel(activity),
            "encrypted" to PayloadCrypto.isEnabled(),
        )
    }

    private fun activationWriteMap(ok: Boolean, message: String): Map<String, Any?> {
        val snapshot = runCatching {
            Triple(
                ActivationManager.isActivated(activity),
                ActivationManager.getStoredCode(activity),
                ActivationManager.membershipBadgeLabel(activity),
            )
        }.getOrNull()
        return ActivationReplyMaps.write(
            ok = ok,
            message = message,
            activated = snapshot?.first ?: false,
            code = snapshot?.second,
            membershipBadge = snapshot?.third,
            encrypted = PayloadCrypto.isEnabled(),
        )
    }

    companion object {
        const val CHANNEL = "onewifi/activation"
    }
}
