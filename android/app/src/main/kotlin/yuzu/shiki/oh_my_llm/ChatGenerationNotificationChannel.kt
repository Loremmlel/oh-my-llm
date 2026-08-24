package yuzu.shiki.oh_my_llm

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 聊天生成通知的原生 MethodChannel：接收 Dart 的命令（前台服务、终态通知、
 * 系统设置三类职责共享一条通道），持有 start 的挂起结果（按原生内部递增
 * commandId 关联），并暴露 companion 回调供 Service 回 ACK / 发送 stop/open/
 * timeout/notificationActivated 事件。任何通道失败都映射为固定失败分类，
 * 不向 Dart 抛出、不记录 payload 或异常原文。
 */
class ChatGenerationNotificationChannel(
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
            METHOD_TAKE_PENDING_OPEN_CONVERSATION -> handleTakePendingOpenConversation(result)
            METHOD_SHOW_TERMINAL_NOTIFICATION -> handleShowTerminalNotification(call, result)
            METHOD_TAKE_PENDING_NOTIFICATION_ACTIVATION ->
                handleTakePendingNotificationActivation(result)
            METHOD_GET_NOTIFICATION_SETTINGS_STATUS ->
                handleGetNotificationSettingsStatus(result)
            METHOD_OPEN_NOTIFICATION_SETTINGS -> handleOpenNotificationSettings(result)
            else -> result.notImplemented()
        }
    }

    /**
     * 通知点击 Intent 分发：ongoing 点击直达会话与终态/fallback 点击激活是
     * 两条互不重叠的窄路径，按 action 显式路由；未知 action 静默忽略。
     */
    fun handleNotificationIntent(intent: Intent?) {
        when (intent?.action) {
            NOTIFICATION_ACTION_OPEN_CONVERSATION -> handleOpenConversationIntent(intent)
            NOTIFICATION_ACTION_GENERATION_ACTIVATED -> handleNotificationActivatedIntent(intent)
        }
    }

    /**
     * ongoing 通知点击打开会话：总是先缓存到最后 conversation ID（冷启动兜底），
     * 再向 warm engine 发送 openConversationRequested；Dart 受理返回 true
     * 时清除该缓存，避免经 stream 与 takePendingOpenConversation 双重投递。
     */
    fun handleOpenConversationIntent(intent: Intent) {
        val conversationId = intent.getStringExtra(KEY_CONVERSATION_ID) ?: return
        if (conversationId.isBlank()) return
        pendingOpenConversation = conversationId
        emitOpenConversation(conversationId)
    }

    /**
     * 终态通知/timeout fallback 点击激活：payload 原样缓存到单槽（后一次覆盖
     * 前一次），再向 warm engine 发送 notificationActivated；Dart 受理返回 true
     * 时清槽，否则留给 takePendingNotificationActivation 取走一次。
     */
    fun handleNotificationActivatedIntent(intent: Intent) {
        val payload = intent.getStringExtra(KEY_PAYLOAD) ?: return
        if (payload.isEmpty()) return
        pendingNotificationActivation = payload
        emitNotificationActivated(payload)
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
        // 超时兜底：原生 ACK 迟迟不到（进程被杀 / handleStartCommand 抛错）时
        // 按通道超时收束挂起结果并清理，避免 MethodChannel.Result 泄漏到进程
        // 结束。completeStart 先到时 finishStart 已移除 entry，本定时器随后
        // no-op（finishStart 幂等）。
        Handler(Looper.getMainLooper()).postDelayed(
            {
                finishStart(
                    commandId,
                    NativeCommandResult.Unavailable(FAILURE_CHANNEL_TIMEOUT),
                )
            },
            START_ACK_TIMEOUT_MS,
        )
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
            putExtra(KEY_TIMEOUT_ACTIVATION_PAYLOAD, payload.timeoutActivationPayload)
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
            ChatGenerationForegroundService.remove(token, conversationId).toMap(),
        )
    }

    private fun handleTakePendingOpenConversation(result: MethodChannel.Result) {
        val id = pendingOpenConversation
        pendingOpenConversation = null
        result.success(id)
    }

    /** 展示终态通知：解析失败、权限/开关不可用或原生失败都回 false，Dart fail-open 后可重试。 */
    private fun handleShowTerminalNotification(call: MethodCall, result: MethodChannel.Result) {
        val request =
            parseTerminalNotificationRequest(call.arguments as? Map<*, *>)
        if (request == null) {
            result.success(false)
            return
        }
        val notificationsEnabled =
            NotificationManagerCompat.from(activity).areNotificationsEnabled()
        val postNotificationsGranted =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(
                    activity,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) == PackageManager.PERMISSION_GRANTED
        if (!shouldAcknowledgeTerminalShow(
                notificationsEnabled,
                postNotificationsGranted,
                Build.VERSION.SDK_INT,
            )
        ) {
            // 权限被拒/开关关闭时 notify 是静默 no-op：如实回 false，让 Dart
            // 不完成去重，权限恢复后仍可重试。
            logCategory("terminal_notification_denied")
            result.success(false)
            return
        }
        try {
            showTerminalNotification(activity, request)
            result.success(true)
        } catch (e: Exception) {
            logCategory("terminal_notification_failed")
            result.success(false)
        }
    }

    /**
     * 取走一次冷启动/无 listener 激活 payload；应答为 nullable map
     * `{payload: <原始字符串>}`，内容是否合法由 Dart 共享 codec 严格解码，
     * 这里不做二次校验。
     */
    private fun handleTakePendingNotificationActivation(result: MethodChannel.Result) {
        val payload = pendingNotificationActivation
        pendingNotificationActivation = null
        result.success(payload?.let { mapOf(KEY_PAYLOAD to it) })
    }

    /** 设置状态查询先幂等建渠道；获取系统服务失败映射为 unavailable。 */
    private fun handleGetNotificationSettingsStatus(result: MethodChannel.Result) {
        try {
            ensureTerminalChannel(activity)
            val manager =
                activity.getSystemService(android.app.NotificationManager::class.java)
            if (manager == null) {
                result.success(STATUS_UNAVAILABLE)
                return
            }
            val enabled =
                NotificationManagerCompat.from(activity).areNotificationsEnabled()
            val terminalImportance = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.getNotificationChannel(TERMINAL_CHANNEL_ID)?.importance
            } else {
                null
            }
            result.success(
                resolveNotificationSettingsStatus(
                    notificationsEnabled = enabled,
                    terminalChannelImportance = terminalImportance,
                    sdkInt = Build.VERSION.SDK_INT,
                ),
            )
        } catch (e: Exception) {
            logCategory("settings_status_failed")
            result.success(STATUS_UNAVAILABLE)
        }
    }

    /** 打开系统通知设置页；无 Activity handler 或抛错回 false，不崩溃。 */
    private fun handleOpenNotificationSettings(result: MethodChannel.Result) {
        try {
            val spec = appNotificationSettingsSpec(activity.packageName)
            val intent = Intent(spec.action).apply {
                putExtra(spec.packageExtraKey, spec.packageName)
                if (spec.needsNewTaskFlag) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            logCategory("open_settings_failed")
            result.success(false)
        }
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

    private fun emitNotificationActivated(payload: String) {
        if (instance !== this) return
        channel.invokeMethod(
            CALLBACK_NOTIFICATION_ACTIVATED,
            payload,
            object : MethodChannel.Result {
                override fun success(value: Any?) {
                    if (value == true) {
                        // Dart 已受理（进入流或本地暂存槽），原生槽位可以清空。
                        clearPendingActivationIf(payload)
                    }
                    // false/null：保留单槽，等 takePendingNotificationActivation 取走。
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

                override fun notImplemented() {}
            },
        )
    }

    private fun clearPendingActivationIf(payload: String) {
        if (pendingNotificationActivation == payload) {
            pendingNotificationActivation = null
        }
    }

    private fun logCategory(category: String) {
        Log.w(TAG, "category=$category sdk=${Build.VERSION.SDK_INT}")
    }

    companion object {
        /** start ACK 的 Kotlin 侧超时上界；与 Dart 侧 2s 通道超时对齐。 */
        const val START_ACK_TIMEOUT_MS = 2_000L
        private const val TAG = "ChatGenerationFgs"
        private const val PERMISSION_PREFS = "chat_generation_notifications"
        private const val KEY_POST_NOTIFICATIONS_REQUESTED = "post_notifications_requested"
        private const val REQUEST_POST_NOTIFICATIONS = 4102

        @Volatile
        private var instance: ChatGenerationNotificationChannel? = null

        /** 冷启动打开会话的最后一个 conversation ID，取走一次后清空。 */
        @Volatile
        private var pendingOpenConversation: String? = null

        /** 终态激活 payload 单槽：后一次点击覆盖前一次，取走一次后清空。 */
        @Volatile
        private var pendingNotificationActivation: String? = null

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

        /**
         * 发出 foregroundServiceTimedOut 并按 ACK 决策 fallback：只有严格 true
         * 表示事件已进入 Dart（由 Dart 展示终态通知）；false、null、异常、
         * 未实现或 engine 已 detach 都立即执行 [onNotAccepted] 原生 HIGH fallback。
         * ACK 不等待通知展示完成，也不承诺 durable delivery。
         */
        fun emitForegroundServiceTimedOut(
            token: Long,
            conversationId: String,
            onNotAccepted: () -> Unit,
        ) {
            val current = instance
            if (current == null) {
                onNotAccepted()
                return
            }
            current.channel.invokeMethod(
                CALLBACK_FOREGROUND_SERVICE_TIMED_OUT,
                mapOf(KEY_TOKEN to token, KEY_CONVERSATION_ID to conversationId),
                object : MethodChannel.Result {
                    override fun success(value: Any?) {
                        if (!isTimeoutAcceptedByDart(value)) onNotAccepted()
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        onNotAccepted()
                    }

                    override fun notImplemented() {
                        onNotAccepted()
                    }
                },
            )
        }
    }
}
