import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Chat 侧所需的收藏夹选项快照。
final class ChatFavoriteCollectionOption {
  const ChatFavoriteCollectionOption({required this.id, required this.name});

  final String id;
  final String name;
}

/// Chat 侧传递的收藏内容及来源元数据。
final class ChatFavoriteDraft {
  const ChatFavoriteDraft({
    required this.userMessageContent,
    required this.assistantContent,
    required this.assistantReasoningContent,
    required this.assistantModelDisplayName,
    required this.collectionId,
    required this.sourceAssistantMessageId,
    required this.sourceConversationId,
    required this.sourceConversationTitle,
  });

  final String userMessageContent;
  final String assistantContent;
  final String assistantReasoningContent;
  final String assistantModelDisplayName;
  final String? collectionId;
  final String? sourceAssistantMessageId;
  final String? sourceConversationId;
  final String? sourceConversationTitle;

  /// 复制并替换 collectionId（'' 已在调用方归一为 null 前透传）。
  ChatFavoriteDraft copyWithCollectionId(String? collectionId) {
    return ChatFavoriteDraft(
      userMessageContent: userMessageContent,
      assistantContent: assistantContent,
      assistantReasoningContent: assistantReasoningContent,
      assistantModelDisplayName: assistantModelDisplayName,
      collectionId: collectionId,
      sourceAssistantMessageId: sourceAssistantMessageId,
      sourceConversationId: sourceConversationId,
      sourceConversationTitle: sourceConversationTitle,
    );
  }
}

/// Chat 侧用于取消收藏和撤销操作的只读条目。
final class ChatFavoriteEntry {
  const ChatFavoriteEntry({required this.id, required this.draft});

  final String id;
  final ChatFavoriteDraft draft;
}

/// Chat 侧所需的收藏快照。
final class ChatFavoritesSnapshot {
  const ChatFavoritesSnapshot({
    required this.entries,
    required this.collections,
  });

  final List<ChatFavoriteEntry> entries;
  final List<ChatFavoriteCollectionOption> collections;

  Set<String> get favoritedAssistantContents =>
      entries.map((entry) => entry.draft.assistantContent).toSet();

  ChatFavoriteEntry? findByAssistantContent(String assistantContent) {
    for (final entry in entries) {
      if (entry.draft.assistantContent == assistantContent) return entry;
    }
    return null;
  }
}

/// Chat 面向用户收藏 intent 的跨 feature 边界。
abstract interface class ChatFavoritesFacade {
  ChatFavoritesSnapshot get snapshot;

  String createCollection(String name);

  void add(ChatFavoriteDraft draft);

  void remove(String favoriteId);
}

/// 必须由 app composition 或测试显式绑定的收藏 intent 实现。
final chatFavoritesFacadeProvider = Provider<ChatFavoritesFacade>((ref) {
  throw StateError('ChatFavoritesFacade 尚未由应用组合层绑定');
});
