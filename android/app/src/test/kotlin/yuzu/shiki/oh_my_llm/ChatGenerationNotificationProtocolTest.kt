package yuzu.shiki.oh_my_llm

import android.app.NotificationManager
import android.provider.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 聊天生成通知协议的纯 JVM 测试：token 守卫、载荷解析（含 Dart 预编码超时
 * payload 的类型/长度校验）、终态通知请求解码、request code 推导、
 * timeout fallback 决策、渠道配置常量与设置状态判定。
 *
 * 只依赖 Protocol 与 TerminalNotification 中的纯 Kotlin 类型；framework 行为
 * （真实横幅/声音）不在本文件伪装已验证，留给 smoke。
 */
class ChatGenerationNotificationProtocolTest {

    /** 构造一份合法的 ongoing 载荷 map，默认带 stop 动作。 */
    private fun validMap(
        token: Any = 42L,
        conversationId: String = "conv-1",
        title: String = "正在生成",
        text: String = "正文 1 字 · 推理 0 字",
        publicTitle: String = "正在生成",
        publicText: String = "请打开应用查看进度",
        actionKind: String = "stop",
        actionLabel: String? = "停止生成",
        timeoutActivationPayload: Any = TIMEOUT_PAYLOAD,
    ): Map<String, Any?> = mapOf(
        KEY_TOKEN to token,
        KEY_CONVERSATION_ID to conversationId,
        KEY_TITLE to title,
        KEY_TEXT to text,
        KEY_PUBLIC_TITLE to publicTitle,
        KEY_PUBLIC_TEXT to publicText,
        KEY_ACTION_KIND to actionKind,
        KEY_ACTION_LABEL to actionLabel,
        KEY_TIMEOUT_ACTIVATION_PAYLOAD to timeoutActivationPayload,
    )

    /** 构造一份合法的终态通知请求 map。 */
    private fun validTerminalMap(
        id: Any = 1_672_833_428L,
        title: String = "生成完成",
        body: String = "正文 12 字 · 推理 0 字",
        publicTitle: String = "生成完成",
        publicBody: String = "请打开应用查看",
        payload: Any =
            """{"v":1,"eventKey":"$TIMEOUT_EVENT_KEY","conversationId":"conv-1"}""",
    ): Map<String, Any?> = mapOf(
        KEY_ID to id,
        KEY_TITLE to title,
        KEY_BODY to body,
        KEY_PUBLIC_TITLE to publicTitle,
        KEY_PUBLIC_BODY to publicBody,
        KEY_PAYLOAD to payload,
    )

    companion object {
        /** 固定测试 session 的合法 v1 超时 payload（Dart 共享 codec 同形产物）。 */
        private const val TIMEOUT_PAYLOAD =
            """{"v":1,"eventKey":"v1:000102030405060708090a0b0c0d0e0f:42:""" +
                """foregroundProtectionTimedOut","conversationId":"conv-1"}"""

        private const val TIMEOUT_EVENT_KEY =
            "v1:000102030405060708090a0b0c0d0e0f:42:foregroundProtectionTimedOut"
    }

    // ── 协议常量 ─────────────────────────────────────────────────────────

    @Test
    fun 通道名与方法回调常量与计划Section7逐字一致() {
        assertEquals(
            "yuzu.shiki.oh_my_llm/chat_generation_notifications",
            CHAT_GENERATION_CHANNEL,
        )
        assertEquals("ensureNotificationPermission", METHOD_ENSURE_NOTIFICATION_PERMISSION)
        assertEquals("startForegroundGeneration", METHOD_START_FOREGROUND_GENERATION)
        assertEquals("updateForegroundGeneration", METHOD_UPDATE_FOREGROUND_GENERATION)
        assertEquals("removeForegroundGeneration", METHOD_REMOVE_FOREGROUND_GENERATION)
        assertEquals("takePendingOpenConversation", METHOD_TAKE_PENDING_OPEN_CONVERSATION)
        assertEquals("showTerminalNotification", METHOD_SHOW_TERMINAL_NOTIFICATION)
        assertEquals(
            "takePendingNotificationActivation",
            METHOD_TAKE_PENDING_NOTIFICATION_ACTIVATION,
        )
        assertEquals(
            "getNotificationSettingsStatus",
            METHOD_GET_NOTIFICATION_SETTINGS_STATUS,
        )
        assertEquals("openNotificationSettings", METHOD_OPEN_NOTIFICATION_SETTINGS)
        assertEquals("stopRequested", CALLBACK_STOP_REQUESTED)
        assertEquals("openConversationRequested", CALLBACK_OPEN_CONVERSATION_REQUESTED)
        assertEquals("foregroundServiceTimedOut", CALLBACK_FOREGROUND_SERVICE_TIMED_OUT)
        assertEquals("notificationActivated", CALLBACK_NOTIFICATION_ACTIVATED)
        assertEquals("timeoutActivationPayload", KEY_TIMEOUT_ACTIVATION_PAYLOAD)
        assertEquals("body", KEY_BODY)
        assertEquals("publicBody", KEY_PUBLIC_BODY)
        assertEquals("payload", KEY_PAYLOAD)
    }

