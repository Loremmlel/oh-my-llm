package yuzu.shiki.oh_my_llm

/**
 * 聊天生成前台服务的原生协议定义：通道/方法/载荷键、命令结果 map、
 * 通知与渠道 ID、动作字符串、纯解析函数与 token/timeout 守卫。
 *
 * 本文件是纯 Kotlin，不依赖 Android 框架，可被 JVM 单元测试直接加载。
 * 所有常量与方法名必须与 Dart 侧 `AndroidChatGenerationForegroundService`
 * 以及 Section 1.3 协议逐字节一致。
 */

// ── 通道与方法名 ─────────────────────────────────────────────────────────

internal const val CHAT_GENERATION_CHANNEL =
    "yuzu.shiki.oh_my_llm/chat_generation_foreground_service"

internal const val METHOD_ENSURE_NOTIFICATION_PERMISSION =
    "ensureNotificationPermission"
internal const val METHOD_START_FOREGROUND_GENERATION =
    "startForegroundGeneration"
internal const val METHOD_UPDATE_FOREGROUND_GENERATION =
    "updateForegroundGeneration"
internal const val METHOD_REMOVE_FOREGROUND_GENERATION =
    "removeForegroundGeneration"
internal const val METHOD_FAIL_FOREGROUND_GENERATION =
    "failForegroundGeneration"
internal const val METHOD_TAKE_PENDING_OPEN_CONVERSATION =
    "takePendingOpenConversation"

internal const val CALLBACK_STOP_REQUESTED = "stopRequested"
internal const val CALLBACK_OPEN_CONVERSATION_REQUESTED =
    "openConversationRequested"
internal const val CALLBACK_FOREGROUND_SERVICE_TIMED_OUT =
    "foregroundServiceTimedOut"

// ── 载荷键（camelCase，与 Dart 侧一致） ──────────────────────────────────

internal const val KEY_TOKEN = "token"
internal const val KEY_CONVERSATION_ID = "conversationId"
internal const val KEY_TITLE = "title"
internal const val KEY_TEXT = "text"
internal const val KEY_PUBLIC_TITLE = "publicTitle"
internal const val KEY_PUBLIC_TEXT = "publicText"
internal const val KEY_ACTION_KIND = "actionKind"
internal const val KEY_ACTION_LABEL = "actionLabel"

/**
 * 原生内部命令 ID：只存在于 Kotlin Channel -> Service 的显式 Intent 中，
 * 由 Channel 生成并递增；Dart 不生成、不发送、不解释 command ID。
 */
internal const val EXTRA_COMMAND_ID = "commandId"

// ── 通知与渠道 ID ────────────────────────────────────────────────────────

internal const val CHAT_GENERATION_NOTIFICATION_CHANNEL_ID = "chat_generation"
internal const val CHAT_GENERATION_NOTIFICATION_ID = 4101

// ── 通知动作字符串 ───────────────────────────────────────────────────────

/** Channel 显式启动 Service 的内部 action。 */
internal const val SERVICE_START_ACTION =
    "yuzu.shiki.oh_my_llm.action.CHAT_GENERATION_START"

/** 通知停止动作，PendingIntent 指向 Service 自身。 */
internal const val NOTIFICATION_ACTION_STOP =
    "yuzu.shiki.oh_my_llm.action.CHAT_GENERATION_STOP"

/** 通知打开会话动作，PendingIntent 指向 MainActivity。 */
internal const val NOTIFICATION_ACTION_OPEN_CONVERSATION =
    "yuzu.shiki.oh_my_llm.action.CHAT_GENERATION_OPEN_CONVERSATION"

// ── 命令失败分类（与 Dart ChatForegroundFailureCode 枚举名一致） ─────────

