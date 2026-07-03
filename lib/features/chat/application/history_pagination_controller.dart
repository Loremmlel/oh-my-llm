import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_conversation_repository.dart';
import '../domain/history_pagination_state.dart';
import '../domain/models/chat_conversation_summary.dart';

/// 默认每页显示的对话数量。
const defaultPageSize = 20;

/// 可供用户选择的每页条数选项。
const availablePageSizes = <int>[10, 20, 50];

/// 历史页分页栏数据控制器。
///
/// 负责管理「翻页 / 切换每页条数 / 搜索 / 跳转」以及 rename/delete
/// 后的本地数据修正。UI 层通过 [historyPaginationProvider] watch 此控制器的
/// 状态，并将翻页/搜索事件转发为方法调用。
///
/// 使用 [Notifier]（而非 [AsyncNotifier]），因为底层 SQLite 查询是同步的。
///
/// 状态语义与旧版「无限累积窗口」不同：[HistoryPaginationState.conversations]
/// 仅包含**当前页**的数据；总条目数由 `totalItems` 显式持有，分页栏直接渲染。
class HistoryPaginationController extends Notifier<HistoryPaginationState> {
  @override
  HistoryPaginationState build() {
    return const HistoryPaginationState();
  }

  ChatConversationRepository get _repository =>
      ref.read(chatConversationRepositoryProvider);

  /// 首次加载（或搜索重置后）的分页查询。
  ///
  /// 重置到第 1 页，同时拉取总数和当前页数据。
  void loadInitial({String keyword = ''}) {
    final pageSize = state.pageSize;
    final totalItems = _repository.countHistorySummaries(keyword: keyword);
    final result = _repository.loadHistorySummaries(
      keyword: keyword,
      limit: pageSize,
      offset: 0,
    );
    state = HistoryPaginationState(
      conversations: result,
      isLoading: false,
      keyword: keyword,
      hasAnyConversations:
          keyword.isEmpty ? totalItems > 0 : true,
      currentPage: 1,
      pageSize: pageSize,
      totalItems: totalItems,
    );
  }

  /// 跳转到指定页（夹取到 [1, totalPages] 区间）。
  void goToPage(int page) {
    if (state.isLoading) return;

    final totalPages = state.totalPages;
    if (totalPages <= 0) return;
    final clamped = page.clamp(1, totalPages);
    if (clamped == state.currentPage) return;

    state = state.copyWith(isLoading: true);

    final result = _repository.loadHistorySummaries(
      keyword: state.keyword,
      limit: state.pageSize,
      offset: (clamped - 1) * state.pageSize,
    );
    state = state.copyWith(
      conversations: result,
      isLoading: false,
      currentPage: clamped,
    );
  }

  /// 跳转到上一页。
  void prev() => goToPage(state.currentPage - 1);

  /// 跳转到下一页。
  void next() => goToPage(state.currentPage + 1);

  /// 跳转到第一页。
  void first() => goToPage(1);

  /// 跳转到最后一页。
  void last() => goToPage(state.totalPages);

  /// 修改每页条数并重置到第 1 页。
  ///
  /// [size] 仅在 [availablePageSizes] 中生效，否则保持当前 pageSize 不变。
  void setPageSize(int size) {
    if (!availablePageSizes.contains(size)) return;
    if (size == state.pageSize) return;

    final totalItems = _repository.countHistorySummaries(keyword: state.keyword);
    final result = _repository.loadHistorySummaries(
      keyword: state.keyword,
      limit: size,
      offset: 0,
    );
    state = state.copyWith(
      conversations: result,
      isLoading: false,
      currentPage: 1,
      pageSize: size,
      totalItems: totalItems,
    );
  }

  /// 变更搜索关键词并重置到第 1 页。
  ///
  /// 空串且当前 keyword 也为空时直接返回，避免无意义刷新。
  /// 入参会先 trim，与 [loadHistorySummaries] 的语义保持一致。
  void setKeyword(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty && state.keyword.isEmpty) return;
    loadInitial(keyword: trimmed);
  }

  /// 重命名后在当前页本地列表中更新标题，避免刷新丢失滚动位置。
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

  /// 删除后从当前页本地列表中移除。
  ///
  /// 若删除后当前页码超出新的总页数（例如删光最后一页的条目），
  /// 自动回退到新的最后一页并重新拉取。
  void afterDelete(Set<String> deletedIds) {
    final remaining =
        state.conversations
            .where((c) => !deletedIds.contains(c.id))
            .toList();

    final newTotalItems =
        _repository.countHistorySummaries(keyword: state.keyword);
    final newTotalPages = newTotalItems <= 0
        ? 0
        : (newTotalItems / state.pageSize).ceil();

    if (newTotalPages <= 0) {
      // 库被清空。
      state = state.copyWith(
        conversations: const [],
        hasAnyConversations: state.keyword.isEmpty ? false : true,
        currentPage: 1,
        totalItems: 0,
      );
      return;
    }

    if (state.currentPage <= newTotalPages) {
      // 当前页仍有效，仅本地移除。
      state = state.copyWith(
        conversations: remaining,
        hasAnyConversations: state.keyword.isEmpty
            ? newTotalItems > 0
            : true,
        totalItems: newTotalItems,
      );
      return;
    }

    // 当前页已越界，回退到最后一页并重新拉取。
    final target = newTotalPages;
    final result = _repository.loadHistorySummaries(
      keyword: state.keyword,
      limit: state.pageSize,
      offset: (target - 1) * state.pageSize,
    );
    state = state.copyWith(
      conversations: result,
      hasAnyConversations: state.keyword.isEmpty
          ? newTotalItems > 0
          : true,
      currentPage: target,
      totalItems: newTotalItems,
    );
  }
}

/// 历史页分页数据的 notifier provider。
final historyPaginationProvider =
    NotifierProvider<HistoryPaginationController, HistoryPaginationState>(
  HistoryPaginationController.new,
);
