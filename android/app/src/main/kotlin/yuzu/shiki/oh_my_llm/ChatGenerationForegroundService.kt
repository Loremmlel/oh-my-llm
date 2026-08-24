package yuzu.shiki.oh_my_llm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat

/**
 * 聊天生成前台服务：只在用户可见 Activity 发起的 generation 处于
 * preparing/streaming 期间以 `dataSync` 类型保持前台。只管理前台状态、
 * 标准通知、token 守卫与 Android 生命周期，不发送 LLM 请求、不访问 SQLite、
 * 不理解 Riverpod，不持有 API key/prompt/回复正文/推理/URL/响应体。
 *
 * start 由 Channel 通过显式内部 action 启动并携带原生 command ID；
 * update/remove 在 Service 活跃后由同进程活跃实例直接派发，避免后台
 * 再次 startService 与 stop-after-restart 竞态。活跃实例只保存 Service
 * 自身引用，不保存 Activity，并在 onDestroy 清除。
 *
 * 终态展示不属于本服务：普通错误/超时留存路径已由 HIGH 终态通知取代，
 * 这里只在 dataSync 超时时先移除 ongoing 并报告 Dart，ACK 未受理才退回
 * 原生固定 fallback（见 [showTimeoutFallback]）。
 */
class ChatGenerationForegroundService : Service() {

    private val tokenGuard = ActiveGenerationTokenGuard()
    private var activeConversationId: String? = null
    private var activePayload: NativeNotificationPayload? = null

