import '../generation/chat_generation_terminal_notification.dart';

/// 聊天 application 对外的终态通知端口。
///
/// 与前台服务端口分离：只接收安全收据，不理解 generation outcome、payload
/// 或平台细节；实现由 app composition 绑定。
abstract interface class ChatGenerationTerminalNotifications {
  /// 报告一次生成终态收据；实现内部 fail-open，不得向调用者抛出。
  Future<void> report(ChatGenerationTerminalReceipt receipt);

  /// 释放资源；幂等。
  Future<void> dispose();
}