    // ── 渠道配置 ─────────────────────────────────────────────────────────

    @Test
    fun 终态渠道配置为HIGH且不是silent() {
        assertEquals("chat_generation_result", TERMINAL_CHANNEL_ID)
        assertEquals(
            NotificationManager.IMPORTANCE_HIGH,
            ChatGenerationTerminalNotificationSpec.CHANNEL_IMPORTANCE,
        )
        // HIGH importance + 默认通知声 + 振动三者共同构成「非 silent」契约。
        assertTrue(ChatGenerationTerminalNotificationSpec.CHANNEL_DEFAULT_NOTIFICATION_SOUND)
        assertTrue(ChatGenerationTerminalNotificationSpec.CHANNEL_VIBRATION_ENABLED)
    }

    @Test
    fun 前台渠道仍为LOW且silent() {
        assertEquals("chat_generation", ONGOING_CHANNEL_ID)
        assertEquals(
            NotificationManager.IMPORTANCE_LOW,
            ONGOING_CHANNEL_IMPORTANCE,
        )
        // 静音契约：不设置声音、不启用振动。
        assertTrue(ONGOING_CHANNEL_SILENT)
    }

    // ── ActiveGenerationTokenGuard ────────────────────────────────────────

    @Test
    fun 空守卫接受任意正整数token包括超出Int范围的Long() {
        val guard = ActiveGenerationTokenGuard()
        val largeToken = 3_000_000_000L
        assertEquals(TokenDecision.ACCEPTED, guard.start(largeToken))
        assertEquals(largeToken, guard.activeToken)
    }

    @Test
    fun 重复相同token的start幂等接受且不改变活跃token() {
        val guard = ActiveGenerationTokenGuard()
        assertEquals(TokenDecision.ACCEPTED, guard.start(7L))
        assertEquals(TokenDecision.ACCEPTED, guard.start(7L))
        assertEquals(7L, guard.activeToken)
    }

    @Test
    fun 不同token活跃时新start被拒绝为stale且不覆盖活跃token() {
        val guard = ActiveGenerationTokenGuard()
        assertEquals(TokenDecision.ACCEPTED, guard.start(1L))
        assertEquals(TokenDecision.STALE, guard.start(2L))
        assertEquals(1L, guard.activeToken)
    }

    @Test
    fun 非正token的start一律为malformed() {
        val guard = ActiveGenerationTokenGuard()
        assertEquals(TokenDecision.MALFORMED, guard.start(0L))
        assertEquals(TokenDecision.MALFORMED, guard.start(-5L))
        assertNull(guard.activeToken)
    }

    @Test
    fun update只接受当前活跃token其余为stale() {
        val guard = ActiveGenerationTokenGuard()
        guard.start(3L)
        assertEquals(TokenDecision.ACCEPTED, guard.accepts(3L))
        assertEquals(TokenDecision.STALE, guard.accepts(4L))
        assertEquals(TokenDecision.STALE, guard.accepts(2L))
    }

    @Test
    fun 无活跃token时update为stale() {
        val guard = ActiveGenerationTokenGuard()
        assertEquals(TokenDecision.STALE, guard.accepts(3L))
    }

    @Test
    fun 当前终态finish清除匹配token且后续命令为stale() {
        val guard = ActiveGenerationTokenGuard()
        guard.start(3L)
        assertEquals(TokenDecision.ACCEPTED, guard.finish(3L))
        assertNull(guard.activeToken)
        assertEquals(TokenDecision.STALE, guard.accepts(3L))
        assertEquals(TokenDecision.STALE, guard.finish(3L))
    }