    /** Dart 预编码的超时激活 payload；fallback 原样复用，不解析内容。 */
    private var activeTimeoutActivationPayload: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            SERVICE_START_ACTION -> handleStartCommand(intent, startId)
            NOTIFICATION_ACTION_STOP -> handleStopAction(intent, startId)
            else -> logCategory("unexpected_command")
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopAndRemoveNotification()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        clearActiveInstance(this)
        tokenGuard.clear()
        activeConversationId = null
        activePayload = null
        activeTimeoutActivationPayload = null
        super.onDestroy()
    }

    // ── 启动与停止动作 ────────────────────────────────────────────────────

    private fun handleStartCommand(intent: Intent, startId: Int) {
        val commandId = intent.getLongExtra(EXTRA_COMMAND_ID, -1L)
        val payload = parsePayloadFromIntent(intent)
        if (payload == null || commandId < 0) {
            logCategory("malformed_start")
            if (commandId >= 0) {
                ChatGenerationNotificationChannel.completeStart(
                    commandId,
                    NativeCommandResult.Unavailable(FAILURE_MALFORMED_PAYLOAD),
                )
            }
            // malformed start 在前台窗口内立即 stopSelf，不等待 promotion
            // deadline；已有活跃 generation 时保留前台状态，不误杀当前通知。
            if (tokenGuard.activeToken == null) stopSelf(startId)
            return
        }
        when (tokenGuard.start(payload.token)) {
            TokenDecision.ACCEPTED -> {}
            TokenDecision.STALE -> {
                logCategory("stale_start")
                ChatGenerationNotificationChannel.completeStart(
                    commandId,
                    NativeCommandResult.Unavailable(FAILURE_STALE_TOKEN),
                )
                // 不停止当前活跃 generation。
                return
            }
            TokenDecision.MALFORMED -> {
                // 解析已保证 token 为正，此分支仅为穷举守卫。
                logCategory("malformed_start")
                ChatGenerationNotificationChannel.completeStart(
                    commandId,
                    NativeCommandResult.Unavailable(FAILURE_MALFORMED_PAYLOAD),
                )
                if (tokenGuard.activeToken == null) stopSelf(startId)
                return
            }
        }
        activeInstance = this
        activePayload = payload
        activeConversationId = payload.conversationId
        activeTimeoutActivationPayload = payload.timeoutActivationPayload
        ensureNotificationChannel()
        val notification = buildGenerationNotification(this, payload)
        try {
            ServiceCompat.startForeground(
                this,
                ONGOING_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } catch (e: SecurityException) {
            logCategory("foreground_security")
            clearActiveState()
            stopSelf(startId)
            ChatGenerationNotificationChannel.completeStart(
                commandId,
                NativeCommandResult.Unavailable(FAILURE_SECURITY),
            )
            return
        } catch (e: Exception) {
            logCategory("foreground_promotion_failed")
            clearActiveState()
            stopSelf(startId)
            ChatGenerationNotificationChannel.completeStart(
                commandId,
                NativeCommandResult.Unavailable(FAILURE_NATIVE_FAILURE),
            )
            return
        }
        // 只有 startForeground 成功后才会发送 accepted ACK。
        ChatGenerationNotificationChannel.completeStart(commandId, NativeCommandResult.Accepted)
    }

    private fun handleStopAction(intent: Intent, startId: Int) {
        val token = intent.getLongExtra(KEY_TOKEN, -1L)
        val conversationId = intent.getStringExtra(KEY_CONVERSATION_ID)
        if (token <= 0 || conversationId.isNullOrBlank()) {
            logCategory("malformed_stop_action")
            return
        }
        if (tokenGuard.accepts(token) != TokenDecision.ACCEPTED) {
            logCategory("stale_stop_action")
            return
        }
        // 先把通知替换为固定停止文案并移除所有动作，再发出 stopRequested。
        val title = activePayload?.title ?: STOPPING_TITLE
        try {
            ServiceCompat.startForeground(
                this,
                ONGOING_NOTIFICATION_ID,
                buildStoppingNotification(this, title, conversationId),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } catch (e: Exception) {
            logCategory("foreground_update_failed")
        }
        ChatGenerationNotificationChannel.emitStopRequested(token, conversationId)
    }

    // ── 活跃实例命令应用 ──────────────────────────────────────────────────

    private fun applyUpdate(payload: NativeNotificationPayload): NativeCommandResult {
        return when (tokenGuard.accepts(payload.token)) {
            TokenDecision.ACCEPTED -> {
                activePayload = payload
                activeConversationId = payload.conversationId
                activeTimeoutActivationPayload = payload.timeoutActivationPayload
                try {
                    ServiceCompat.startForeground(
                        this,
                        ONGOING_NOTIFICATION_ID,
                        buildGenerationNotification(this, payload),
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                    )
                    NativeCommandResult.Accepted
                } catch (e: SecurityException) {
                    logCategory("foreground_security")
                    NativeCommandResult.Unavailable(FAILURE_SECURITY)
                } catch (e: Exception) {
                    logCategory("foreground_update_failed")
                    NativeCommandResult.Unavailable(FAILURE_NATIVE_FAILURE)
                }
            }
            TokenDecision.STALE -> NativeCommandResult.Unavailable(FAILURE_STALE_TOKEN)
            TokenDecision.MALFORMED -> NativeCommandResult.Unavailable(FAILURE_MALFORMED_PAYLOAD)
        }
    }

    private fun removeActive() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun stopAndRemoveNotification() {
        NotificationManagerCompat.from(this).cancel(ONGOING_NOTIFICATION_ID)
        stopSelf()
    }

    private fun clearActiveState() {
        clearActiveInstance(this)
        tokenGuard.clear()
        activePayload = null
        activeConversationId = null
        activeTimeoutActivationPayload = null
    }

    // ── Android 15 dataSync timeout ───────────────────────────────────────

    /**
     * 前台保护超时：先移除 ongoing 通知并停止前台服务，再向 Dart 报告事件。
     * 只有严格 ACK true 表示事件已进入 Dart（终态通知由 Dart 展示）；false、
     * 异常或 engine 已 detach 都立即执行原生 HIGH 固定 fallback。ACK 只覆盖
     * 「Dart handler 是否连接」，不是 durable delivery。
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        val token = tokenGuard.activeToken
        val conversationId = activeConversationId
        val savedPayload = activeTimeoutActivationPayload
        stopAndRemoveNotification()
        tokenGuard.clear()
        clearActiveInstance(this)
        if (token != null && conversationId != null) {
            ChatGenerationNotificationChannel.emitForegroundServiceTimedOut(
                token,
                conversationId,
            ) {
                showTimeoutFallback(applicationContext, savedPayload)
            }
        }
    }

    // ── 基础设施 ──────────────────────────────────────────────────────────

    private fun parsePayloadFromIntent(intent: Intent): NativeNotificationPayload? {
        if (!intent.hasExtra(KEY_TOKEN) || !intent.hasExtra(KEY_CONVERSATION_ID) ||
            !intent.hasExtra(KEY_TITLE) || !intent.hasExtra(KEY_TEXT) ||
            !intent.hasExtra(KEY_PUBLIC_TITLE) || !intent.hasExtra(KEY_PUBLIC_TEXT) ||
            !intent.hasExtra(KEY_ACTION_KIND) ||
            !intent.hasExtra(KEY_TIMEOUT_ACTIVATION_PAYLOAD)
        ) {
            return null
        }
        val map = mapOf(
            KEY_TOKEN to intent.getLongExtra(KEY_TOKEN, 0L),
            KEY_CONVERSATION_ID to intent.getStringExtra(KEY_CONVERSATION_ID),
            KEY_TITLE to intent.getStringExtra(KEY_TITLE),
            KEY_TEXT to intent.getStringExtra(KEY_TEXT),
            KEY_PUBLIC_TITLE to intent.getStringExtra(KEY_PUBLIC_TITLE),
            KEY_PUBLIC_TEXT to intent.getStringExtra(KEY_PUBLIC_TEXT),
            KEY_ACTION_KIND to intent.getStringExtra(KEY_ACTION_KIND),
            KEY_ACTION_LABEL to
                if (intent.hasExtra(KEY_ACTION_LABEL)) intent.getStringExtra(KEY_ACTION_LABEL) else null,
            KEY_TIMEOUT_ACTIVATION_PAYLOAD to intent.getStringExtra(KEY_TIMEOUT_ACTIVATION_PAYLOAD),
        )
        return parseNotificationPayload(map)
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            manager.createNotificationChannel(
                NotificationChannel(
                    ONGOING_CHANNEL_ID,
                    getString(R.string.chat_generation_notification_channel_name),
                    ONGOING_CHANNEL_IMPORTANCE,
                ).apply {
                    description = getString(R.string.chat_generation_notification_channel_description)
                },
            )
        } catch (e: Exception) {
            // OEM 建渠道失败不致命：不阻塞 accepted ACK，startForeground 仍按
            // 无渠道 best-effort 继续（与终态 ensureTerminalChannel 同一策略）。
            logCategory("channel_create_failed")
        }
    }

    private fun logCategory(category: String) {
        Log.w(TAG, "category=$category sdk=${Build.VERSION.SDK_INT}")
    }

    companion object {
        @Volatile
        private var activeInstance: ChatGenerationForegroundService? = null

        // ── 活跃实例派发（仅主线程） ────────────────────────────────────

        internal fun update(payload: NativeNotificationPayload): NativeCommandResult {
            val instance = activeInstance
                ?: return NativeCommandResult.Unavailable(FAILURE_SERVICE_UNAVAILABLE)
            return instance.applyUpdate(payload)
        }

        internal fun remove(
            token: Long,
            conversationId: String,
        ): NativeCommandResult {
            val instance = activeInstance
                ?: return NativeCommandResult.Unavailable(FAILURE_SERVICE_UNAVAILABLE)
            return when (instance.tokenGuard.accepts(token)) {
                TokenDecision.ACCEPTED -> {
                    instance.removeActive()
                    NativeCommandResult.Accepted
                }
                TokenDecision.STALE ->
                    NativeCommandResult.Unavailable(FAILURE_STALE_TOKEN)
                TokenDecision.MALFORMED ->
                    NativeCommandResult.Unavailable(FAILURE_MALFORMED_PAYLOAD)
            }
        }

        /** engine detach 清理：取消 ongoing 通知并停止活跃服务。 */
        internal fun stopForEngineDetach(context: Context) {
            NotificationManagerCompat.from(context)
                .cancel(ONGOING_NOTIFICATION_ID)
            activeInstance?.stopAndRemoveNotification()
        }

        /** Dart 未受理 stop 事件时，做原生幂等清理：移除通知并停止 Service。 */
        internal fun onStopNotAccepted(token: Long, conversationId: String) {
            val instance = activeInstance ?: return
            if (instance.tokenGuard.accepts(token) != TokenDecision.ACCEPTED) return
            instance.removeActive()
        }

        private fun logCategory(category: String) {
            Log.w(TAG, "category=$category sdk=${Build.VERSION.SDK_INT}")
        }

        private fun clearActiveInstance(service: ChatGenerationForegroundService) {
            if (activeInstance === service) {
                activeInstance = null
            }
        }
    }
}

