import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';

/// 用于不满屏自动追加测试的 mock 仓库，记录 `loadHistorySummaries` 的调用历史。
class FakeHistoryRepository implements ChatConversationRepository {
  FakeHistoryRepository({required this.pages});

  /// 按调用顺序返回的页面列表；每个元素是一次 `loadHistorySummaries` 调用的返回值。
  final List<({List<ChatConversationSummary> summaries, bool hasMore})> pages;
  int _callIndex = 0;

  /// 每次 `loadHistorySummaries` 的入参记录，便于断言 offset / limit / keyword。
  List<({String keyword, int? limit, int? offset})> calls = [];

  int get callCount => _callIndex;

  ({List<ChatConversationSummary> summaries, bool hasMore}) _next() {
    // pages 不够时兜底返回空且 hasMore=false，避免越界。
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

void registerHistoryScreenAutoLoadTests() {
  group('history screen auto-fill pagination', () {
    testWidgets('视屏不满时自动追加加载直至填满或 hasMore=false', (tester) async {
      // 第一页仅 1 条（必然不满任何合理视口），hasMore=true；
      // 第二页 0 条 + hasMore=false 终止循环。
      final singleConversation = ChatConversationSummary(
        id: 'c0',
        title: '单条对话',
        firstUserMessagePreview: '用户消息',
        latestUserMessagePreview: '最新用户消息',
        updatedAt: DateTime(2026, 6, 1),
      );

      final fakeRepo = FakeHistoryRepository(
        pages: [
          // pages[0] 被 ChatSessionsController.build() 的无参调用消耗。
          (summaries: const [], hasMore: false),
          // pages[1] 对应 HistoryPaginationController.loadInitial。
          (summaries: [singleConversation], hasMore: true),
          // pages[2] 对应 _autoFillIfNeeded 触发的 loadMore。
          (summaries: const [], hasMore: false),
        ],
      );

      final database = AppDatabase.inMemory();
      addTearDown(database.close);

      final preferences = await TestFixtures.seedPreferences(database: database);

      await pumpTestApp(
        tester,
        child: const HistoryScreen(),
        preferences: preferences,
        database: database,
        viewportSize: const Size(800, 600),
        extraOverrides: [
          chatConversationRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );

      // 等待所有 post-frame 回调与重建完成。
      await tester.pumpAndSettle();

      // 取出带 limit 的分页调用（过滤掉 ChatSessionsController 的无参调用）。
      final pageCalls = fakeRepo.calls.where((c) => c.limit != null).toList();

      // 至少两次分页调用：loadInitial + 至少一次 loadMore。
      expect(pageCalls.length, greaterThanOrEqualTo(2));

      // 第一次分页调用是 loadInitial（limit=50, offset=0）。
      expect(pageCalls[0].limit, 50);
      expect(pageCalls[0].offset, 0);

      // 接下来是 loadMore（limit=30）。
      expect(pageCalls[1].limit, 30);

      // 全部加载完后 spinner 应该消失（最后一页 hasMore=false 已写入状态）。
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('数据足以填满一屏时不自动追加，仅靠滚动触发', (tester) async {
      // 数百条数据足够让 maxScrollExtent > viewportDimension，
      // _autoFillIfNeeded 不应触发追加。
      final hugePage = List.generate(
        500,
        (i) => ChatConversationSummary(
          id: 'c$i',
          title: '大页对话 $i',
          firstUserMessagePreview: '用户消息 $i',
          latestUserMessagePreview: '最新用户消息 $i',
          updatedAt: DateTime(2026, 6, 1).add(Duration(minutes: i)),
        ),
      );

      final fakeRepo = FakeHistoryRepository(
        pages: [
          // ChatSessionsController.build() 的无参调用。
          (summaries: const [], hasMore: false),
          // loadInitial。
          (summaries: hugePage, hasMore: true),
        ],
      );

      final database = AppDatabase.inMemory();
      addTearDown(database.close);

      final preferences = await TestFixtures.seedPreferences(database: database);

      await pumpTestApp(
        tester,
        child: const HistoryScreen(),
        preferences: preferences,
        database: database,
        viewportSize: const Size(800, 600),
        extraOverrides: [
          chatConversationRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );

      // 不能用 pumpAndSettle：满屏 hasMore=true 时 spinner 会一直转，
      // 导致无限动画无法 settle。就用 pump 足够多的帧让 post-frame
      // 回调有机会执行。
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // 仅 ChatSessionsController 的无参调用 + loadInitial 一次，无 loadMore。
      expect(fakeRepo.callCount, 2);
      final pageCalls =
          fakeRepo.calls.where((c) => c.limit != null).toList();
      expect(pageCalls.length, 1);
      expect(pageCalls[0].limit, 50);
      expect(pageCalls[0].offset, 0);
    });
  });
}
