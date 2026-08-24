package yuzu.shiki.oh_my_llm

import android.app.NotificationManager

/**
 * 聊天生成通知的原生协议定义：通道/方法/载荷键、命令结果 map、通知与渠道
 * ID、动作字符串、纯解析函数与 token 守卫。
 *
 * 本文件不含任何 Android framework 调用：唯一的 framework 引用是
 * `NotificationManager.IMPORTANCE_*` 编译期常量（编译时内联），JVM 单元测试
 * 可直接加载。所有常量与方法名必须与 Dart 侧
 * `AndroidChatGenerationPlatformBridge` 以及计划 Section 7 协议逐字节一致。
 * 通道职责：
 *
 * - ongoing 前台服务：LOW 静音渠道 + 4101 通知，点击直达会话契约原样保留；
 * - 终态通知：HIGH 渠道，ID 由 Dart FNV-1a 计算并随命令传入；
 * - 系统设置：状态查询与打开系统设置入口。
 */

// ── 通道与方法名 ─────────────────────────────────────────────────────────

internal const val CHAT_GENERATION_CHANNEL =
    "yuzu.shiki.oh_my_llm/chat_generation_notifications"

internal const val METHOD_ENSURE_NOTIFICATION_PERMISSION =
    "ensureNotificationPermission"
internal const val METHOD_START_FOREGROUND_GENERATION =
    "startForegroundGeneration"
internal const val METHOD_UPDATE_FOREGROUND_GENERATION =
    "updateForegroundGeneration"
internal const val METHOD_REMOVE_FOREGROUND_GENERATION =
    "removeForegroundGeneration"
internal const val METHOD_TAKE_PENDING_OPEN_CONVERSATION =
    "takePendingOpenConversation"
internal const val METHOD_SHOW_TERMINAL_NOTIFICATION =
    "showTerminalNotification"
internal const val METHOD_TAKE_PENDING_NOTIFICATION_ACTIVATION =
    "takePendingNotificationActivation"
internal const val METHOD_GET_NOTIFICATION_SETTINGS_STATUS =
    "getNotificationSettingsStatus"
internal const val METHOD_OPEN_NOTIFICATION_SETTINGS =
    "openNotificationSettings"

internal const val CALLBACK_STOP_REQUESTED = "stopRequested"
internal const val CALLBACK_OPEN_CONVERSATION_REQUESTED =
    "openConversationRequested"
internal const val CALLBACK_FOREGROUND_SERVICE_TIMED_OUT =
    "foregroundServiceTimedOut"
internal const val CALLBACK_NOTIFICATION_ACTIVATED = "notificationActivated"

// ── 载荷键（camelCase，与 Dart 侧一致） ──────────────────────────────────

internal const val KEY_TOKEN = "token"
internal const val KEY_CONVERSATION_ID = "conversationId"
internal const val KEY_TITLE = "title"
internal const val KEY_TEXT = "text"
internal const val KEY_PUBLIC_TITLE = "publicTitle"
internal const val KEY_PUBLIC_TEXT = "publicText"
internal const val KEY_ACTION_KIND = "actionKind"
internal const val KEY_ACTION_LABEL = "actionLabel"

/** Dart 预编码的前台保护超时激活 payload；原生只保存与原样复用。 */
internal const val KEY_TIMEOUT_ACTIVATION_PAYLOAD = "timeoutActivationPayload"

/** 终态通知命令的载荷键（showTerminalNotification 参数）。 */
internal const val KEY_ID = "id"
internal const val KEY_BODY = "body"
internal const val KEY_PUBLIC_BODY = "publicBody"
internal const val KEY_PAYLOAD = "payload"

/**
 * 原生内部命令 ID：只存在于 Kotlin Channel -> Service 的显式 Intent 中，
 * 由 Channel 生成并递增；Dart 不生成、不发送、不解释 command ID。
 * 终态/fallback 点击激活 Intent 的 payload extra 复用 [KEY_PAYLOAD]。
 */
internal const val EXTRA_COMMAND_ID = "commandId"

// ── 通知与渠道 ID ────────────────────────────────────────────────────────

/** ongoing 前台服务渠道：LOW 且静音，只承载进行中的生成保护。 */
internal const val ONGOING_CHANNEL_ID = "chat_generation"

/** ongoing 通知固定 ID；终态 ID 与本值分属不同职责，绝不允许冲突。 */
internal const val ONGOING_NOTIFICATION_ID = 4101

/**
 * ongoing 渠道固定 importance：LOW 才能保持静默常驻；升级已有 LOW channel
 * 得不到横幅，因此终态必须另开 HIGH 渠道而不是复用本渠道。
 */
internal const val ONGOING_CHANNEL_IMPORTANCE = NotificationManager.IMPORTANCE_LOW

/** ongoing 渠道静音契约：不设置声音、不启用振动。 */
internal const val ONGOING_CHANNEL_SILENT = true

