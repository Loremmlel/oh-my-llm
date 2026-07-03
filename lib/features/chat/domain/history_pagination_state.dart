import 'package:equatable/equatable.dart';

import 'models/chat_conversation_summary.dart';

/// 历史页分页加载的状态快照。
///
/// 将分页逻辑从 UI 层抽离到 [HistoryPaginationController]，
/// 使 HistoryScreen 只需要 watch 此状态 + 转发滚动/事件操作。
class HistoryPaginationState extends Equatable {
  const HistoryPaginationState({
    this.conversations = const [],
    this.hasMore = true,
    this.isLoading = false,
    this.keyword = '',
    this.hasAnyConversations = true,
  });

  /// 当前已加载的会话摘要（按分页窗口截断，非全量）。
  final List<ChatConversationSummary> conversations;

  /// 是否还有更多数据未加载。
  final bool hasMore;

  /// 是否正在执行分页加载（不论首次还是增量）。
  final bool isLoading;

  /// 当前生效的搜索关键词。
  final String keyword;

  /// 数据库中是否存在任何会话（不区分 keyword），用于空状态文案。
  final bool hasAnyConversations;

  HistoryPaginationState copyWith({
    List<ChatConversationSummary>? conversations,
    bool? hasMore,
    bool? isLoading,
    String? keyword,
    bool? hasAnyConversations,
  }) {
    return HistoryPaginationState(
      conversations: conversations ?? this.conversations,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      keyword: keyword ?? this.keyword,
      hasAnyConversations:
          hasAnyConversations ?? this.hasAnyConversations,
    );
  }

  @override
  List<Object?> get props => [
    conversations,
    hasMore,
    isLoading,
    keyword,
    hasAnyConversations,
  ];
}
