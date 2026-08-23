package yuzu.shiki.oh_my_llm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * 生成终态 HIGH 通知：渠道创建、终态展示与 timeout 原生 fallback。
 *
 * 职责边界：本模块只渲染 Dart 已生成的安全文案与不透明 payload，不理解
 * generation outcome，也不参与终态判定；timeout fallback 只在原生前台服务
 * 失去 Dart 通道时告知用户，不是 durable delivery。
 *
 * 参数选择全部抽成纯配置常量/纯函数（[ChatGenerationTerminalNotificationSpec]
 * 与顶层函数），JVM 单元测试可直接断言 HIGH/非静音、ID/request code 冲突规则
 * 与设置状态判定；真实横幅、声音等 framework 行为留给 smoke 验证，不在 JVM
 * 测试中伪装已验证。
 */
private const val TAG = "ChatGenerationTerminal"

/** 终态通知固定参数；全部为编译期常量，JVM 测试无需 Android 框架即可断言。 */
internal object ChatGenerationTerminalNotificationSpec {
    /** API 26+ 渠道 importance：HIGH 才能出横幅，与静音的 ongoing LOW 渠道分离。 */
    const val CHANNEL_IMPORTANCE = NotificationManager.IMPORTANCE_HIGH

    /** 渠道启用振动；HIGH importance + 默认声 + 振动共同保证「不是 silent」。 */
    const val CHANNEL_VIBRATION_ENABLED = true

    /** 渠道使用系统默认通知声（USAGE_NOTIFICATION），绝不设为静音。 */
    const val CHANNEL_DEFAULT_NOTIFICATION_SOUND = true

    /** pre-26 builder 提示默认值：默认声音 | 默认振动。 */
    const val PRE_26_DEFAULTS =
        NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_VIBRATE

    /** pre-26 builder 优先级：HIGH。 */
    const val PRE_26_PRIORITY = NotificationCompat.PRIORITY_HIGH

    /** 终态通知类别：设备状态类事件，不用进度/提醒语义。 */
    const val CATEGORY = NotificationCompat.CATEGORY_STATUS

    /** 主通知锁屏可见性：正文仅解锁后可见。 */
    const val VISIBILITY = NotificationCompat.VISIBILITY_PRIVATE

    /** public version 锁屏可见性：公开副本只含固定安全文案，可全程显示。 */
    const val PUBLIC_VISIBILITY = NotificationCompat.VISIBILITY_PUBLIC

    /** timeout 原生 fallback 固定文案（计划 Section 3.4 安全文案表）。 */
    const val TIMEOUT_FALLBACK_TITLE = "后台保护已结束"
    const val TIMEOUT_FALLBACK_BODY = "请打开应用查看生成状态"
}

// ── 纯决策函数（framework 无关，JVM 测试直接覆盖） ────────────────────────

/**
 * 只有尚不存在同 ID 渠道时才创建；已有渠道绝不删除重建或尝试升级
 * importance——系统不允许升级，重建只会丢失用户手工调整。
 */
internal fun shouldCreateTerminalChannel(existingChannelId: String?): Boolean =
    existingChannelId == null

/**
 * 锁屏公开副本的字段来源：只允许使用请求里传入的固定 publicTitle/publicBody，
 * 绝不从 private 正文推导。builder 一律经本函数取值，保证被测决策就是
 * 实际执行路径。
 */
internal fun terminalPublicCopy(request: TerminalNotificationRequest): Pair<String, String> =
    request.publicTitle to request.publicBody

/**
 * 系统通知设置状态的纯判定：
 * - 总开关关闭 -> disabled；
 * - API 26+ 且终态渠道 importance 为 NONE -> disabled；
 * - 其余 -> enabled。获取系统服务失败由调用方映射为 unavailable。
 */
internal fun resolveNotificationSettingsStatus(
    notificationsEnabled: Boolean,
    terminalChannelImportance: Int?,
    sdkInt: Int,
): String {
    if (!notificationsEnabled) return SETTINGS_STATUS_DISABLED
    if (sdkInt >= Build.VERSION_CODES.O &&
        terminalChannelImportance == NotificationManager.IMPORTANCE_NONE
    ) {
        return SETTINGS_STATUS_DISABLED
    }
    return SETTINGS_STATUS_ENABLED
}

/** 打开系统通知设置所需 Intent 参数（Intent 构造留在框架侧以便 JVM 测试）。 */
internal data class AppNotificationSettingsSpec(
    val action: String,
    val packageExtraKey: String,
    val packageName: String,
    val needsNewTaskFlag: Boolean,
)

/** 只使用当前 package 打开应用通知设置页，不带任何深链会话参数。 */
internal fun appNotificationSettingsSpec(packageName: String): AppNotificationSettingsSpec =
    AppNotificationSettingsSpec(
        action = Settings.ACTION_APP_NOTIFICATION_SETTINGS,
        packageExtraKey = Settings.EXTRA_APP_PACKAGE,
        packageName = packageName,
        needsNewTaskFlag = true,
    )

// ── 渠道 ─────────────────────────────────────────────────────────────────

/**
 * 幂等创建终态 HIGH 渠道：showTerminalNotification 与设置状态查询都会先
 * 调用本函数，用户进入设置页时即使尚无第一条终态通知也能配置该渠道。
 */
