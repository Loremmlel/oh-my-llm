import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

/// 测试用 mock 仓库，按调用顺序返回预设页面。
///
/// 用于 history_pagination_controller_test.dart 与
/// history_screen_pagination_bar_cases.dart，避免两处重复实现。
///
/// [pages] 按调用顺序被消耗：每次 [loadHistorySummaries] 带 limit 调用时，
/// 返回 pages[_callIndex] 并将 _callIndex 自增。超出范围后返回空列表。
///
/// [calls] 记录每次 [loadHistorySummaries] 的入参（keyword/limit/offset），便于断言。
/// 注意：ChatSessionsController.build() 会先调用一次无参的
/// loadHistorySummaries()，该调用也会被记录在 calls 中（limit/offset
/// 均为 null）。
///
/// [countResult] 控制 [countHistorySummaries] 的返回值：
/// - 非 null 时直接返回 [countResult]；
/// - null 时回退为 pages 所有 summaries 数量之和（便于只测分页而
///   不关心总数的场景）。
///
/// 若需模拟「计数随数据变更而变」的场景（例如 afterDelete），可使用
/// [sequenceCounts]：按调用顺序依次返回列表中的值；列表耗尽后固定返回
/// 最后一个值。[sequenceCounts] 的优先级高于 [countResult]。
class FakeHistoryRepository implements ChatConversationRepository {
  FakeHistoryRepository({
    required this.pages,
    this.countResult,
    List<int>? sequenceCounts,
  }) : _sequenceCounts = sequenceCounts;

  /// 按调用顺序返回的页面列表。
  final List<List<ChatConversationSummary>> pages;

  /// countHistorySummaries 的返回值；为 null 时回退为 pages 总结。
  final int? countResult;

  /// 按调用顺序消耗的计数返回值（优先级高于 countResult）。
  final List<int>? _sequenceCounts;
  int _countSequenceIndex = 0;

  int _callIndex = 0;

  /// 每次 loadHistorySummaries 的入参记录。
  final List<({String keyword, int? limit, int? offset})> calls = [];

  /// countHistorySummaries 被调用的次数。
  int countCallCount = 0;

  /// 已消耗的调用次数。
  int get callCount => _callIndex;

  /// 仅包含带 limit 的调用（即 HistoryPaginationController 的分页调用），
  /// 过滤掉 ChatSessionsController.build() 的无参调用。
  List<({String keyword, int? limit, int? offset})> get pagedCalls =>
      calls.where((c) => c.limit != null).toList();

  List<ChatConversationSummary> _next() {
    if (_callIndex >= pages.length) {
      return const [];
    }
    return pages[_callIndex++];
  }

  @override
  List<ChatConversationSummary> loadHistorySummaries({
    String keyword = '',
    int? limit,
    int? offset,
  }) {
    calls.add((keyword: keyword, limit: limit, offset: offset));
    return _next();
  }

  @override
  int countHistorySummaries({String keyword = ''}) {
    countCallCount++;
    final seq = _sequenceCounts;
    if (seq != null && seq.isNotEmpty) {
      final value = seq[_countSequenceIndex.clamp(0, seq.length - 1)];
      if (_countSequenceIndex < seq.length - 1) {
        _countSequenceIndex++;
      }
      return value;
    }
    if (countResult != null) return countResult!;
    return pages.fold(0, (sum, p) => sum + p.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