internal const val FAILURE_UNSUPPORTED_PLATFORM = "unsupportedPlatform"
internal const val FAILURE_CHANNEL_UNAVAILABLE = "channelUnavailable"
internal const val FAILURE_CHANNEL_TIMEOUT = "channelTimeout"
internal const val FAILURE_START_NOT_ALLOWED = "startNotAllowed"
internal const val FAILURE_SECURITY = "security"
internal const val FAILURE_SERVICE_UNAVAILABLE = "serviceUnavailable"
internal const val FAILURE_STALE_TOKEN = "staleToken"
internal const val FAILURE_MALFORMED_PAYLOAD = "malformedPayload"
internal const val FAILURE_NATIVE_FAILURE = "nativeFailure"

// ── 权限状态（与 Dart ChatNotificationPermissionStatus 枚举名一致） ──────

internal const val STATUS_NOT_REQUIRED = "notRequired"
internal const val STATUS_GRANTED = "granted"
internal const val STATUS_DENIED = "denied"
internal const val STATUS_SKIPPED_ALREADY_REQUESTED = "skippedAlreadyRequested"
internal const val STATUS_UNAVAILABLE = "unavailable"

// ── 动作类型 ─────────────────────────────────────────────────────────────

internal sealed interface NotificationActionKind {
    data object None : NotificationActionKind
    data object Stop : NotificationActionKind
    data object OpenConversation : NotificationActionKind
}

/** 动作类型到协议字符串，与 Dart `actionKind.name` 一致。 */
internal fun NotificationActionKind.protocolName(): String = when (this) {
    NotificationActionKind.None -> "none"
    NotificationActionKind.Stop -> "stop"
    NotificationActionKind.OpenConversation -> "openConversation"
}

internal fun parseActionKind(value: Any?): NotificationActionKind? = when (value) {
    "none" -> NotificationActionKind.None
    "stop" -> NotificationActionKind.Stop
    "openConversation" -> NotificationActionKind.OpenConversation
    else -> null
}

// ── 脱敏载荷模型 ─────────────────────────────────────────────────────────

/** 解析后的脱敏通知载荷；Kotlin 不持有任何 prompt/回复/推理/URL/凭据。 */
internal data class NativeNotificationPayload(
    val token: Long,
    val conversationId: String,
    val title: String,
    val text: String,
    val publicTitle: String,
    val publicText: String,
    val actionKind: NotificationActionKind,
    val actionLabel: String?,
)

// ── 命令结果 ─────────────────────────────────────────────────────────────

internal sealed interface NativeCommandResult {
    data object Accepted : NativeCommandResult

    data class Unavailable(val failureCode: String) : NativeCommandResult
}

internal fun acceptedCommandResult(): Map<String, Any?> =
    mapOf("accepted" to true)

internal fun unavailableCommandResult(failureCode: String): Map<String, Any?> =
    mapOf("accepted" to false, "failureCode" to failureCode)

internal fun permissionStatusResult(status: String): Map<String, Any?> =
    mapOf("status" to status)

internal fun NativeCommandResult.toMap(): Map<String, Any?> = when (this) {
    NativeCommandResult.Accepted -> acceptedCommandResult()
    is NativeCommandResult.Unavailable -> unavailableCommandResult(failureCode)
}

// ── token 守卫 ───────────────────────────────────────────────────────────

internal enum class TokenDecision { ACCEPTED, STALE, MALFORMED }

/**
 * 当前进程内活跃生成 token 守卫：只做乱序保护，不持久化。
 * start 仅当无不同 token 活跃时接受；相同 token 的重复 start 幂等接受；
 * finish 只清除匹配 token。
 */
internal class ActiveGenerationTokenGuard {
    var activeToken: Long? = null
        private set

    fun start(token: Long): TokenDecision {
        if (token <= 0) return TokenDecision.MALFORMED
        val current = activeToken
        if (current == null) {
            activeToken = token
            return TokenDecision.ACCEPTED
        }
        return if (current == token) TokenDecision.ACCEPTED else TokenDecision.STALE
    }

