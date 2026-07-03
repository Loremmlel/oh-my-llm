import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_conversation_repository.dart';
import '../domain/history_pagination_state.dart';
import '../domain/models/chat_conversation_summary.dart';

/// 首次进入历史页加载的对话数量。
const initialPageSize = 50;

/// 滚动到底部时追加加载的数量。
const pageIncrement = 30;

/// 历史页分页数据控制器。
///
/// 负责分页查询、搜索关键词变更、追加加载以及 rename/delete 后的
/// 本地数据修正。UI 层通过 [historyPaginationProvider] watch 此控制器的
/// 状态，并将滚动/搜索事件转发为方法调用。
///
/// 使用 [Notifier]（而非 [AsyncNotifier]），因为底层 SQLite 查询是同步的。
class HistoryPaginationController extends Notifier<HistoryPaginationState> {
  @override
  HistoryPaginationState build() {
    return const HistoryPaginationState();
  }

  ChatConversationRepository get _repository =>
      ref.read(chatConversationRepositoryProvider);

  /// 首次加载（或搜索重置后）的分页查询。
  void loadInitial({String keyword = ''}) {
    final result = _repository.loadHistorySummaries(
      keyword: keyword,
      limit: initialPageSize,
      offset: 0,
    );
    state = HistoryPaginationState(
      conversations: result.summaries,
      hasMore: result.hasMore,
      isLoading: false,
      keyword: keyword,
      hasAnyConversations:
          keyword.isEmpty ? result.summaries.isNotEmpty : true,
    );
  }

  /// 追加加载下一页。
  void loadMore() {
    final current = state;
    if (current.isLoading || !current.hasMore) return;

    state = current.copyWith(isLoading: true);

    final next = _repository.loadHistorySummaries(
      keyword: current.keyword,
      limit: pageIncrement,
      offset: current.conversations.length,
    );
    state = current.copyWith(
      conversations: [...current.conversations, ...next.summaries],
      hasMore: next.hasMore,
      isLoading: false,
    );
  }

  /// 变更搜索关键词并重置分页。
  void setKeyword(String keyword) {
    loadInitial(keyword: keyword);
  }

  /// 重命名后在本地列表中更新标题，避免全量刷新丢失滚动位置。
  void afterRename(String conversationId, String newTitle) {
    final updated = state.conversations.map((summary) {
      if (summary.id != conversationId) return summary;
      return ChatConversationSummary(
        id: summary.id,
        updatedAt: summary.updatedAt,
        title: newTitle,
        firstUserMessagePreview: summary.firstUserMessagePreview,
        latestUserMessagePreview: summary.latestUserMessagePreview,
      );
    }).toList();

    state = state.copyWith(conversations: updated);
  }

  /// 删除后从本地列表中移除，保留其他已加载的分页数据。
  void afterDelete(Set<String> deletedIds) {
    final remaining =
        state.conversations
            .where((c) => !deletedIds.contains(c.id))
            .toList();

    state = state.copyWith(
      conversations: remaining,
      hasAnyConversations:
          state.keyword.isEmpty ? remaining.isNotEmpty : true,
    );
  }
}

/// 历史页分页数据的 notifier provider。
final historyPaginationProvider =
    NotifierProvider<HistoryPaginationController, HistoryPaginationState>(
  HistoryPaginationController.new,
);
