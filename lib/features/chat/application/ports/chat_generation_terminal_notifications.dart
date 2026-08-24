import '../generation/chat_generation_terminal_notification.dart';

/// 聊天 application 对外的终态通知端口。
///
/// 与前台服务端口分离：只接收安全收据，不理解 generation outcome、payload
/// 或平台细节；实现由 app composition 绑定。
abstract interface class ChatGenerationTerminalNotifications {
  /// 报告一次生成终态收据；实现内部 fail-open，不得向调用者抛出。
  ///
  /// [suppressedAtTerminal] 是终态事件发生时刻冻结的注意力抑制决策；非 null
  /// 时以它为准（解决报告在 cleanup 延迟后执行、决策随用户导航漂移的问题），
  /// null 时实现回退到执行时刻评估。
  Future<void> report(
    ChatGenerationTerminalReceipt receipt, {
    bool? suppressedAtTerminal,
  });

  /// 释放资源；幂等。
  Future<void> dispose();
}
