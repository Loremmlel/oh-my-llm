import 'chat_sessions_controller/chat_sessions_controller_branching_cases.dart';
import 'chat_sessions_controller/chat_sessions_controller_checkpoint_cases.dart';
import 'chat_sessions_controller/chat_sessions_controller_crud_cases.dart';
import 'chat_sessions_controller/chat_sessions_controller_generation_cases.dart';
import 'chat_sessions_controller/chat_sessions_controller_retry_cases.dart';
import 'chat_sessions_controller/chat_sessions_controller_stop_cases.dart';

/// ChatSessionsController 公开契约测试入口。
///
/// 按 case-file decomposition 拆分为 6 个 case 文件，各自注册一组公开契约
/// 测试。原测试名称与行为断言保留，仅按契约归入对应文件。
void main() {
  registerChatSessionsControllerCrudCases();
  registerChatSessionsControllerGenerationCases();
  registerChatSessionsControllerRetryCases();
  registerChatSessionsControllerStopCases();
  registerChatSessionsControllerBranchingCases();
  registerChatSessionsControllerCheckpointCases();
}