// ── ongoing 通知构建（LOW 静音渠道契约） ─────────────────────────────────

private const val TAG = "ChatGenerationFgs"

private const val STOP_ACTION_FALLBACK_LABEL = "停止"
private const val STOPPING_TITLE = "正在停止"
private const val STOPPING_TEXT = "正在停止并保存已有内容"
private const val PUBLIC_ONGOING_TITLE = "正在生成"
private const val PUBLIC_ONGOING_TEXT = "请打开应用查看进度"

/** 构建进行中的静音通知；动作只保留停止，点击本体直达对应会话。 */
private fun buildGenerationNotification(
    context: Context,
    payload: NativeNotificationPayload,
): Notification {
    val builder = NotificationCompat.Builder(context, ONGOING_CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_chat_generation)
        .setContentTitle(payload.title)
        .setContentText(payload.text)
        .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        .setOnlyAlertOnce(true)
        .setSilent(true)
        .setOngoing(true)
        .setAutoCancel(false)
        .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
        .setContentIntent(openConversationPendingIntent(context, payload.conversationId))
        .setPublicVersion(publicVersion(context, PUBLIC_ONGOING_TITLE, PUBLIC_ONGOING_TEXT))
    when (payload.actionKind) {
        NotificationActionKind.None -> {}
        NotificationActionKind.Stop -> builder.addAction(
            0,
            payload.actionLabel ?: STOP_ACTION_FALLBACK_LABEL,
            stopPendingIntent(context, payload.token, payload.conversationId),
        )
    }
    return builder.build()
}

