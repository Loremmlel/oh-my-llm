import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database_provider.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import 'background_chat_repository.dart';
import 'sqlite_chat_conversation_repository.dart';
final chatConversationRepositoryProvider = Provider<ChatConversationRepository>(
  (ref) {
    final database = ref.watch(appDatabaseProvider);
    final inner = SqliteChatConversationRepository(database);
    return BackgroundChatConversationRepository(inner, database.path);
  },
);

/// 聊天会话持久化仓库接口。
abstract interface class ChatConversationRepository {
  /// 读取全部会话；空存储会返回空列表。
  List<ChatConversation> loadAll();

  /// 读取单个会话的完整数据（消息树、分支选择、检查点）。
  /// 找不到时返回 `null`。
  ChatConversation? loadConversation(String id);

  /// 按历史页需求读取会话摘要，并支持按标题和用户消息搜索。
  ///
  /// 传入 [limit] 时会同时返回 [hasMore] 标记（通过多查一行判断）。
  /// 不传 [limit] 时返回全部数据，[hasMore] 固定为 `false`。
  ({List<ChatConversationSummary> summaries, bool hasMore})
  loadHistorySummaries({String keyword = '', int? limit, int? offset});

  /// 将指定会话列表增量写回持久层（不存在则插入，存在则更新）。
  Future<void> saveConversations(List<ChatConversation> conversations);

  /// 保存单条会话，空会话（无消息、无检查点、无标题）将被跳过。
  Future<void> saveConversation(ChatConversation conversation);

  /// 从持久层删除指定 ID 的会话及其所有关联数据。
  Future<void> deleteConversations(List<String> ids);
}
