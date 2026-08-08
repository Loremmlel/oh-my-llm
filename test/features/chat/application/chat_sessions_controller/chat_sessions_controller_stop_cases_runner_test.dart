import 'chat_sessions_controller_stop_cases.dart';

/// stop 用例的独立入口：case 文件不被测试运行器发现（无 `main()`），需要单独
/// 连跑 stop / 重试竞态场景时从本入口执行，避免在全量入口中连带其他用例。
void main() {
  registerChatSessionsControllerStopCases();
}