internal fun ensureTerminalChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    try {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (!shouldCreateTerminalChannel(manager.getNotificationChannel(TERMINAL_CHANNEL_ID)?.id)) {
            return
        }
        val channel = NotificationChannel(
            TERMINAL_CHANNEL_ID,
            context.getString(R.string.chat_generation_terminal_notification_channel_name),
            ChatGenerationTerminalNotificationSpec.CHANNEL_IMPORTANCE,
        ).apply {
            description =
                context.getString(R.string.chat_generation_terminal_notification_channel_description)
            if (ChatGenerationTerminalNotificationSpec.CHANNEL_DEFAULT_NOTIFICATION_SOUND) {
                setSound(
                    Settings.System.DEFAULT_NOTIFICATION_URI,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
            }
            enableVibration(ChatGenerationTerminalNotificationSpec.CHANNEL_VIBRATION_ENABLED)
        }
        manager.createNotificationChannel(channel)
    } catch (e: Exception) {
        // OEM 禁止建渠道时不崩溃；后续 notify 退化为无渠道 best-effort。
        Log.w(TAG, "category=terminal_channel_failed sdk=${Build.VERSION.SDK_INT}")
    }
}

// ── 展示 ─────────────────────────────────────────────────────────────────

/** 展示一条终态通知；失败抛给调用方（Channel 映射为 ACK false 供 Dart 重试）。 */
internal fun showTerminalNotification(context: Context, request: TerminalNotificationRequest) {
    ensureTerminalChannel(context)
    val contentIntent = terminalActivationPendingIntent(context, request.id, request.payload)
    val publicCopy = terminalPublicCopy(request)
    val notification = baseTerminalBuilder(context, contentIntent)
        .setContentTitle(request.title)
        .setContentText(request.body)
        .setPublicVersion(publicTerminalVersion(context, publicCopy.first, publicCopy.second, contentIntent))
        .build()
    NotificationManagerCompat.from(context).notify(request.id, notification)
}

/**
 * timeout 原生 fallback：完全自包含（内部吞异常记日志），供前台服务在 Dart
 * 未受理 timeout 事件时调用。payload 原样复用 start 载荷保存的激活字符串；
 * 同一时间至多保留一条，后一次经 FLAG_UPDATE_CURRENT 覆盖前一次。
 */
internal fun showTimeoutFallback(context: Context, savedPayload: String?) {
    val fallback = timeoutFallbackRequest(savedPayload)
    try {
        ensureTerminalChannel(context)
        val contentIntent =
            terminalActivationPendingIntent(context, fallback.notificationId, fallback.payload)
        val notification = baseTerminalBuilder(context, contentIntent)
            .setContentTitle(ChatGenerationTerminalNotificationSpec.TIMEOUT_FALLBACK_TITLE)
            .setContentText(ChatGenerationTerminalNotificationSpec.TIMEOUT_FALLBACK_BODY)
            .setPublicVersion(
                publicTerminalVersion(
                    context,
                    ChatGenerationTerminalNotificationSpec.TIMEOUT_FALLBACK_TITLE,
                    ChatGenerationTerminalNotificationSpec.TIMEOUT_FALLBACK_BODY,
                    contentIntent,
                ),
            )
            .build()
        NotificationManagerCompat.from(context).notify(fallback.notificationId, notification)
    } catch (e: Exception) {
        Log.w(TAG, "category=timeout_fallback_failed sdk=${Build.VERSION.SDK_INT}")
    }
}

// ── 构造细节 ─────────────────────────────────────────────────────────────

private fun baseTerminalBuilder(
    context: Context,
    contentIntent: PendingIntent,
): NotificationCompat.Builder {
    val builder = NotificationCompat.Builder(context, TERMINAL_CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_chat_generation)
        .setContentIntent(contentIntent)
        .setCategory(ChatGenerationTerminalNotificationSpec.CATEGORY)
        .setOngoing(false)
        .setAutoCancel(true)
        .setVisibility(ChatGenerationTerminalNotificationSpec.VISIBILITY)
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
        // API 26+ 的提示行为由 HIGH 渠道决定；pre-26 用 builder 默认值补齐。
        builder.setDefaults(ChatGenerationTerminalNotificationSpec.PRE_26_DEFAULTS)
        builder.setPriority(ChatGenerationTerminalNotificationSpec.PRE_26_PRIORITY)
    }
    return builder
}

/** public version 与主通知共用 icon/category/contentIntent，visibility 固定 public。 */
private fun publicTerminalVersion(
    context: Context,
    title: String,
    body: String,
    contentIntent: PendingIntent,
): Notification {
    return NotificationCompat.Builder(context, TERMINAL_CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_chat_generation)
        .setContentTitle(title)
        .setContentText(body)
        .setCategory(ChatGenerationTerminalNotificationSpec.CATEGORY)
        .setVisibility(ChatGenerationTerminalNotificationSpec.PUBLIC_VISIBILITY)
        .setContentIntent(contentIntent)
        .build()
}

/**
 * 点击激活 PendingIntent：指向 MainActivity，data URI 与 request code 都由
 * 通知 ID 推导，extras 只携带原始 payload 字符串。
 */
private fun terminalActivationPendingIntent(
    context: Context,
    notificationId: Int,
    payload: String?,
): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
        action = NOTIFICATION_ACTION_GENERATION_ACTIVATED
        data = Uri.parse(generationNotificationDataUri(notificationId))
        if (!payload.isNullOrEmpty()) {
            putExtra(KEY_PAYLOAD, payload)
        }
    }
    return PendingIntent.getActivity(
        context,
        terminalPendingRequestCode(notificationId),
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}
