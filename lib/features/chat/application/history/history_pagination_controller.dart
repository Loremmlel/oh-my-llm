import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';
import 'package:oh_my_llm/features/chat/application/history/history_browse_preferences_controller.dart';

import '../../domain/history_pagination_state.dart';
import '../ports/history_page_query.dart';

/// 查询失败时的通用错误文案；具体呈现方式由 UI 决定。
const historyLoadErrorMessage = '加载历史记录失败';

/// 一次窗口加载调用对提交权的三态结论。
enum HistoryWindowLoadOutcome {
  /// 结果已提交为最新 committed 窗口。
  committed,

  /// 最新请求失败，stale 内容与错误态已落定。
  failed,

  /// 本调用不拥有提交权（no-op / 被更新目标超越 / controller 已 dispose）。
  ignored,
}

/// 一次窗口加载的内部执行单元；只在 controller 文件内存在。
final class _HistoryLoadOperation {
  _HistoryLoadOperation({required this.generation, required this.request});

  final int generation;
  final HistoryPageRequest request;
  final Completer<HistoryWindowLoadOutcome> completer =
      Completer<HistoryWindowLoadOutcome>();
}

/// 历史页分页栏数据控制器。
///
/// 负责「route 加载 / 翻页 / 切换每页条数 / 搜索 / rename/delete 后修正」。
/// UI 层通过 [historyPaginationProvider] watch 此控制器的状态，并将翻页/
/// 搜索事件转发为方法调用。
///
/// 使用 [Notifier]（而非 [AsyncNotifier]）：状态需要表达「最后成功提交的
/// 窗口 + 在途重载时的 stale content」，单一 async 值无法同时携带两者。
///
/// 状态语义：[HistoryPaginationState] 始终表示**最后成功提交的窗口**；
/// pending 的 keyword/page/pageSize 不提前写入 committed 字段，唯一允许
/// 提前变化的是 `isLoading=true`（UI 显示 busy 并保留旧列表）。窗口查询
/// 经 [HistoryPageQuery] 异步执行；任意时刻最多「1 个 active + 1 个 latest
/// pending」，旧成功与旧失败都不覆盖新目标。
class HistoryPaginationController extends Notifier<HistoryPaginationState> {
  @override
  HistoryPaginationState build() {
    ref.onDispose(() {
      _disposed = true;
      final pending = _pendingLatest;
      _pendingLatest = null;
      if (pending != null) {
        _completeOperation(pending, HistoryWindowLoadOutcome.ignored);
      }
    });
    return const HistoryPaginationState();
  }

  HistoryPageQuery get _query => ref.read(historyPageQueryProvider);

  int _nextGeneration = 0;
  bool _disposed = false;
  _HistoryLoadOperation? _activeLoad;
  _HistoryLoadOperation? _pendingLatest;
  HistoryPageRequest? _latestRequestedWindow;
  HistoryPageRequest? _failedRequest;

  /// 判断「是否有任何会话」：非空串 keyword 下不应打扰用户空状态展示，
  /// 否则跟随 totalItems。
  bool _calcHasAny(String keyword, int totalItems) =>
      keyword.isNotEmpty || totalItems > 0;

  /// no-op 比较使用的目标窗口：在途请求优先，否则回退 committed 窗口。
  HistoryPageRequest get _desiredWindow =>
      _latestRequestedWindow ??
      HistoryPageRequest(
        keyword: state.keyword,
        requestedPage: state.currentPage,
        pageSize: state.pageSize,
      );

  // ── 查询核心 ────────────────────────────────────────────

  /// 按 route 参数加载历史窗口；route 是 page/pageSize/keyword 的唯一入口。
  ///
  /// 所有输入在此处统一 trim 与校验：
  /// - [keyword] trim 后生效，缺省沿用当前关键词；
  /// - [pageSize] 仅接受 [appPageSizeOptions]；合法显式值回写偏好，
  ///   非法或缺省回退持久化偏好（偏好自身保证合法，默认 20）；
  /// - [page] 缺省视为 1；越界页码由查询实现按同快照总数夹取。
  Future<HistoryWindowLoadOutcome> loadRoute({
    int? page,
    int? pageSize,
    String? keyword,
  }) {
    final nextKeyword = (keyword ?? state.keyword).trim();
    int nextPageSize;
    if (pageSize != null && appPageSizeOptions.contains(pageSize)) {
      nextPageSize = pageSize;
      // 合法的显式容量回写偏好；写失败不影响本次浏览。
      unawaited(
        ref.read(historyBrowsePreferencesProvider.notifier).save(pageSize),
      );
    } else {
      nextPageSize = ref.read(historyBrowsePreferencesProvider);
    }

    return _scheduleLoad(
      HistoryPageRequest(
        keyword: nextKeyword,
        requestedPage: page ?? 1,
        pageSize: nextPageSize,
      ),
    );
  }