    @Test
    fun 替换后的旧token终态为stale() {
        val guard = ActiveGenerationTokenGuard()
        guard.start(1L)
        guard.finish(1L)
        guard.start(2L)
        assertEquals(TokenDecision.STALE, guard.finish(1L))
        assertEquals(2L, guard.activeToken)
        assertEquals(TokenDecision.ACCEPTED, guard.finish(2L))
    }

    @Test
    fun finish只清除匹配token不误伤当前活跃token() {
        val guard = ActiveGenerationTokenGuard()
        guard.start(1L)
        assertEquals(TokenDecision.STALE, guard.finish(2L))
        assertEquals(1L, guard.activeToken)
    }

    // ── 载荷解析 ─────────────────────────────────────────────────────────

    @Test
    fun 合法载荷按字段解析为NativeNotificationPayload并携带超时payload() {
        val payload = parseNotificationPayload(validMap())
        assertTrue(payload != null)
        payload ?: return
        assertEquals(42L, payload.token)
        assertEquals("conv-1", payload.conversationId)
        assertEquals("正在生成", payload.title)
        assertEquals("正文 1 字 · 推理 0 字", payload.text)
        assertEquals(NotificationActionKind.Stop, payload.actionKind)
        assertEquals(TIMEOUT_PAYLOAD, payload.timeoutActivationPayload)
    }

    @Test
    fun Int型token同样被接受() {
        val payload = parseNotificationPayload(validMap(token = 42))
        assertEquals(42L, payload?.token)
    }

    @Test
    fun 空白conversationId解析失败() {
        assertNull(parseNotificationPayload(validMap(conversationId = "  ")))
        assertNull(parseNotificationPayload(validMap(conversationId = "")))
    }

    @Test
    fun 未知actionKind解析失败() {
        assertNull(parseNotificationPayload(validMap(actionKind = "bogus")))
        assertNull(parseNotificationPayload(validMap(actionKind = "Stop")))
        assertNull(parseNotificationPayload(validMap(actionKind = "OPEN")))
    }

    @Test
    fun 旧LOW终态的open_conversation动作已随统一终态激活移除() {
        // open 动作属于已删除的旧错误通知路径；ongoing 点击直达走 content intent。
        assertNull(parseActionKind("openConversation"))
        assertNull(parseNotificationPayload(validMap(actionKind = "openConversation", actionLabel = "查看")))
        assertEquals(NotificationActionKind.None, parseActionKind("none"))
        assertEquals(NotificationActionKind.Stop, parseActionKind("stop"))
    }

    @Test
    fun 非正或非整数token解析失败() {
        assertNull(parseNotificationPayload(validMap(token = 0L)))
        assertNull(parseNotificationPayload(validMap(token = -1L)))
        assertNull(parseNotificationPayload(validMap(token = 5.5)))
        assertNull(parseNotificationPayload(validMap(token = "42")))
        assertNull(parseNotificationPayload(validMap(token = true)))
    }

    @Test
    fun 空白title与text解析失败() {
        assertNull(parseNotificationPayload(validMap(title = " ")))
        assertNull(parseNotificationPayload(validMap(text = "")))
        assertNull(parseNotificationPayload(validMap(publicTitle = " ")))
        assertNull(parseNotificationPayload(validMap(publicText = "")))
    }

    @Test
    fun stop动作缺label而none动作带label时解析失败() {
        assertNull(parseNotificationPayload(validMap(actionKind = "none", actionLabel = "停止生成")))
        assertNull(parseNotificationPayload(validMap(actionKind = "stop", actionLabel = null)))
        assertNull(parseNotificationPayload(validMap(actionKind = "stop", actionLabel = " ")))
    }

    @Test
    fun none动作允许空label() {
        val nonePayload = parseNotificationPayload(
            validMap(actionKind = "none", actionLabel = null),
        )
        assertEquals(NotificationActionKind.None, nonePayload?.actionKind)
        assertNull(nonePayload?.actionLabel)
    }

