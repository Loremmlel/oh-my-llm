import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';
import 'chat_favorites_facade.dart';

/// favorite toggle 的同步结果。
sealed class ChatFavoriteIntentResult {
  const ChatFavoriteIntentResult();
}

/// 已存在收藏：已调用 remove，可 restore。
class ChatFavoriteRemoved extends ChatFavoriteIntentResult {
  const ChatFavoriteRemoved(this.removedEntry);

  final ChatFavoriteEntry removedEntry;
}

/// 无收藏：返回待新增 draft 与 collection 选项，尚未 mutation。
class ChatFavoriteNeedsCollection extends ChatFavoriteIntentResult {
  const ChatFavoriteNeedsCollection({
    required this.draftWithoutCollection,
    required this.collectionOptions,
  });

  final ChatFavoriteDraft draftWithoutCollection;
  final List<ChatFavoriteCollectionOption> collectionOptions;
}

/// 收藏 intent 的薄编排：准备/移除/恢复/新增，都经 [ChatFavoritesFacade]。
class ChatFavoriteIntentCommand {
  ChatFavoriteIntentCommand(this._facade);

  final ChatFavoritesFacade _facade;

  ChatFavoriteIntentResult beginToggle({
    required ChatConversation conversation,
    required ChatMessage assistantMessage,
  }) {
    final snapshot = _facade.snapshot;
    final existing = snapshot.findByAssistantContent(assistantMessage.content);
    if (existing != null) {
      _facade.remove(existing.id);
      return ChatFavoriteRemoved(existing);
    }

    final draft = ChatFavoriteDraft(
      userMessageContent: _resolveUserContent(conversation, assistantMessage),
      assistantContent: assistantMessage.content,
      assistantReasoningContent: assistantMessage.reasoningContent,
      assistantModelDisplayName:
          assistantMessage.resolvedAssistantModelDisplayName,
      collectionId: null,
      sourceAssistantMessageId: assistantMessage.id,
      sourceConversationId: conversation.id,
      sourceConversationTitle: conversation.resolvedTitle,
    );
    return ChatFavoriteNeedsCollection(
      draftWithoutCollection: draft,
      collectionOptions: snapshot.collections,
    );
  }

  void addToCollection(ChatFavoriteDraft draft, String selectedCollectionId) {
    // '' 表示未分类 -> null。
    final normalized = selectedCollectionId.isEmpty
        ? null
        : selectedCollectionId;
    _facade.add(draft.copyWithCollectionId(normalized));
  }

  void restore(ChatFavoriteEntry entry) => _facade.add(entry.draft);

  /// 空名（trim 后）返回 null 表示未创建，避免产生空收藏夹；
  /// dialog 侧保留空名 UI guard，不会对空名发起回调。
  String? createCollection(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return _facade.createCollection(trimmed);
  }

  /// 在 assistant 之前反向找最近 user；前缀非空但无 user 时回退前缀第一条；
  /// assistant 位于索引 0 或不存在时返回空字符串。既有产品行为，不重新定义。
  String _resolveUserContent(
    ChatConversation conversation,
    ChatMessage assistantMessage,
  ) {
    final messages = conversation.messages;
    final assistantIndex = messages.indexWhere(
      (m) => m.id == assistantMessage.id,
    );
    if (assistantIndex <= 0) return '';
    final prefix = messages.sublist(0, assistantIndex);
    final userMessage = prefix.lastWhere(
      (m) => m.role == ChatMessageRole.user,
      orElse: () => prefix.first,
    );
    return userMessage.content;
  }
}

/// 由普通 Provider 从 [chatFavoritesFacadeProvider] 创建，不新增 app concrete bridge。
final chatFavoriteIntentCommandProvider = Provider<ChatFavoriteIntentCommand>((
  ref,
) {
  return ChatFavoriteIntentCommand(ref.watch(chatFavoritesFacadeProvider));
});
