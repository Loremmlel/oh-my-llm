import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/chat_conversation_summary.dart';

/// 历史页窗口查询请求：一个 count + 当前页的完整语义单元。
///
/// [requestedPage] 允许越界，由实现按同一查询快照的总数夹取；
/// [keyword] 构造时 trim，大小写与 LIKE 转义语义仍由 SQLite 实现定义。
final class HistoryPageRequest extends Equatable {
  HistoryPageRequest({
    required String keyword,
    required this.requestedPage,
    required this.pageSize,
  }) : keyword = keyword.trim() {
    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize', '必须大于 0');
    }
  }

  final String keyword;
  final int requestedPage;
  final int pageSize;

  @override
  List<Object?> get props => [keyword, requestedPage, pageSize];
}

/// 历史页窗口查询结果：夹取后的提交页与同快照总数。
final class HistoryPageResult extends Equatable {
  HistoryPageResult({
    required List<ChatConversationSummary> items,
    required this.totalItems,
    required this.committedPage,
  }) : items = List.unmodifiable(items) {
    if (totalItems < 0) {
      throw ArgumentError.value(totalItems, 'totalItems', '不得小于 0');
    }
    if (committedPage < 1) {
      throw ArgumentError.value(committedPage, 'committedPage', '必须至少为 1');
    }
  }

  final List<ChatConversationSummary> items;
  final int totalItems;
  final int committedPage;

  @override
  List<Object?> get props => [items, totalItems, committedPage];
}

/// 历史页查询失败的统一异常；内部错误文本不直接展示给用户。
class HistoryPageQueryException implements Exception {
  const HistoryPageQueryException(this.message);

  final String message;

  @override
  String toString() => 'HistoryPageQueryException: $message';
}

/// 历史页分页窗口的查询 seam。
///
/// controller 只通过 [load] 提交一个窗口请求并异步得到完整窗口；
/// COUNT、页码夹取、page SELECT、row mapping、worker 生命周期与异常映射
/// 都是实现细节，不出现在本接口。
abstract interface class HistoryPageQuery {
  /// 提交一次窗口查询；数据库 / worker / 协议错误统一抛
  /// [HistoryPageQueryException]。
  Future<HistoryPageResult> load(HistoryPageRequest request);

  /// 释放底层资源；幂等，dispose 开始后新的 [load] 立即失败。
  Future<void> dispose();
}

/// 必须由 app composition 或测试显式绑定的历史页查询实现。
final historyPageQueryProvider = Provider<HistoryPageQuery>((ref) {
  throw StateError('HistoryPageQuery 尚未由应用组合层绑定');
});
