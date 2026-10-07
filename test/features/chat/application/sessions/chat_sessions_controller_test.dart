import 'package:flutter_test/flutter_test.dart';

import 'chat_sessions_controller/chat_sessions_controller_branching_cases.dart';
import 'chat_sessions_controller/chat_sessions_controller_checkpoint_cases.dart';
import 'chat_sessions_controller/chat_sessions_controller_crud_cases.dart';
import 'chat_sessions_controller/chat_sessions_controller_generation_cases.dart';
import 'chat_sessions_controller/chat_sessions_controller_retry_cases.dart';
import 'chat_sessions_controller/chat_sessions_controller_stop_cases.dart';

/// ChatSessionsController 公开契约测试入口。
///
/// 每组独立拥有 setUp/tearDown，避免一个用例创建其他组的数据库与容器。
void main() {
  group('会话管理', registerChatSessionsControllerCrudCases);
  group('消息生成', registerChatSessionsControllerGenerationCases);
  group('自动与手动重试', registerChatSessionsControllerRetryCases);
  group('停止与释放', registerChatSessionsControllerStopCases);
  group('消息分支', registerChatSessionsControllerBranchingCases);
  group('检查点', registerChatSessionsControllerCheckpointCases);
}
