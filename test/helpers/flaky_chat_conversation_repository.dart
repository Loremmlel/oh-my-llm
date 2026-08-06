import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

/// 测试用故障仓库：委托真实 [SqliteChatConversationRepository]（内存库），
/// 按开关在 [saveConversation] / [saveConversations] 抛异常，用于验证 generation
/// 关键 checkpoint 的 durable save 失败被正确感知（persistenceFailed / inline error），
/// 且不触发重复网络请求或假成功。
///
/// 与 [FakeHistoryRepository] 不同：本类显式转发全部方法到真实仓库，避免
/// `noSuchMethod` 转发导致 generation 路径上的 save/load 行为不一致。
class FlakyChatConversationRepository implements ChatConversationRepository {
  FlakyChatConversationRepository(AppDatabase database)
    : _inner = SqliteChatConversationRepository(database);

  final SqliteChatConversationRepository _inner;

  /// 下一次 [saveConversation] 是否抛异常。
  bool failSaveConversation = false;

  /// [saveConversations] 是否抛异常。
  bool failSaveConversations = false;

  /// 第 N 次 [saveConversation] 调用抛异常（1-based，null=不按序号触发）。
  /// 用于区分 pending save（第 1 次）与 terminal/retry save（第 2+ 次）失败。
  int? failOnSaveCallIndex;

  /// [saveConversation] 被调用的次数。
  int saveConversationCallCount = 0;

  /// [saveConversations] 被调用的次数。
  int saveConversationsCallCount = 0;

  @override
  Future<void> saveConversation(ChatConversation conversation) async {
    saveConversationCallCount++;
    if (failSaveConversation ||
        failOnSaveCallIndex == saveConversationCallCount) {
      throw Exception(
        'durable save failed (saveConversation #$saveConversationCallCount)',
      );
    }
    // 直接走 _inner.saveConversations，绕过 saveConversation 的转发计数，
    // 避免重复计数干扰断言。
    await _inner.saveConversations([conversation]);
  }

  @override
  Future<void> saveConversations(List<ChatConversation> conversations) async {
    saveConversationsCallCount++;
    if (failSaveConversations) {
      throw Exception('durable save failed (saveConversations)');
    }
    await _inner.saveConversations(conversations);
  }

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
