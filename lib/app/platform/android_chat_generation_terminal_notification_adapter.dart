import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_platform_bridge.dart';

/// Android 终态通知窄 adapter。
///
/// 只接收 [ChatGenerationSafeNotification]、只交回激活；所有平台交互委托共享
/// [AndroidChatGenerationPlatformBridge]，本类不创建、不安装 MethodChannel
/// handler。展示失败以 [AndroidTerminalNotificationShowException] 暴露给终态
/// 通知深模块（fail-open 捕获并保留重试），不解释 generation outcome。
///
/// dispose 只释放自身（当前无独占资源），绝不 dispose 共享 bridge——共享
/// owner 的释放由 composition 的 `disposeShared` 统一完成。
final class AndroidChatGenerationTerminalNotificationAdapter
    implements ChatGenerationTerminalNotificationAdapter {
  AndroidChatGenerationTerminalNotificationAdapter({required this.bridge});

  final AndroidChatGenerationPlatformBridge bridge;

  @override
  Stream<ChatGenerationNotificationActivation> get activations =>
      bridge.terminalActivations;

  @override
  Future<void> initialize() async {
    // Android 无需插件级初始化：channel 与 handler 由共享 bridge 在构造时
    // 就位，权限/渠道创建由 Kotlin 侧按需幂等完成。
  }

  @override
  Future<void> show(ChatGenerationSafeNotification notification) =>
      bridge.showTerminalNotification(notification);

  @override
  Future<ChatGenerationNotificationActivation?> takePendingActivation() =>
      bridge.takePendingActivation();

  @override
  Future<void> dispose() async {}
}