  /// 提交一个窗口目标：分配 generation、写 loading、收编 pending。
  ///
  /// 旧的 pending 目标立即以 `ignored` 结算；任意时刻最多「1 active +
  /// 1 latest pending」，避免把任意数量的旧请求送入查询实现。
  Future<HistoryWindowLoadOutcome> _scheduleLoad(
    HistoryPageRequest request, {
    bool isRetry = false,
  }) {
    if (_disposed) return Future.value(HistoryWindowLoadOutcome.ignored);
    final generation = ++_nextGeneration;
    if (!isRetry) {
      // 任何新的非 retry 目标都取代旧失败目标，避免 retry 复活过期窗口。
      _failedRequest = null;
    }
    _latestRequestedWindow = request;
    state = state.copyWith(isLoading: true);

    final operation = _HistoryLoadOperation(
      generation: generation,
      request: request,
    );
    final superseded = _pendingLatest;
    _pendingLatest = operation;
    if (superseded != null) {
      _completeOperation(superseded, HistoryWindowLoadOutcome.ignored);
    }
    if (_activeLoad == null) {
      unawaited(_drainLoads());
    }
    return operation.completer.future;
  }

  /// 串行排空 pending：一次只调用一个 `query.load`，结束后立即接续下一个。
  Future<void> _drainLoads() async {
    while (!_disposed) {
      final pending = _pendingLatest;
      if (pending == null) break;
      _pendingLatest = null;
      _activeLoad = pending;
      var outcome = HistoryWindowLoadOutcome.ignored;
      try {
        final result = await _query.load(pending.request);
        if (!_disposed && pending.generation == _nextGeneration) {
          state = state.copyWith(
            conversations: result.items,
            isLoading: false,
            isInitialized: true,
            errorMessage: null,
            keyword: pending.request.keyword,
            hasAnyConversations: _calcHasAny(
              pending.request.keyword,
              result.totalItems,
            ),
            currentPage: result.committedPage,
            pageSize: pending.request.pageSize,
            totalItems: result.totalItems,
          );
          _failedRequest = null;
          outcome = HistoryWindowLoadOutcome.committed;
        }
      } catch (_) {
        if (!_disposed && pending.generation == _nextGeneration) {
          // 最新失败：保留 committed 窗口（stale content），记录失败目标
          // 供 retry 重新提交。
          _failedRequest = pending.request;
          state = state.copyWith(
            isLoading: false,
            isInitialized: true,
            errorMessage: historyLoadErrorMessage,
          );
          outcome = HistoryWindowLoadOutcome.failed;
        }
      } finally {
        _activeLoad = null;
        _completeOperation(pending, outcome);
      }
    }
    // 没有 pending 时清空在途目标（失败后同样清空，使同一目标可重试）。
    if (_pendingLatest == null) {
      _latestRequestedWindow = null;
    }
  }

  void _completeOperation(
    _HistoryLoadOperation operation,
    HistoryWindowLoadOutcome outcome,
  ) {
    if (!operation.completer.isCompleted) {
      operation.completer.complete(outcome);
    }
  }

  // ── 翻页与搜索 ──────────────────────────────────────────

  /// 跳转到指定页；在途加载期间返回 `ignored`，分页栏忙碌时不接受新翻页。
  Future<HistoryWindowLoadOutcome> goToPage(int page) {
    if (state.isLoading) return Future.value(HistoryWindowLoadOutcome.ignored);

    final totalPages = state.totalPages;
    if (totalPages <= 0) return Future.value(HistoryWindowLoadOutcome.ignored);
    final clamped = clampPageToValidRange(page, totalPages);
    if (clamped == state.currentPage) {
      return Future.value(HistoryWindowLoadOutcome.ignored);
    }

    return _scheduleLoad(
      HistoryPageRequest(
        keyword: state.keyword,
        requestedPage: clamped,
        pageSize: state.pageSize,
      ),
    );
  }

