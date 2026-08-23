import 'package:oh_my_llm/app/platform/android_chat_generation_platform_bridge.dart';
import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';

/// Android 系统通知设置窄 adapter。
///
/// 状态查询与打开设置入口都只委托共享 [AndroidChatGenerationPlatformBridge]；
/// 失败映射（未知状态 → unavailable / 打不开 → false）由 bridge 统一完成，
/// 本类不持有任何平台资源，也不需要 dispose。
final class AndroidSystemNotificationSettings
    implements SystemNotificationSettings {
  AndroidSystemNotificationSettings({required this.bridge});

  final AndroidChatGenerationPlatformBridge bridge;

  @override
  Future<SystemNotificationStatus> getStatus() =>
      bridge.getNotificationSettingsStatus();

  @override
  Future<bool> openSettings() => bridge.openNotificationSettings();
}