private fun buildStoppingNotification(context: Context, title: String, conversationId: String): Notification {
    return NotificationCompat.Builder(context, ONGOING_CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_chat_generation)
        .setContentTitle(title)
        .setContentText(STOPPING_TEXT)
        .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        .setOnlyAlertOnce(true)
        .setSilent(true)
        .setOngoing(true)
        .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
        .setContentIntent(openConversationPendingIntent(context, conversationId))
        .setPublicVersion(publicVersion(context, PUBLIC_ONGOING_TITLE, PUBLIC_ONGOING_TEXT))
        .build()
}

/** 锁屏/公开副本只使用固定安全文案，绝不携带业务正文。 */
private fun publicVersion(context: Context, title: String, text: String): Notification {
    return NotificationCompat.Builder(context, ONGOING_CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_chat_generation)
        .setContentTitle(title)
        .setContentText(text)
        .build()
}

/** 停止动作指向 Service 自身，只携带 token + conversation ID。 */
private fun stopPendingIntent(context: Context, token: Long, conversationId: String): PendingIntent {
    val intent = Intent(context, ChatGenerationForegroundService::class.java).apply {
        action = NOTIFICATION_ACTION_STOP
        putExtra(KEY_TOKEN, token)
        putExtra(KEY_CONVERSATION_ID, conversationId)
    }
    return PendingIntent.getService(
        context,
        STOP_PENDING_REQUEST_CODE,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/** 打开会话动作指向 MainActivity，只携带 conversation ID（既有 ongoing 契约）。 */
private fun openConversationPendingIntent(context: Context, conversationId: String): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
        action = NOTIFICATION_ACTION_OPEN_CONVERSATION
        putExtra(KEY_CONVERSATION_ID, conversationId)
    }
    return PendingIntent.getActivity(
        context,
        OPEN_CONVERSATION_PENDING_REQUEST_CODE,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}
