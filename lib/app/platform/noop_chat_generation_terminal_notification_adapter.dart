import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';

/// 非 Android/Windows 平台（以及平台 composition 完成前的默认绑定）的
/// no-op 终态通知 adapter。
///
/// 不发起任何平台调用：激活流恒为空、pending 恒为 null、所有命令直接完成；
/// 保证平台 composition 接入前的每个中间提交可编译可启动，不抛「未绑定」。
final class NoopChatGenerationTerminalNotificationAdapter
    implements ChatGenerationTerminalNotificationAdapter {
  @override
  Stream<ChatGenerationNotificationActivation> get activations =>
      const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show(ChatGenerationSafeNotification notification) async {}

  @override
  Future<ChatGenerationNotificationActivation?> takePendingActivation() async =>
      null;

  @override
  Future<void> dispose() async {}
}
