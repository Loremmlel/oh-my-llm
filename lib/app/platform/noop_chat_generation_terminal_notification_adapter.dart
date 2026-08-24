import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';

/// 非 Android/Windows 平台（以及未被平台 composition override 时）的
/// no-op 终态通知 adapter。
///
/// 不发起任何平台调用：激活流恒为空、pending 恒为 null、所有命令直接完成；
/// 作为安全默认绑定保证任意平台组合可编译可启动，不抛「未绑定」。
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