  /// 跳转到上一页。
  Future<HistoryWindowLoadOutcome> prev() => goToPage(state.currentPage - 1);

  /// 跳转到下一页。
  Future<HistoryWindowLoadOutcome> next() => goToPage(state.currentPage + 1);

  /// 跳转到第一页。
  Future<HistoryWindowLoadOutcome> first() => goToPage(1);

  /// 跳转到最后一页。
  Future<HistoryWindowLoadOutcome> last() => goToPage(state.totalPages);

  /// 修改每页条数并重置到第 1 页。
  ///
  /// [size] 仅在 [appPageSizeOptions] 中生效，否则保持当前 pageSize 不变；
  /// 生效时立即异步回写持久化偏好，查询失败时可见窗口保持旧值。
  Future<HistoryWindowLoadOutcome> setPageSize(int size) {
    if (!appPageSizeOptions.contains(size)) {
      return Future.value(HistoryWindowLoadOutcome.ignored);
    }
    if (size == _desiredWindow.pageSize) {
      return Future.value(HistoryWindowLoadOutcome.ignored);
    }
    unawaited(ref.read(historyBrowsePreferencesProvider.notifier).save(size));
    return _scheduleLoad(
      HistoryPageRequest(
        keyword: _desiredWindow.keyword,
        requestedPage: 1,
        pageSize: size,
      ),
    );
  }

  /// 变更搜索关键词并重置到第 1 页。
  ///
  /// 入参统一 trim；no-op 比较对象是在途目标（缺省回退 committed），
  /// 因此「在途非空搜索后清空」会生成新请求，不会被空 committed 关键词
  /// 误判为 no-op。
  Future<HistoryWindowLoadOutcome> setKeyword(String keyword) {
    final trimmed = keyword.trim();
    final desired = _desiredWindow;
    if (trimmed.isEmpty && desired.keyword.isEmpty) {
      return Future.value(HistoryWindowLoadOutcome.ignored);
    }
    return _scheduleLoad(
      HistoryPageRequest(
        keyword: trimmed,
        requestedPage: 1,
        pageSize: desired.pageSize,
      ),
    );
  }

  /// 重试最近一次失败的目标；没有失败目标时重载当前 committed 窗口。
  Future<HistoryWindowLoadOutcome> retry() {
    return _scheduleLoad(
      _failedRequest ??
          HistoryPageRequest(
            keyword: state.keyword,
            requestedPage: state.currentPage,
            pageSize: state.pageSize,
          ),
      isRetry: true,
    );
  }

  // ── 数据变更后的窗口修正 ────────────────────────────────

  /// 重命名后的窗口修正。
  ///
  /// 搜索态下 rename 可能改变匹配集合，必须按查询结果重拉；非搜索态仅本地
  /// 更新标题，避免刷新丢失滚动位置。
  Future<HistoryWindowLoadOutcome> afterRename(
    String conversationId,
    String newTitle,
  ) {
    final desired = _desiredWindow;
    if (desired.keyword.isNotEmpty) {
      return _scheduleLoad(
        HistoryPageRequest(
          keyword: desired.keyword,
          requestedPage: state.currentPage,
          pageSize: desired.pageSize,
        ),
      );
    }

    final updated = state.conversations.map((summary) {
      if (summary.id != conversationId) return summary;
      return summary.copyWith(title: newTitle);
    }).toList();

    state = state.copyWith(conversations: updated);
    return Future.value(HistoryWindowLoadOutcome.committed);
  }

  /// 删除后一律按数据库真实结果重拉当前窗口。
  ///
  /// 删除会同时改变总数与 OFFSET 分布，任何「本地裁剪 + 推断补页」都会
  /// 造成漏项或残留，因此不做本地移除，统一重查（页码越界由查询实现按
  /// 真实总数夹取回退）。
  Future<HistoryWindowLoadOutcome> afterDelete(Set<String> deletedIds) {
    if (deletedIds.isEmpty) {
      return Future.value(HistoryWindowLoadOutcome.ignored);
    }

    final desired = _desiredWindow;
    return _scheduleLoad(
      HistoryPageRequest(
        keyword: desired.keyword,
        requestedPage: state.currentPage,
        pageSize: desired.pageSize,
      ),
    );
  }
}

/// 历史页分页数据的 notifier provider。
final historyPaginationProvider =
    NotifierProvider<HistoryPaginationController, HistoryPaginationState>(
      HistoryPaginationController.new,
    );
