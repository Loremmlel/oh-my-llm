import 'dart:async';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

/// 一次 [saveConversation] 调用的可控门。
///
/// 测试 await [reached] 确认 save 已进入（尚未写入 inner），再通过 [release]
/// 决定何时放行、或设置 [error] 模拟落盘失败。reached / release 分离使测试能在
/// 精确的 save 时点同步，而非依赖毫秒级 delay 或脆弱的固定字段顺序。
class SaveGate {
  SaveGate(this.index);

  /// 本次 gate 对应的 1-based save 调用序号。
  final int index;

  /// save 进入 gate 时完成，供测试 await。
  final Completer<void> reached = Completer<void>();

  /// 测试主动 complete 以放行 save；未 complete 前 save 一直挂起。
  final Completer<void> release = Completer<void>();

  /// release 时若非 null，则 save 抛出此异常模拟落盘失败。
  Object? error;

  bool get shouldFail => error != null;
}

/// 可控的会话持久化仓库：包装真实内存 [SqliteChatConversationRepository]，
/// 在 generation 关键 checkpoint（pending / intermediate / terminal / stop save）
/// 真正写入 inner 前设置 gate，使竞态测试能在精确的 save 时点同步。
///
/// gate 按 1-based 调用序号注册：第 N 次 [saveConversation] 命中 gate[N] 时，
/// 先 complete [SaveGate.reached]（让测试知道 save 已到达、尚未落盘），再 await
/// [SaveGate.release]（测试决定何时放行），可选抛 [SaveGate.error] 模拟落盘失败。
/// 未注册 gate 的 save 直接委托 inner，行为与生产一致。
///
/// 测试用 [saveCalls]（每次 save 的 conversation 快照）+ 内容断言验证 save 语义
/// （pending / terminal / stop），而非依赖调用序号本身的语义稳定性--
/// 后者在 retry / 多 attempt 场景下会因额外 intermediate save 而错位。
class ControllableChatConversationRepository
    implements ChatConversationRepository {
  ControllableChatConversationRepository(AppDatabase database)
    : _inner = SqliteChatConversationRepository(database);

  final SqliteChatConversationRepository _inner;

  /// 每次进入 [saveConversation] 时记录的 conversation 快照（gate 拦截前）。
  /// 供测试按内容（assistantMessageId / isStreaming / 内容）断言 save 语义。
  final List<ChatConversation> saveCalls = [];

  final Map<int, SaveGate> _gates = {};

  /// 为第 [oneBasedIndex] 次 [saveConversation] 注册 gate。返回 gate 供测试
  /// await reached / complete release。重复注册同一序号会覆盖旧 gate。
  SaveGate gateSave(int oneBasedIndex) {
    final gate = SaveGate(oneBasedIndex);
    _gates[oneBasedIndex] = gate;
    return gate;
  }

  /// 等待第 [oneBasedIndex] 次 save 进入 gate（[SaveGate.reached] 完成）。
  Future<void> awaitReached(int oneBasedIndex) {
    final gate = _gates[oneBasedIndex];
    if (gate == null) {
      throw StateError('未为第 $oneBasedIndex 次 save 注册 gate');
    }
    return gate.reached.future;
  }

  /// 放行第 [oneBasedIndex] 次 save；[error] 非空时模拟落盘失败抛出。
  void releaseSave(int oneBasedIndex, {Object? error}) {
    final gate = _gates[oneBasedIndex];
    if (gate == null) {
      throw StateError('未为第 $oneBasedIndex 次 save 注册 gate');
    }
    if (error != null) gate.error = error;
    if (!gate.release.isCompleted) gate.release.complete();
  }

  /// 已完成的 [saveConversation] 调用次数。
  int get saveCallCount => saveCalls.length;

  @override
  Future<void> saveConversation(ChatConversation conversation) async {
    final index = saveCalls.length + 1; // 1-based
    saveCalls.add(conversation);
    final gate = _gates[index];
    if (gate != null) {
      if (!gate.reached.isCompleted) gate.reached.complete();
      await gate.release.future;
      if (gate.shouldFail) {
        throw gate.error!;
      }
    }
    await _inner.saveConversation(conversation);
  }

  @override
  Future<void> saveConversations(List<ChatConversation> conversations) =>
      _inner.saveConversations(conversations);

  @override
  List<ChatConversation> loadAll() => _inner.loadAll();

  @override
  ChatConversation? loadConversation(String id) => _inner.loadConversation(id);

  @override
  List<ChatConversationSummary> loadHistorySummaries({
    String keyword = '',
    int? limit,
    int? offset,
  }) => _inner.loadHistorySummaries(
    keyword: keyword,
    limit: limit,
    offset: offset,
  );

  @override
  int countHistorySummaries({String keyword = ''}) =>
      _inner.countHistorySummaries(keyword: keyword);

  @override
  Future<void> deleteConversations(List<String> ids) =>
      _inner.deleteConversations(ids);

  @override
  Future<void> flush() => _inner.flush();

  @override
  Future<void> close() => _inner.close();
}