    @Test
    fun 缺失关键字段的map解析失败() {
        val map = validMap()
        assertNull(parseNotificationPayload(map - KEY_TOKEN))
        assertNull(parseNotificationPayload(map - KEY_CONVERSATION_ID))
        assertNull(parseNotificationPayload(map - KEY_TITLE))
        assertNull(parseNotificationPayload(map - KEY_ACTION_KIND))
        assertNull(parseNotificationPayload(map - KEY_TIMEOUT_ACTIVATION_PAYLOAD))
        assertNull(parseNotificationPayload(emptyMap<String, Any?>()))
    }

    @Test
    fun 非Map参数不参与解析返回null() {
        assertNull(parseNotificationPayload(null))
    }

    // ── 超时激活 payload 校验（类型与长度，不解析 JSON 内容） ────────────────

    @Test
    fun Kotlin只校验timeout_payload类型与长度不解析JSON内容() {
        // 非 JSON 乱串只要类型正确且长度合规就原样接受——原生侧把它当不透明字段。
        val opaque = "{not-json::任意 不透明 文本}}"
        assertEquals(opaque, parseTimeoutActivationPayload(opaque))
        val payload = parseNotificationPayload(validMap(timeoutActivationPayload = opaque))
        assertTrue(payload != null)
        assertEquals(opaque, payload?.timeoutActivationPayload)
    }

    @Test
    fun timeout_payload缺失或类型错误一律拒绝() {
        assertNull(parseTimeoutActivationPayload(null))
        assertNull(parseTimeoutActivationPayload(42))
        assertNull(parseTimeoutActivationPayload(true))
        assertNull(parseNotificationPayload(validMap(timeoutActivationPayload = 42)))
    }

    @Test
    fun 空白timeout_payload拒绝() {
        assertNull(parseTimeoutActivationPayload(""))
        assertNull(parseTimeoutActivationPayload("   "))
        assertNull(parseNotificationPayload(validMap(timeoutActivationPayload = " ")))
    }

    @Test
    fun timeout_payload超过1024个UTF8字节拒绝且恰好1024接受() {
        assertTrue(parseTimeoutActivationPayload("a".repeat(1024)) != null)
        assertNull(parseTimeoutActivationPayload("a".repeat(1025)))
        // 中文每字 3 bytes：341 字 = 1023 bytes 通过，342 字 = 1026 bytes 拒绝。
        assertTrue(parseTimeoutActivationPayload("生".repeat(341)) != null)
        assertNull(parseTimeoutActivationPayload("生".repeat(342)))
    }

    // ── 终态通知请求解码 ─────────────────────────────────────────────────

    @Test
    fun 终态通知构造同时使用private和固定public文案() {
        val request = parseTerminalNotificationRequest(validTerminalMap())
        assertTrue(request != null)
        request ?: return
        assertEquals(1_672_833_428, request.id)
        assertEquals("生成完成", request.title)
        assertEquals("正文 12 字 · 推理 0 字", request.body)
        // 公开副本只取传入的固定 public 字段，绝不从 private 正文推导。
        assertEquals("生成完成" to "请打开应用查看", terminalPublicCopy(request))
    }

    @Test
    fun 终态请求缺任一文案或payload解析失败() {
        assertNull(parseTerminalNotificationRequest(validTerminalMap(title = " ")))
        assertNull(parseTerminalNotificationRequest(validTerminalMap(body = "")))
        assertNull(parseTerminalNotificationRequest(validTerminalMap(publicTitle = "")))
        assertNull(parseTerminalNotificationRequest(validTerminalMap(publicBody = " ")))
        assertNull(parseTerminalNotificationRequest(validTerminalMap(payload = "")))
        assertNull(parseTerminalNotificationRequest(validTerminalMap(payload = 42)))
        assertNull(parseTerminalNotificationRequest(null))
    }

    @Test
    fun 终态通知ID不与ongoing及fallback保留槽位冲突() {
        // Dart FNV 契约区间为 [10000, 2147483646]：低于下界的 ID 一律拒绝，
        // 因此天然避开 ongoing 4101 与 timeout fallback 4200。
        assertEquals(4101, ONGOING_NOTIFICATION_ID)
        assertEquals(4200, TERMINAL_TIMEOUT_FALLBACK_NOTIFICATION_ID)
        assertTrue(TERMINAL_TIMEOUT_FALLBACK_NOTIFICATION_ID < MIN_TERMINAL_NOTIFICATION_ID)
        assertNull(parseTerminalNotificationId(4101L))
        assertNull(parseTerminalNotificationId(4200L))
        assertNull(parseTerminalNotificationId(9999L))
        assertNull(parseTerminalNotificationId(0L))
        assertNull(parseTerminalNotificationId(-5L))
        assertNull(parseTerminalNotificationId(3_000_000_000L))
        assertNull(parseTerminalNotificationId("123456"))
        assertEquals(10_000, parseTerminalNotificationId(10_000L))
        assertEquals(2_147_483_646, parseTerminalNotificationId(2_147_483_646L))
    }

