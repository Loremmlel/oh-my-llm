import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';

/// 非 Android/Windows 平台（以及普通测试）的系统通知设置 no-op。
///
/// 这些平台没有可集成的系统通知设置入口：状态恒为 unavailable、打开设置
/// 恒为 false；不发起任何平台调用。Android/Windows 由平台 composition 绑定
/// 各自的窄 adapter，不使用本类。
final class NoopSystemNotificationSettings
    implements SystemNotificationSettings {
  @override
  Future<SystemNotificationStatus> getStatus() async =>
      SystemNotificationStatus.unavailable;

  @override
  Future<bool> openSettings() async => false;
}
