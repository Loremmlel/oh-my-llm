import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database_provider.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import 'sqlite_chat_conversation_repository.dart';

/// SharedPreferences 中旧版聊天记录的存储键（已废弃，仅供迁移读取）。
const chatConversationsStorageKey = 'chat_conversations';

/// SharedPreferences 中聊天记录已完成 SQLite 迁移的标志键。
const chatConversationsSqliteMigrationFlagKey =
    'chat_conversations_sqlite_migrated';

final chatConversationRepositoryProvider = Provider<ChatConversationRepository>(
  (ref) {
    final database = ref.watch(appDatabaseProvider);
    return SqliteChatConversationRepository(database);
  },
);

/// 聊天会话持久化仓库接口。
abstract interface class ChatConversationRepository {
  /// 读取全部会话；空存储会返回空列表。
  List<ChatConversation> loadAll();

  /// 按历史页需求读取会话摘要，并支持按标题和用户消息搜索。
  List<ChatConversationSummary> loadHistorySummaries({String keyword = ''});

  /// 将当前会话列表覆盖写回持久层。
  Future<void> saveAll(List<ChatConversation> conversations);
}