/** 终态 HIGH 渠道 ID；与 ongoing 渠道分离，避免 importance 无法升级的死锁。 */
internal const val TERMINAL_CHANNEL_ID = "chat_generation_result"

/**
 * Dart FNV-1a 终态通知 ID 的契约下界（10000..2147483646）；Kotlin 只用它
 * 拒绝落在原生保留槽位的非法 ID，不复刻哈希算法。
 */
internal const val MIN_TERMINAL_NOTIFICATION_ID = 10000

/**
 * timeout 原生 fallback 固定通知 ID / PendingIntent request code：低于 Dart
 * FNV 下界且不与 ongoing [ONGOING_NOTIFICATION_ID] 冲突。
 */
internal const val TERMINAL_TIMEOUT_FALLBACK_NOTIFICATION_ID = 4200

/** timeoutActivationPayload 只校验类型与长度：UTF-8 上限与 Dart codec 一致。 */
internal const val MAX_TIMEOUT_ACTIVATION_PAYLOAD_BYTES = 1024

// ── 通知动作字符串 ───────────────────────────────────────────────────────

/** Channel 显式启动 Service 的内部 action。 */
internal const val SERVICE_START_ACTION =
    "yuzu.shiki.oh_my_llm.action.CHAT_GENERATION_START"

/** 通知停止动作，PendingIntent 指向 Service 自身。 */
internal const val NOTIFICATION_ACTION_STOP =
    "yuzu.shiki.oh_my_llm.action.CHAT_GENERATION_STOP"

/** ongoing 通知点击打开会话动作，PendingIntent 指向 MainActivity（既有契约）。 */
internal const val NOTIFICATION_ACTION_OPEN_CONVERSATION =
    "yuzu.shiki.oh_my_llm.action.CHAT_GENERATION_OPEN_CONVERSATION"

/** 终态通知与 timeout fallback 点击激活动作，PendingIntent 指向 MainActivity。 */
internal const val NOTIFICATION_ACTION_GENERATION_ACTIVATED =
    "yuzu.shiki.oh_my_llm.action.CHAT_GENERATION_NOTIFICATION_ACTIVATED"

// ── PendingIntent request code（原生保留槽位） ────────────────────────────

internal const val STOP_PENDING_REQUEST_CODE = 4103
internal const val OPEN_CONVERSATION_PENDING_REQUEST_CODE = 4104

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

// ── 权限与设置状态字符串 ────────────────────────────────────────────────

internal const val STATUS_NOT_REQUIRED = "notRequired"
internal const val STATUS_GRANTED = "granted"
internal const val STATUS_DENIED = "denied"
internal const val STATUS_SKIPPED_ALREADY_REQUESTED = "skippedAlreadyRequested"
internal const val STATUS_UNAVAILABLE = "unavailable"

/** 系统通知设置状态（与 Dart SystemNotificationStatus 解码约定一致）。 */
internal const val SETTINGS_STATUS_ENABLED = "enabled"
internal const val SETTINGS_STATUS_DISABLED = "disabled"

// ── 动作类型 ─────────────────────────────────────────────────────────────

/**
 * ongoing 载荷的动作类型。旧 LOW 终态路径的 openConversation 动作已由统一
 * 终态激活取代，只保留 none/stop；ongoing 点击直达会话走 content intent 与
 * takePendingOpenConversation，不经过动作按钮。
 */
internal sealed interface NotificationActionKind {
    data object None : NotificationActionKind
    data object Stop : NotificationActionKind
}

/** 动作类型到协议字符串，与 Dart `actionKind.name` 一致。 */
internal fun NotificationActionKind.protocolName(): String = when (this) {
    NotificationActionKind.None -> "none"
    NotificationActionKind.Stop -> "stop"
}

