package yuzu.shiki.oh_my_llm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 前台服务原生协议的纯 JVM 测试：token 守卫、timeout 瞬态记录与载荷解析。
 * 只依赖 Protocol 中的纯 Kotlin 类型，不触碰 Android 框架。
 */
class ChatGenerationForegroundProtocolTest {

    /** 构造一份合法的载荷 map，默认带 stop 动作。 */
    private fun validMap(
        token: Any = 42L,
        conversationId: String = "conv-1",
        title: String = "正在生成",
        text: String = "正文 1 字 · 推理 0 字",
        publicTitle: String = "正在生成",
        publicText: String = "请打开应用查看进度",
        actionKind: String = "stop",
        actionLabel: String? = "停止生成",
    ): Map<String, Any?> = mapOf(
        KEY_TOKEN to token,
        KEY_CONVERSATION_ID to conversationId,
        KEY_TITLE to title,
        KEY_TEXT to text,
        KEY_PUBLIC_TITLE to publicTitle,
        KEY_PUBLIC_TEXT to publicText,
        KEY_ACTION_KIND to actionKind,
        KEY_ACTION_LABEL to actionLabel,
    )

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

    // ── TimedOutNotificationGuard ─────────────────────────────────────────

    @Test
    fun timeout记录仅精确匹配token加conversationId组合() {
        val registry = TimedOutNotificationGuard()
        assertEquals(TokenDecision.ACCEPTED, registry.record(5L, "conv-5"))
        assertTrue(registry.matches(5L, "conv-5"))
        assertFalse(registry.matches(6L, "conv-5"))
        assertFalse(registry.matches(5L, "conv-6"))
        assertFalse(registry.matches(6L, "conv-6"))
    }

    @Test
    fun 空白conversationId的timeout记录为malformed() {
        val registry = TimedOutNotificationGuard()
        assertEquals(TokenDecision.MALFORMED, registry.record(5L, " "))
        assertEquals(TokenDecision.MALFORMED, registry.record(5L, ""))
        assertFalse(registry.matches(5L, " "))
    }

    @Test
    fun timeout记录clear后终态命令为stale() {
        val registry = TimedOutNotificationGuard()
        registry.record(5L, "conv-5")
        registry.clear()
        assertFalse(registry.matches(5L, "conv-5"))
    }

    // ── 载荷解析 ─────────────────────────────────────────────────────────

    @Test
    fun 合法载荷按字段解析为NativeNotificationPayload() {
        val payload = parseNotificationPayload(validMap())
        assertTrue(payload != null)
        payload ?: return
        assertEquals(42L, payload.token)
        assertEquals("conv-1", payload.conversationId)
        assertEquals("正在生成", payload.title)
        assertEquals("正文 1 字 · 推理 0 字", payload.text)
        assertEquals("正在生成", payload.publicTitle)
        assertEquals("请打开应用查看进度", payload.publicText)
        assertEquals(NotificationActionKind.Stop, payload.actionKind)
        assertEquals("停止生成", payload.actionLabel)
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
    fun actionLabel与actionKind不匹配时解析失败() {
        // none 动作携带非空 label
        assertNull(parseNotificationPayload(validMap(actionKind = "none", actionLabel = "停止生成")))
        // stop / openConversation 动作缺失或空白 label
        assertNull(parseNotificationPayload(validMap(actionKind = "stop", actionLabel = null)))
        assertNull(parseNotificationPayload(validMap(actionKind = "stop", actionLabel = " ")))
        assertNull(parseNotificationPayload(validMap(actionKind = "openConversation", actionLabel = null)))
    }

    @Test
    fun none动作允许空label且openConversation动作可解析() {
        val nonePayload = parseNotificationPayload(
            validMap(actionKind = "none", actionLabel = null),
        )
        assertEquals(NotificationActionKind.None, nonePayload?.actionKind)
        assertNull(nonePayload?.actionLabel)

        val openPayload = parseNotificationPayload(
            validMap(actionKind = "openConversation", actionLabel = "查看详情"),
        )
        assertEquals(NotificationActionKind.OpenConversation, openPayload?.actionKind)
        assertEquals("查看详情", openPayload?.actionLabel)
    }

    @Test
    fun 缺失关键字段的map解析失败() {
        val map = validMap()
        assertNull(parseNotificationPayload(map - KEY_TOKEN))
        assertNull(parseNotificationPayload(map - KEY_CONVERSATION_ID))
        assertNull(parseNotificationPayload(map - KEY_TITLE))
        assertNull(parseNotificationPayload(map - KEY_ACTION_KIND))
        assertNull(parseNotificationPayload(emptyMap<String, Any?>()))
    }

    @Test
    fun 非Map参数不参与解析返回null() {
        assertNull(parseNotificationPayload(null))
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