    fun accepts(token: Long): TokenDecision {
        if (token <= 0) return TokenDecision.MALFORMED
        val current = activeToken ?: return TokenDecision.STALE
        return if (current == token) TokenDecision.ACCEPTED else TokenDecision.STALE
    }

    fun finish(token: Long): TokenDecision {
        if (token <= 0) return TokenDecision.MALFORMED
        val current = activeToken
        if (current == null || current != token) return TokenDecision.STALE
        activeToken = null
        return TokenDecision.ACCEPTED
    }

    fun clear() {
        activeToken = null
    }
}

/**
 * Android 15 timeout 普通通知的瞬态记录：只存 token + conversation ID，
 * 不存任何正文或领域载荷。后续匹配的 remove 取消该通知、匹配的 fail 替换它；
 * 新 start、engine detach 或进程死亡都会清除此记录。
 */
internal class TimedOutNotificationGuard {
    private var recordedToken: Long? = null
    private var recordedConversationId: String? = null

    fun record(token: Long, conversationId: String): TokenDecision {
        if (token <= 0) return TokenDecision.MALFORMED
        if (conversationId.isBlank()) return TokenDecision.MALFORMED
        recordedToken = token
        recordedConversationId = conversationId
        return TokenDecision.ACCEPTED
    }

    fun matches(token: Long, conversationId: String): Boolean =
        recordedToken != null &&
            recordedToken == token &&
            recordedConversationId == conversationId

    fun clear() {
        recordedToken = null
        recordedConversationId = null
    }
}

// ── 载荷解析 ─────────────────────────────────────────────────────────────

/**
 * 逐字段解析协议 map。Dart 小整数可能以 Int 或 Long 到达，因此只接受
 * 数学上为整数且为正的 Number；拒绝 Double 小数、布尔、空白 ID/标题/正文、
 * 未知 actionKind 与 actionLabel 不匹配。绝不调用 toString() 强转载荷值。
 */
internal fun parseNotificationPayload(map: Map<*, *>?): NativeNotificationPayload? {
    if (map == null) return null
    val token = parsePositiveToken(map[KEY_TOKEN]) ?: return null
    val conversationId = map[KEY_CONVERSATION_ID] as? String ?: return null
    if (conversationId.isBlank()) return null
    val title = map[KEY_TITLE] as? String ?: return null
    if (title.isBlank()) return null
    val text = map[KEY_TEXT] as? String ?: return null
    if (text.isBlank()) return null
    val publicTitle = map[KEY_PUBLIC_TITLE] as? String ?: return null
    if (publicTitle.isBlank()) return null
    val publicText = map[KEY_PUBLIC_TEXT] as? String ?: return null
    if (publicText.isBlank()) return null
    val actionKind = parseActionKind(map[KEY_ACTION_KIND]) ?: return null
    val actionLabel: String? = when (actionKind) {
        NotificationActionKind.None -> {
            // none 动作不允许携带非空 label
            if (map[KEY_ACTION_LABEL] == null) null else return null
        }
        NotificationActionKind.Stop,
        NotificationActionKind.OpenConversation,
        -> {
            val label = map[KEY_ACTION_LABEL]
            if (label is String && label.isNotBlank()) label else return null
        }
    }
    return NativeNotificationPayload(
        token = token,
        conversationId = conversationId,
        title = title,
        text = text,
        publicTitle = publicTitle,
        publicText = publicText,
        actionKind = actionKind,
        actionLabel = actionLabel,
    )
}

/**
 * 只接受数学上为整数且为正的 Number。Dart int 以 Int/Long 到达；
 * Double 小数（5.5）与布尔/字符串一律拒绝。remove 命令也复用该严格规则。
 */
internal fun parsePositiveToken(value: Any?): Long? {
    if (value !is Number) return null
    if (value is Double && value % 1.0 != 0.0) return null
    if (value is Float && value % 1.0f != 0.0f) return null
    val token = value.toLong()
    return if (token > 0) token else null
}