internal fun parseActionKind(value: Any?): NotificationActionKind? = when (value) {
    "none" -> NotificationActionKind.None
    "stop" -> NotificationActionKind.Stop
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
    /**
     * Dart 预编码的前台保护超时激活 payload。已通过类型/长度校验，但内容
     * 对原生不透明：只在 fallback PendingIntent 中原样返回，绝不解析。
     */
    val timeoutActivationPayload: String,
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

// ── 终态通知请求解码 ─────────────────────────────────────────────────────

/** showTerminalNotification 的解析结果；字段在解析层已全部非空白校验。 */
internal data class TerminalNotificationRequest(
    val id: Int,
    val title: String,
    val body: String,
    val publicTitle: String,
    val publicBody: String,
    val payload: String,
)

/**
 * 终态通知 ID 守卫：必须是正 int 且不低于 Dart FNV 契约下界，天然避开
 * ongoing(4101)、timeout fallback(4200) 等原生保留槽位。
 */
internal fun parseTerminalNotificationId(value: Any?): Int? {
    val id = parsePositiveToken(value) ?: return null
    if (id < MIN_TERMINAL_NOTIFICATION_ID || id > Int.MAX_VALUE) return null
    return id.toInt()
}

/**
 * 逐字段解析 showTerminalNotification 参数 map。private 与 public 两套文案
 * 都必须非空白——public version 是锁屏唯一可见副本，缺公开文案按协议不符
 * 处理而不是回退私有正文。payload 是 Dart 预编码的严格 v1 JSON 字符串，
 * 原生只保存转发，不解析内容。
 */
internal fun parseTerminalNotificationRequest(map: Map<*, *>?): TerminalNotificationRequest? {
    if (map == null) return null
    val id = parseTerminalNotificationId(map[KEY_ID]) ?: return null
    val title = nonBlankString(map[KEY_TITLE]) ?: return null
    val body = nonBlankString(map[KEY_BODY]) ?: return null
    val publicTitle = nonBlankString(map[KEY_PUBLIC_TITLE]) ?: return null
    val publicBody = nonBlankString(map[KEY_PUBLIC_BODY]) ?: return null
    val payload = map[KEY_PAYLOAD] as? String
    if (payload.isNullOrEmpty()) return null
    return TerminalNotificationRequest(
        id = id,
        title = title,
        body = body,
        publicTitle = publicTitle,
        publicBody = publicBody,
        payload = payload,
    )
}

internal fun nonBlankString(value: Any?): String? {
    if (value !is String) return null
    if (value.isBlank()) return null
    return value
}

// ── 终态点击 PendingIntent 推导 ──────────────────────────────────────────

/**
 * 终态点击 PendingIntent request code 与通知 ID 同源同值；激活 Intent 不设置
 * data，不同终态互不覆盖的区分性仅由本 request code 保证。
 */
internal fun terminalPendingRequestCode(notificationId: Int): Int = notificationId

// ── timeout fallback 决策 ────────────────────────────────────────────────

/**
 * timeout ACK 解码：只有严格 bool true 表示「事件已进入 Dart」。false、null
 * 或其他类型一律视为未受理，由原生展示 HIGH 固定 fallback。
 */
internal fun isTimeoutAcceptedByDart(value: Any?): Boolean = value == true

/** timeout fallback 请求：固定 ID 4200 + 原样复用保存的激活 payload。 */
internal data class TimeoutFallbackRequest(
    val notificationId: Int,
    val payload: String?,
)

/**
 * 构造 timeout fallback 请求。payload 必须是 start 载荷保存的
 * timeoutActivationPayload 原字符串（event key 已由 Dart 固定编码），这里
 * 不重建、不解析；缺失时为 null，fallback 点击退化为仅打开应用。
 */
internal fun timeoutFallbackRequest(savedPayload: String?): TimeoutFallbackRequest =
    TimeoutFallbackRequest(
        notificationId = TERMINAL_TIMEOUT_FALLBACK_NOTIFICATION_ID,
        payload = savedPayload,
    )

/** timeout fallback 固定 request code：与通知 ID 同为 4200。 */
internal fun timeoutFallbackPendingRequestCode(): Int =
    TERMINAL_TIMEOUT_FALLBACK_NOTIFICATION_ID

// ── 载荷解析 ─────────────────────────────────────────────────────────────

/**
 * 逐字段解析协议 map。Dart 小整数可能以 Int 或 Long 到达，因此只接受
 * 数学上为整数且为正的 Number；拒绝 Double 小数、布尔、空白 ID/标题/正文、
 * 缺失或非法的 timeoutActivationPayload 与 actionLabel 不匹配。绝不调用
 * toString() 强转载荷值。
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
        NotificationActionKind.Stop -> {
            val label = map[KEY_ACTION_LABEL]
            if (label is String && label.isNotBlank()) label else return null
        }
    }
    val timeoutActivationPayload =
        parseTimeoutActivationPayload(map[KEY_TIMEOUT_ACTIVATION_PAYLOAD])
            ?: return null
    return NativeNotificationPayload(
        token = token,
        conversationId = conversationId,
        title = title,
        text = text,
        publicTitle = publicTitle,
        publicText = publicText,
        actionKind = actionKind,
        actionLabel = actionLabel,
        timeoutActivationPayload = timeoutActivationPayload,
    )
}

/**
 * 只校验 Dart 预编码 timeout 激活载荷的类型与长度：非空 String 且 UTF-8
 * 不超过 [MAX_TIMEOUT_ACTIVATION_PAYLOAD_BYTES]。绝不解析 JSON 内容，也不
 * 校验 event key/session 规则——内容合法性由 Dart 共享 codec 在发送前保证，
 * 原生侧把它当作不透明安全字段。
 */
internal fun parseTimeoutActivationPayload(value: Any?): String? {
    if (value !is String) return null
    if (value.isBlank()) return null
    if (value.toByteArray(Charsets.UTF_8).size > MAX_TIMEOUT_ACTIVATION_PAYLOAD_BYTES) {
        return null
    }
    return value
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