    @Test
    fun 每个终态PendingIntent_request_code由通知ID唯一推导且互不相同() {
        val ids = listOf(10_000, 16_728_334_28.toInt(), 2_147_483_646)
        ids.forEach { id ->
            // request code 与通知 ID 同源同值，不同终态互不覆盖。
            assertEquals(id, terminalPendingRequestCode(id))
        }
        assertEquals(ids.size, ids.map { terminalPendingRequestCode(it) }.toSet().size)
    }

    // ── 终态展示 ACK 决策 ───────────────────────────────────────────────

    @Test
    fun 权限未授予或通知禁用时终态展示不ACK成功() {
        assertTrue(
            shouldAcknowledgeTerminalShow(
                notificationsEnabled = true,
                postNotificationsGranted = true,
                sdkInt = 34,
            ),
        )
        assertFalse(
            shouldAcknowledgeTerminalShow(
                notificationsEnabled = false,
                postNotificationsGranted = true,
                sdkInt = 34,
            ),
        )
        assertFalse(
            shouldAcknowledgeTerminalShow(
                notificationsEnabled = true,
                postNotificationsGranted = false,
                sdkInt = 33,
            ),
        )
        // pre-33 无 POST_NOTIFICATIONS 权限概念：granted=false 也只取决于总开关。
        assertTrue(
            shouldAcknowledgeTerminalShow(
                notificationsEnabled = true,
                postNotificationsGranted = false,
                sdkInt = 32,
            ),
        )
        assertFalse(
            shouldAcknowledgeTerminalShow(
                notificationsEnabled = false,
                postNotificationsGranted = true,
                sdkInt = 26,
            ),
        )
    }

    // ── timeout fallback 决策 ─────────────────────────────────────────────

    @Test
    fun timeout_callback未受理时选择HIGH_fallback() {
        // 只有严格 bool true 表示事件已进入 Dart；其余全部退回原生 fallback。
        assertFalse(isTimeoutAcceptedByDart(false))
        assertFalse(isTimeoutAcceptedByDart(null))
        assertFalse(isTimeoutAcceptedByDart(1))
        assertFalse(isTimeoutAcceptedByDart("true"))
        assertTrue(isTimeoutAcceptedByDart(true))
    }

    @Test
    fun timeout_fallback固定使用通知ID与request_code_4200() {
        val fallback = timeoutFallbackRequest(TIMEOUT_PAYLOAD)
        assertEquals(4200, fallback.notificationId)
        assertEquals(TERMINAL_TIMEOUT_FALLBACK_NOTIFICATION_ID, fallback.notificationId)
        assertEquals(4200, timeoutFallbackPendingRequestCode())
    }

    @Test
    fun timeout_fallback原样复用Dart_session_scoped_payload() {
        val saved = """{"v":1,"eventKey":"$TIMEOUT_EVENT_KEY","conversationId":"conv-9"}"""
        val fallback = timeoutFallbackRequest(saved)
        // 原样复用：同一字符串原封不动进入 fallback 请求，不重建不解析。
        assertEquals(saved, fallback.payload)
        val opaque = "::not-parsed-anywhere::"
        assertEquals(opaque, timeoutFallbackRequest(opaque).payload)
        assertNull(timeoutFallbackRequest(null).payload)
    }

    @Test
    fun timeout_fallback文案与Dart固定安全文案保持一致() {
        // 与 default_chat_generation_terminal_notifications.dart 的
        // foregroundProtectionTimedOut 文案逐字一致；改任一端必须同步改
        // 另一端与两端测试（Dart 侧断言见同文件对应测试）。
        assertEquals(
            "后台保护已结束",
            ChatGenerationTerminalNotificationSpec.TIMEOUT_FALLBACK_TITLE,
        )
        assertEquals(
            "请打开应用查看生成状态",
            ChatGenerationTerminalNotificationSpec.TIMEOUT_FALLBACK_BODY,
        )
    }

