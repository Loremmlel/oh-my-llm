import 'package:equatable/equatable.dart';

import 'models/chat_conversation_summary.dart';

/// 历史页分页栏的状态快照。
///
/// 与旧版「无限累积窗口」模型不同，本状态仅描述**当前页**的数据窗口；
/// 总条目数由 [totalItems] 显式持有，配合 [pageSize] 派生出
/// [totalPages] / [hasPrevious] / [hasNext]，由分页栏 UI 直接渲染。
///
/// 将分页逻辑从 UI 层抽离到 [HistoryPaginationController]，
/// 使 HistoryScreen 只需要 watch 此状态 + 转发翻页/搜索事件。
class HistoryPaginationState extends Equatable {
  const HistoryPaginationState({
    this.conversations = const [],
    this.isLoading = false,
    this.keyword = '',
    this.hasAnyConversations = false,
    this.currentPage = 1,
    this.pageSize = 20,
    this.totalItems = 0,
  });

  /// 当前页已加载的会话摘要（仅当前页，非累积窗口）。
  final List<ChatConversationSummary> conversations;

  /// 是否正在执行分页加载（不论首次还是翻页）。
  final bool isLoading;

  /// 当前生效的搜索关键词。
  final String keyword;

  /// 数据库中是否存在任何会话（不区分 keyword），用于空状态文案。
  final bool hasAnyConversations;

  /// 当前页码（从 1 开始）。
  final int currentPage;

  /// 每页显示的条目数。
  final int pageSize;

  /// 满足当前 keyword 条件的会话总数。
  final int totalItems;

  /// 派生：总页数。
  int get totalPages => pageSize <= 0 ? 0 : (totalItems / pageSize).ceil();

  /// 派生：是否存在上一页（即 currentPage > 1）。
  bool get hasPrevious => currentPage > 1;

  /// 派生：是否存在下一页（即 currentPage < totalPages）。
  bool get hasNext => currentPage < totalPages;

  HistoryPaginationState copyWith({
    List<ChatConversationSummary>? conversations,
    bool? isLoading,
    String? keyword,
    bool? hasAnyConversations,
    int? currentPage,
    int? pageSize,
    int? totalItems,
  }) {
    return HistoryPaginationState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
      keyword: keyword ?? this.keyword,
      hasAnyConversations:
          hasAnyConversations ?? this.hasAnyConversations,
      currentPage: currentPage ?? this.currentPage,
      pageSize: pageSize ?? this.pageSize,
      totalItems: totalItems ?? this.totalItems,
    );
  }

  @override
  List<Object?> get props => [
    conversations,
    isLoading,
    keyword,
    hasAnyConversations,
    currentPage,
    pageSize,
    totalItems,
  ];
}
