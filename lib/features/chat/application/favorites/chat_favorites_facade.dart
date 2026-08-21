import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Chat 侧所需的收藏夹选项快照。
final class ChatFavoriteCollectionOption {
  const ChatFavoriteCollectionOption({
    required this.id,
    required this.name,
    this.isSystem = false,
  });

  final String id;
  final String name;

  /// 是否为系统收藏夹（如"未分类"），用于对话框内区分图标。
  final bool isSystem;
}

/// Chat 侧传递的收藏内容及来源元数据。
///
/// [collectionId] 必填非空；默认值来自最近有效收藏夹或系统"未分类"。
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
  final String collectionId;
  final String? sourceAssistantMessageId;
  final String? sourceConversationId;
  final String? sourceConversationTitle;

  /// 复制并替换 collectionId。
  ChatFavoriteDraft copyWithCollectionId(String collectionId) {
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

/// Chat 侧所需的收藏快照：针对当前会话消息定向查询的结果。
final class ChatFavoritesSnapshot {
  const ChatFavoritesSnapshot({
    required this.entries,
    required this.collections,
    required this.defaultCollectionId,
  });

  /// 当前会话中已收藏消息对应的条目（不含其他会话的收藏）。
  final List<ChatFavoriteEntry> entries;

  /// 收藏夹选项：系统"未分类"包含一次且置顶。
  final List<ChatFavoriteCollectionOption> collections;

  /// 新增收藏的默认目标：最近有效收藏夹，失效回退系统"未分类"。
  final String defaultCollectionId;

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
  /// 收藏库版本号：任何成功 mutation 后递增。
  ///
  /// 调用方 watch 该值建立重建依赖，再用 [snapshotFor] 定向重查；
  /// facade 实现不得要求调用方加载全量收藏 catalog。
  int get revision;

  /// 为当前会话的 assistant 消息内容集合构建定向收藏快照。
  ChatFavoritesSnapshot snapshotFor(Set<String> assistantContents);

  String createCollection(String name);

  void add(ChatFavoriteDraft draft);

  void remove(String favoriteId);
}

/// 必须由 app composition 或测试显式绑定的收藏 intent 实现。
final chatFavoritesFacadeProvider = Provider<ChatFavoritesFacade>((ref) {
  throw StateError('ChatFavoritesFacade 尚未由应用组合层绑定');
});
