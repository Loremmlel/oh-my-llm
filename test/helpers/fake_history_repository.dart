import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

/// 测试用 mock 仓库，按调用顺序返回预设页面。
///
/// 用于 history_pagination_controller_test.dart 与
/// history_screen_auto_load_cases.dart，避免两处重复实现。
///
/// [pages] 按调用顺序被消耗：每次 [loadHistorySummaries] 被调用时，
/// 返回 pages[_callIndex] 并将 _callIndex 自增。超出范围后返回空列表
/// 且 hasMore=false，避免越界。
///
/// [calls] 记录每次调用的入参（keyword/limit/offset），便于断言。
/// 注意：ChatSessionsController.build() 会先调用一次无参的
/// loadHistorySummaries()，该调用也会被记录在 calls 中（limit/offset
/// 均为 null）。
class FakeHistoryRepository implements ChatConversationRepository {
  FakeHistoryRepository({required this.pages});

  /// 按调用顺序返回的页面列表。
  final List<({List<ChatConversationSummary> summaries, bool hasMore})> pages;

  int _callIndex = 0;

  /// 每次 loadHistorySummaries 的入参记录。
  final List<({String keyword, int? limit, int? offset})> calls = [];

  /// 已消耗的调用次数。
  int get callCount => _callIndex;

  /// 仅包含带 limit 的调用（即 HistoryPaginationController 的分页调用），
  /// 过滤掉 ChatSessionsController.build() 的无参调用。
  List<({String keyword, int? limit, int? offset})> get pagedCalls =>
      calls.where((c) => c.limit != null).toList();

  ({List<ChatConversationSummary> summaries, bool hasMore}) _next() {
    if (_callIndex >= pages.length) {
      return (summaries: const [], hasMore: false);
    }
    return pages[_callIndex++];
  }

  @override
  ({List<ChatConversationSummary> summaries, bool hasMore}) loadHistorySummaries({
    String keyword = '',
    int? limit,
    int? offset,
  }) {
    calls.add((keyword: keyword, limit: limit, offset: offset));
    return _next();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
