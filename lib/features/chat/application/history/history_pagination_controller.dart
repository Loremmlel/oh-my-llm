import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/chat/application/history/history_browse_preferences_controller.dart';

import '../../domain/history_pagination_state.dart';
import '../ports/chat_conversation_repository.dart';

export '../../domain/history_pagination_state.dart' show availablePageSizes;

/// 查询失败时的通用错误文案；具体呈现方式由 UI 决定。
const historyLoadErrorMessage = '加载历史记录失败';

/// 历史页分页栏数据控制器。
///
/// 负责「route 加载 / 翻页 / 切换每页条数 / 搜索 / rename/delete 后修正」。
/// UI 层通过 [historyPaginationProvider] watch 此控制器的状态，并将翻页/
/// 搜索事件转发为方法调用。
///
/// 使用 [Notifier]（而非 [AsyncNotifier]），因为底层 SQLite 查询是同步的。
///
/// 状态语义：[HistoryPaginationState.conversations] 仅包含**当前页**的数据；
/// 总条目数由 `totalItems` 显式持有。任何改变数据分布的操作（删除、搜索态
/// rename）都通过 [_reloadCurrentWindow] 按数据库真实结果重新查询，不做
/// 本地推断补页。
class HistoryPaginationController extends Notifier<HistoryPaginationState> {
  @override
  HistoryPaginationState build() {
    return const HistoryPaginationState();
  }

  ChatConversationRepository get _repository =>
      ref.read(chatConversationRepositoryProvider);

  /// 判断「是否有任何会话」：非空串 keyword 下不应打扰用户空状态展示，
  /// 否则跟随 totalItems。
  bool _calcHasAny(String keyword, int totalItems) =>
      keyword.isNotEmpty || totalItems > 0;

  // ── 查询核心 ────────────────────────────────────────────

  /// 按 route 参数加载历史窗口；route 是 page/pageSize/keyword 的唯一入口。
  ///
  /// 所有输入在此处统一 trim、校验与夹取：
  /// - [keyword] trim 后生效，缺省沿用当前关键词；
  /// - [pageSize] 仅接受 [availablePageSizes]；合法显式值回写偏好，
  ///   非法或缺省回退持久化偏好（偏好自身保证合法，默认 20）；
  /// - [page] 缺省视为 1，查询后按真实总数夹取到 [1, totalPages]。
  void loadRoute({int? page, int? pageSize, String? keyword}) {
    final nextKeyword = (keyword ?? state.keyword).trim();
    int nextPageSize;
    if (pageSize != null && availablePageSizes.contains(pageSize)) {
      nextPageSize = pageSize;
      // 合法的显式容量回写偏好；写失败不影响本次浏览。
      unawaited(
        ref.read(historyBrowsePreferencesProvider.notifier).save(pageSize),
      );
    } else {
      nextPageSize = ref.read(historyBrowsePreferencesProvider);
    }

    state = state.copyWith(isLoading: true);
    _reloadCurrentWindow(
      requestedPage: page ?? 1,
      keyword: nextKeyword,
      pageSize: nextPageSize,
    );
  }

  /// 统一的当前窗口重载：count → 夹取页码 → load 当前页 → 错误落定。
  ///
  /// 页码夹取基于查询后的真实总数，数据被外部变更时不会越界；
  /// count 与 load 任一失败时保留旧窗口内容并写入错误文案。
  void _reloadCurrentWindow({
    required int requestedPage,
    required String keyword,
    required int pageSize,
  }) {
    try {
      final totalItems = _repository.countHistorySummaries(keyword: keyword);
      final totalPages = pageSize <= 0 ? 0 : (totalItems / pageSize).ceil();
      final targetPage = totalPages <= 0
          ? 1
          : requestedPage < 1
          ? 1
          : (requestedPage > totalPages ? totalPages : requestedPage);
      final result = _repository.loadHistorySummaries(
        keyword: keyword,
        limit: pageSize,
        offset: (targetPage - 1) * pageSize,
      );
      state = state.copyWith(
        conversations: result,
        isLoading: false,
        isInitialized: true,
        errorMessage: null,
        keyword: keyword,
        hasAnyConversations: _calcHasAny(keyword, totalItems),
        currentPage: targetPage,
        pageSize: pageSize,
        totalItems: totalItems,
      );
    } catch (_) {
      // 查询失败：保留旧窗口内容（stale content），错误进入状态由 UI 呈现。
      state = state.copyWith(
        isLoading: false,
        isInitialized: true,
        errorMessage: historyLoadErrorMessage,
      );
    }
  }

  // ── 翻页与搜索 ──────────────────────────────────────────

  /// 跳转到指定页（夹取到 [1, totalPages] 区间）。
  void goToPage(int page) {
    if (state.isLoading) return;

    final totalPages = state.totalPages;
    if (totalPages <= 0) return;
    final clamped = page < 1 ? 1 : (page > totalPages ? totalPages : page);
    if (clamped == state.currentPage) return;

    state = state.copyWith(isLoading: true);
    _reloadCurrentWindow(
      requestedPage: clamped,
      keyword: state.keyword,
      pageSize: state.pageSize,
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
  /// [size] 仅在 [availablePageSizes] 中生效，否则保持当前 pageSize 不变；
  /// 生效时经 [loadRoute] 回写持久化偏好。
  void setPageSize(int size) {
    if (!availablePageSizes.contains(size)) return;
    if (size == state.pageSize) return;

    state = state.copyWith(pageSize: size);
    loadRoute(page: 1, pageSize: size, keyword: state.keyword);
  }

  /// 变更搜索关键词并重置到第 1 页。
  ///
  /// 空串且当前 keyword 也为空时直接返回，避免无意义刷新。
  /// 入参经 [loadRoute] 统一 trim。
  void setKeyword(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty && state.keyword.isEmpty) return;
    loadRoute(page: 1, keyword: trimmed);
  }

  // ── 数据变更后的窗口修正 ────────────────────────────────

  /// 重命名后的窗口修正。
  ///
  /// 搜索态下 rename 可能改变匹配集合，必须按 repository 结果重拉；
  /// 非搜索态仅本地更新标题，避免刷新丢失滚动位置。
  void afterRename(String conversationId, String newTitle) {
    if (state.keyword.isNotEmpty) {
      state = state.copyWith(isLoading: true);
      _reloadCurrentWindow(
        requestedPage: state.currentPage,
        keyword: state.keyword,
        pageSize: state.pageSize,
      );
      return;
    }

    final updated = state.conversations.map((summary) {
      if (summary.id != conversationId) return summary;
      return summary.copyWith(title: newTitle);
    }).toList();

    state = state.copyWith(conversations: updated);
  }

  /// 删除后一律按数据库真实结果重拉当前窗口。
  ///
  /// 删除会同时改变总数与 OFFSET 分布，任何「本地裁剪 + 推断补页」都会
  /// 造成漏项或残留，因此不做本地移除，统一走 [_reloadCurrentWindow]
  /// （页码越界由其按真实总数夹取回退）。
  void afterDelete(Set<String> deletedIds) {
    if (deletedIds.isEmpty) return;

    state = state.copyWith(isLoading: true);
    _reloadCurrentWindow(
      requestedPage: state.currentPage,
      keyword: state.keyword,
      pageSize: state.pageSize,
    );
  }
}

/// 历史页分页数据的 notifier provider。
final historyPaginationProvider =
    NotifierProvider<HistoryPaginationController, HistoryPaginationState>(
      HistoryPaginationController.new,
    );