    // ── ongoing 点击直达契约 ──────────────────────────────────────────────

    @Test
    fun ongoing_content_intent仍打开对应会话() {
        // 既有 ongoing 契约保持不变：点击本体直达对应会话，pending 兜底沿用。
        assertEquals(
            "yuzu.shiki.oh_my_llm.action.CHAT_GENERATION_OPEN_CONVERSATION",
            NOTIFICATION_ACTION_OPEN_CONVERSATION,
        )
        assertEquals(4104, OPEN_CONVERSATION_PENDING_REQUEST_CODE)
        assertEquals("takePendingOpenConversation", METHOD_TAKE_PENDING_OPEN_CONVERSATION)
    }

    // ── 设置状态与入口 ────────────────────────────────────────────────────

    @Test
    fun 首次设置状态查询创建终态channel且不重建已有channel() {
        // 只有尚不存在同 ID 渠道才创建；已有渠道绝不删除重建或升级 importance。
        assertTrue(shouldCreateTerminalChannel(null))
        assertFalse(shouldCreateTerminalChannel(TERMINAL_CHANNEL_ID))
        assertFalse(shouldCreateTerminalChannel("user-renamed-or-configured"))
    }

    @Test
    fun 通知禁用或终态渠道为NONE时返回disabled其余enabled() {
        assertEquals(
            SETTINGS_STATUS_DISABLED,
            resolveNotificationSettingsStatus(notificationsEnabled = false, terminalChannelImportance = null, sdkInt = 33),
        )
        assertEquals(
            SETTINGS_STATUS_DISABLED,
            resolveNotificationSettingsStatus(
                notificationsEnabled = true,
                terminalChannelImportance = NotificationManager.IMPORTANCE_NONE,
                sdkInt = 26,
            ),
        )
        // pre-26 没有 channel 概念，总开关开启即视为可用。
        assertEquals(
            SETTINGS_STATUS_ENABLED,
            resolveNotificationSettingsStatus(
                notificationsEnabled = true,
                terminalChannelImportance = NotificationManager.IMPORTANCE_NONE,
                sdkInt = 25,
            ),
        )
        assertEquals(
            SETTINGS_STATUS_ENABLED,
            resolveNotificationSettingsStatus(
                notificationsEnabled = true,
                terminalChannelImportance = null,
                sdkInt = 33,
            ),
        )
        assertEquals(
            SETTINGS_STATUS_ENABLED,
            resolveNotificationSettingsStatus(
                notificationsEnabled = true,
                terminalChannelImportance = NotificationManager.IMPORTANCE_HIGH,
                sdkInt = 34,
            ),
        )
    }

    @Test
    fun 打开设置Intent只使用当前package() {
        val spec = appNotificationSettingsSpec("yuzu.shiki.oh_my_llm")
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, spec.action)
        assertEquals(Settings.EXTRA_APP_PACKAGE, spec.packageExtraKey)
        assertEquals("yuzu.shiki.oh_my_llm", spec.packageName)
        assertTrue(spec.needsNewTaskFlag)
        // 只使用传入的当前 package，不带任何其他身份或深链参数。
        assertEquals("com.example.other", appNotificationSettingsSpec("com.example.other").packageName)
    }

    // ── start ACK 超时兜底 ──────────────────────────────────────────────

    @Test
    fun start_ACK_Kotlin侧超时与Dart通道超时对齐() {
        // Kotlin postDelayed 的兜底上界必须与 Dart 侧 2s 通道超时一致，
        // 否则一端先超时会留下不一致的 pending 状态。
        assertEquals(2_000L, ChatGenerationNotificationChannel.START_ACK_TIMEOUT_MS)
    }

    // ── 命令结果 map ──────────────────────────────────────────────────────

    @Test
    fun accepted命令结果只含accepted键() {
        val result = acceptedCommandResult()
        assertEquals(true, result["accepted"])
        assertNull(result["failureCode"])
    }

    @Test
    fun unavailable命令结果携带固定failureCode() {
        val result = unavailableCommandResult(FAILURE_STALE_TOKEN)
        assertEquals(false, result["accepted"])
        assertEquals(FAILURE_STALE_TOKEN, result["failureCode"])
    }
}
