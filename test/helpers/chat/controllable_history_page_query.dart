import 'dart:async';

import 'package:oh_my_llm/features/chat/application/ports/history_page_query.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

/// 可控的历史页查询替身：每个请求暴露独立 Completer，由测试决定完成时机。
///
/// 不使用 timer、固定延迟或真实 SQLite；controller 的有界调度、latest-wins
/// 与失败/迟到的时序全部通过手动完成 completer 驱动。
class ControllableHistoryPageQuery implements HistoryPageQuery {
  final List<HistoryPageRequest> requests = [];
  final List<Completer<HistoryPageResult>> _completers = [];
  bool _disposed = false;

  /// 尚未完成的请求数。
  int get pendingCount =>
      _completers.where((completer) => !completer.isCompleted).length;

  /// 第 [index] 次请求对应的 completer（按收到的顺序）。
  Completer<HistoryPageResult> completerAt(int index) => _completers[index];

  /// 以成功结果完成第 [index] 次请求。
  void completeSuccess(
    int index, {
    List<ChatConversationSummary> items = const [],
    required int totalItems,
    int committedPage = 1,
  }) {
    _completers[index].complete(
      HistoryPageResult(
        items: items,
        totalItems: totalItems,
        committedPage: committedPage,
      ),
    );
  }

  /// 以 [HistoryPageQueryException] 完成第 [index] 次请求。
  void completeFailure(int index, [String message = '查询失败']) {
    _completers[index].completeError(HistoryPageQueryException(message));
  }

  @override
  Future<HistoryPageResult> load(HistoryPageRequest request) {
    if (_disposed) {
      throw HistoryPageQueryException('query 已 dispose');
    }
    requests.add(request);
    final completer = Completer<HistoryPageResult>();
    _completers.add(completer);
    return completer.future;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final completer in _completers) {
      if (!completer.isCompleted) {
        completer.completeError(
          const HistoryPageQueryException('query 已 dispose'),
        );
      }
    }
  }
}
