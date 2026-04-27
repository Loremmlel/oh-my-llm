import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/versioned_json_storage.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import '../domain/models/chat_message.dart';
import 'chat_conversation_repository.dart';

/// 基于 SharedPreferences 的旧版会话持久化仓库，仅用于兼容迁移。
class SharedPreferencesChatConversationRepository
    implements ChatConversationRepository {
  const SharedPreferencesChatConversationRepository(this._preferences);

  final SharedPreferences _preferences;

  /// 从 SharedPreferences 读取全部聊天记录。
  ///
  /// 读取时兼容旧格式（裸 JSON 数组）和新格式（`{"version":1,"items":[...]}`）。
  @override
  List<ChatConversation> loadAll() {
    final rawValue = _preferences.getString(chatConversationsStorageKey);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return const [];
    }

    return VersionedJsonStorage.decodeObjectList(
      rawJson: rawValue,
      subject: 'conversations',
    ).map(ChatConversation.fromJson).toList(growable: false);
  }

  /// 返回符合 [keyword] 搜索条件的对话摘要列表。
  ///
  /// 搜索范围仅覆盖对话标题和用户消息，不匹配助手回复，
  /// 与 SQLite 仓库保持一致的行为。
  @override
  List<ChatConversationSummary> loadHistorySummaries({String keyword = ''}) {
    final normalizedKeyword = keyword.trim().toLowerCase();

    return loadAll()
        .where((conversation) {
          if (!conversation.hasMessages) {
            return false;
          }
          if (normalizedKeyword.isEmpty) {
            return true;
          }

          final titleMatched = conversation.resolvedTitle
              .toLowerCase()
              .contains(normalizedKeyword);
          if (titleMatched) {
            return true;
          }

          return conversation.messageNodes.any((message) {
            return message.role == ChatMessageRole.user &&
                message.content.toLowerCase().contains(normalizedKeyword);
          });
        })
        .map((conversation) {
          final userNodes = conversation.messageNodes
              .where((message) => message.role == ChatMessageRole.user)
              .toList(growable: false);

          return ChatConversationSummary(
            id: conversation.id,
            title: conversation.title,
            updatedAt: conversation.updatedAt,
            firstUserMessagePreview: userNodes.firstOrNull?.content ?? '',
            latestUserMessagePreview: userNodes.lastOrNull?.content ?? '',
          );
        })
        .toList(growable: false);
  }

  /// 将全部聊天记录覆盖写入 SharedPreferences。
  @override
  Future<void> saveAll(List<ChatConversation> conversations) {
    final payload = VersionedJsonStorage.encodeObjectList(
      items: conversations,
      toJson: (conversation) => conversation.toJson(),
    );
    return _preferences.setString(chatConversationsStorageKey, payload);
  }
}
