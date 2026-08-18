package yuzu.shiki.oh_my_llm

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 聊天生成前台服务的原生 MethodChannel：接收 Dart 的命令，持有 start 的
 * 挂起结果（按原生内部递增 commandId 关联），并暴露 companion 回调供
 * Service 回 ACK / 发送 stop/open/timeout 事件。任何通道失败都映射为固定
 * 失败分类，不向 Dart 抛出、不记录 payload 或异常原文。
 */
class ChatGenerationForegroundChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHAT_GENERATION_CHANNEL)
    private val pendingStarts = mutableMapOf<Long, MethodChannel.Result>()
    private var nextCommandId = 1L
    private var permissionResult: MethodChannel.Result? = null
    private val permissionPrefs: SharedPreferences by lazy {
        activity.getSharedPreferences(PERMISSION_PREFS, Context.MODE_PRIVATE)
    }

    init {
        channel.setMethodCallHandler(this)
        instance = this
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_ENSURE_NOTIFICATION_PERMISSION -> handleEnsurePermission(result)
            METHOD_START_FOREGROUND_GENERATION -> handleStart(call, result)
            METHOD_UPDATE_FOREGROUND_GENERATION -> handleUpdate(call, result)
            METHOD_REMOVE_FOREGROUND_GENERATION -> handleRemove(call, result)
            METHOD_FAIL_FOREGROUND_GENERATION -> handleFail(call, result)
            METHOD_TAKE_PENDING_OPEN_CONVERSATION -> handleTakePendingOpenConversation(result)
            else -> result.notImplemented()
        }
    }

    /**
     * 通知打开会话：总是先缓存到最后 conversation ID（冷启动兜底），
     * 再向 warm engine 发送 openConversationRequested；Dart 受理返回 true
     * 时清除该缓存，避免经 stream 与 takePendingOpenConversation 双重投递。
     */
    fun handleOpenConversationIntent(intent: Intent) {
        val conversationId = intent.getStringExtra(KEY_CONVERSATION_ID) ?: return
        if (conversationId.isBlank()) return
        pendingOpenConversation = conversationId
        emitOpenConversation(conversationId)
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != REQUEST_POST_NOTIFICATIONS) return
        val pending = permissionResult ?: return
        permissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending.success(
            permissionStatusResult(if (granted) STATUS_GRANTED else STATUS_DENIED),
        )
    }

    fun dispose() {
        if (instance === this) instance = null
        channel.setMethodCallHandler(null)
        pendingStarts.values.forEach {
            it.success(unavailableCommandResult(FAILURE_CHANNEL_UNAVAILABLE))
        }
        pendingStarts.clear()
        permissionResult?.success(permissionStatusResult(STATUS_UNAVAILABLE))
        permissionResult = null
        ChatGenerationForegroundService.stopForEngineDetach(activity.applicationContext)
    }

    // ── 命令处理 ──────────────────────────────────────────────────────────

    private fun handleEnsurePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(permissionStatusResult(STATUS_NOT_REQUIRED))
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(permissionStatusResult(STATUS_GRANTED))
            return
        }
        if (permissionPrefs.getBoolean(KEY_POST_NOTIFICATIONS_REQUESTED, false)) {
            result.success(permissionStatusResult(STATUS_SKIPPED_ALREADY_REQUESTED))
            return
        }
        if (activity.isFinishing || activity.isDestroyed || !activity.hasWindowFocus()) {
            result.success(permissionStatusResult(STATUS_UNAVAILABLE))
            return
        }
        if (permissionResult != null) {
            // 同一时刻至多一个挂起结果，避免覆盖。
            result.success(permissionStatusResult(STATUS_UNAVAILABLE))
            return
        }
        permissionResult = result
        // 在真正发起系统请求前先写持久化：拒绝后跨进程重启也不重复弹。
        permissionPrefs.edit().putBoolean(KEY_POST_NOTIFICATIONS_REQUESTED, true).apply()
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    private fun handleStart(call: MethodCall, result: MethodChannel.Result) {
        val payload = parsePayloadArgument(call)
        if (payload == null) {
            result.success(unavailableCommandResult(FAILURE_MALFORMED_PAYLOAD))
            return
        }
        val commandId = nextCommandId++
        pendingStarts[commandId] = result
        val intent = Intent(activity, ChatGenerationForegroundService::class.java).apply {
            action = SERVICE_START_ACTION
            putExtra(EXTRA_COMMAND_ID, commandId)
            putExtra(KEY_TOKEN, payload.token)
            putExtra(KEY_CONVERSATION_ID, payload.conversationId)
            putExtra(KEY_TITLE, payload.title)
            putExtra(KEY_TEXT, payload.text)
            putExtra(KEY_PUBLIC_TITLE, payload.publicTitle)
            putExtra(KEY_PUBLIC_TEXT, payload.publicText)
            putExtra(KEY_ACTION_KIND, payload.actionKind.protocolName())
            if (payload.actionLabel != null) putExtra(KEY_ACTION_LABEL, payload.actionLabel)
        }
        try {
            ContextCompat.startForegroundService(activity, intent)
        } catch (e: SecurityException) {
            logCategory("start_security")
            finishStart(commandId, NativeCommandResult.Unavailable(FAILURE_SECURITY))
        } catch (e: IllegalStateException) {
            // 后台启动被拒在 API 31+ 抛 ForegroundServiceStartNotAllowedException
            // （IllegalStateException 的子类），低版本 API 直接抛
            // IllegalStateException。不能直接 catch 那个 API 31+ 类：低版本设备
            // 在异常匹配时会因类缺失触发 NoClassDefFoundError（Error，泛型
            // Exception 捕获不了），因此统一按启动不允许映射为 startNotAllowed。
            logCategory("start_not_allowed")
            finishStart(
                commandId,
                NativeCommandResult.Unavailable(FAILURE_START_NOT_ALLOWED),
            )
        } catch (e: Exception) {
            logCategory("start_native_failure")
            finishStart(commandId, NativeCommandResult.Unavailable(FAILURE_NATIVE_FAILURE))
        }
    }

    private fun handleUpdate(call: MethodCall, result: MethodChannel.Result) {
        val payload = parsePayloadArgument(call)
        if (payload == null) {
            result.success(unavailableCommandResult(FAILURE_MALFORMED_PAYLOAD))
            return
        }
        result.success(ChatGenerationForegroundService.update(payload).toMap())
    }

    private fun handleRemove(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments
        if (arguments !is Map<*, *>) {
            result.success(unavailableCommandResult(FAILURE_MALFORMED_PAYLOAD))
            return
        }
        val token = parsePositiveToken(arguments[KEY_TOKEN])
        val conversationId = arguments[KEY_CONVERSATION_ID] as? String
        if (token == null || conversationId.isNullOrBlank()) {
            result.success(unavailableCommandResult(FAILURE_MALFORMED_PAYLOAD))
            return
        }
        result.success(
            ChatGenerationForegroundService
                .removeOrResolveTimeout(activity, token, conversationId)
                .toMap(),
        )
    }

    private fun handleFail(call: MethodCall, result: MethodChannel.Result) {
        val payload = parsePayloadArgument(call)
        if (payload == null) {
            result.success(unavailableCommandResult(FAILURE_MALFORMED_PAYLOAD))
            return
        }
        result.success(ChatGenerationForegroundService.failOrResolveTimeout(activity, payload).toMap())
    }

    private fun handleTakePendingOpenConversation(result: MethodChannel.Result) {
        val id = pendingOpenConversation
        pendingOpenConversation = null
        result.success(id)
    }

    private fun parsePayloadArgument(call: MethodCall): NativeNotificationPayload? {
        val arguments = call.arguments
        if (arguments !is Map<*, *>) return null
        return parseNotificationPayload(arguments)
    }

    private fun finishStart(commandId: Long, nativeResult: NativeCommandResult) {
        val result = pendingStarts.remove(commandId) ?: return
        result.success(nativeResult.toMap())
    }

    // ── Kotlin -> Dart 回调 ───────────────────────────────────────────────

    private fun emitOpenConversation(conversationId: String) {
        if (instance !== this) return
        channel.invokeMethod(
            CALLBACK_OPEN_CONVERSATION_REQUESTED,
            mapOf(KEY_CONVERSATION_ID to conversationId),
            object : MethodChannel.Result {
                override fun success(value: Any?) {
                    if (value == true) {
                        // Dart 已通过 stream 收到，不再需要 pending 槽。
                        clearPendingIf(conversationId)
                    }
                    // false/null：保留 pending 槽，等 takePendingOpenConversation 取走。
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

                override fun notImplemented() {}
            },
        )
    }

    private fun clearPendingIf(conversationId: String) {
        if (pendingOpenConversation == conversationId) {
            pendingOpenConversation = null
        }
    }

    private fun logCategory(category: String) {
        Log.w(TAG, "category=$category sdk=${Build.VERSION.SDK_INT}")
    }

    companion object {
        private const val TAG = "ChatGenerationFgs"
        private const val PERMISSION_PREFS = "chat_generation_notifications"
        private const val KEY_POST_NOTIFICATIONS_REQUESTED = "post_notifications_requested"
        private const val REQUEST_POST_NOTIFICATIONS = 4102

        @Volatile
        private var instance: ChatGenerationForegroundChannel? = null

        /** 冷启动打开会话的最后一个 conversation ID，取走一次后清空。 */
        @Volatile
        private var pendingOpenConversation: String? = null

        // ── Service 侧回调 ──────────────────────────────────────────────

        /** Service 在 startForeground 成功后才回 accepted ACK。 */
        internal fun completeStart(commandId: Long, nativeResult: NativeCommandResult) {
            instance?.finishStart(commandId, nativeResult)
        }

        /**
         * 发出 stopRequested；只有 Dart adapter 类型校验并加入 stream 后返回
         * true 才等待 Dart terminal，否则立即做原生幂等清理。
         */
        fun emitStopRequested(token: Long, conversationId: String) {
            val current = instance
            if (current == null) {
                ChatGenerationForegroundService.onStopNotAccepted(token, conversationId)
                return
            }
            current.channel.invokeMethod(
                CALLBACK_STOP_REQUESTED,
                mapOf(KEY_TOKEN to token, KEY_CONVERSATION_ID to conversationId),
                object : MethodChannel.Result {
                    override fun success(value: Any?) {
                        if (value != true) {
                            ChatGenerationForegroundService.onStopNotAccepted(token, conversationId)
                        }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        ChatGenerationForegroundService.onStopNotAccepted(token, conversationId)
                    }

                    override fun notImplemented() {
                        ChatGenerationForegroundService.onStopNotAccepted(token, conversationId)
                    }
                },
            )
        }

        /** Android 15 timeout 后的 best-effort 通知，不等待 Dart 返回。 */
        fun emitTimedOut(token: Long, conversationId: String) {
            val current = instance ?: return
            current.channel.invokeMethod(
                CALLBACK_FOREGROUND_SERVICE_TIMED_OUT,
                mapOf(KEY_TOKEN to token, KEY_CONVERSATION_ID to conversationId),
                object : MethodChannel.Result {
                    override fun success(value: Any?) {}

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

                    override fun notImplemented() {}
                },
            )
        }
    }
}
