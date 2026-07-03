import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/history_pagination_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';
import 'package:oh_my_llm/features/history/presentation/widgets/history_pagination_bar.dart';

import '../../../helpers/fake_history_repository.dart';
import '../../../helpers/test_harness.dart';

/// 构造 N 条测试会话摘要。
List<ChatConversationSummary> _summaries(int count) => List.generate(
  count,
  (i) => ChatConversationSummary(
    id: 'c$i',
    title: '对话 $i',
    updatedAt: DateTime(2026, 6, 1).add(Duration(minutes: i)),
  ),
);

/// 挂载 HistoryScreen 并注入 FakeHistoryRepository。
///
/// `pages` 列表的每一项按调用顺序提供给 fake：
/// - 第 0 项被 ChatSessionsController.build() 的无参调用消耗（供侧栏使用）；
/// - 第 1 项起被 HistoryPaginationController 的带 limit 调用按顺序消耗。
Future<void> _pumpHistoryScreen(
  WidgetTester tester,
  FakeHistoryRepository repo,
) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final database = AppDatabase.inMemory();
  addTearDown(database.close);

  await pumpTestApp(
    tester,
    child: const HistoryScreen(),
    preferences: preferences,
    database: database,
    viewportSize: const Size(1440, 1200),
    extraOverrides: [
      chatConversationRepositoryProvider.overrideWithValue(repo),
    ],
  );
  // pumpTestApp 已执行一次 pump(), 驱动的 HistoryScreen.initState 中的
  // addPostFrameCallback 执行 → loadInitial。再 pump() 使更新后的
  // 状态触发重建，让 UI 与 state 同步。
  await tester.pump();
}

void registerHistoryScreenPaginationBarTests() {
  group('HistoryPaginationBar', () {
    testWidgets('renders pagination bar between toolbar and list', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          // ChatSessionsController.build() 无参调用
          const [],
          // loadInitial 调用
          _summaries(20),
        ],
        countResult: 100,
      );
      await _pumpHistoryScreen(tester, repo);

      expect(find.byType(HistoryPaginationBar), findsOneWidget);
      expect(find.text('共 100 条 · 第 1/5 页'), findsOneWidget);
      // 当前页码 1 应以高亮形式显示（FilledButton）
      expect(find.widgetWithText(FilledButton, '1'), findsOneWidget);
    });

    testWidgets('clicking next page button loads page 2', (tester) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [], // 侧栏无参调用
          _summaries(20), // page 1 (loadInitial)
          _summaries(20), // page 2 (next)
        ],
        countResult: 100,
      );
      await _pumpHistoryScreen(tester, repo);

      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HistoryPaginationBar)),
      );
      expect(container.read(historyPaginationProvider).currentPage, 2);
    });

    testWidgets('clicking page number navigates to that page', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [], // 侧栏
          _summaries(20), // page 1
          _summaries(20), // page 2
          _summaries(20), // page 3
        ],
        countResult: 60,
      );
      await _pumpHistoryScreen(tester, repo);

      // 点击页码 3
      await tester.tap(find.widgetWithText(OutlinedButton, '3'));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HistoryPaginationBar)),
      );
      expect(container.read(historyPaginationProvider).currentPage, 3);
    });

    testWidgets('page 1 hides previous button / last page hides next', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [], // 侧栏
          _summaries(20), // page 1
          _summaries(20), // page 2
        ],
        countResult: 40,
      );
      await _pumpHistoryScreen(tester, repo);

      // 第 1 页：上一页 disabled
      final prevButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('上一页'),
          matching: find.byType(IconButton),
        ),
      );
      expect(prevButton.onPressed, isNull);

      // 跳到第 2 页
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();

      final nextButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('下一页'),
          matching: find.byType(IconButton),
        ),
      );
      expect(nextButton.onPressed, isNull);
    });

    testWidgets('page number sequence folds with ellipsis for many pages', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [], // 侧栏
          _summaries(20), // page 1
          _summaries(20), // page 2
          _summaries(20), // page 3
          _summaries(20), // page 4
          _summaries(20), // page 5
          _summaries(20), // page 6
          _summaries(20), // page 7
        ],
        countResult: 160,
      );
      await _pumpHistoryScreen(tester, repo);

      // 第 1 页：应显示 1 2 … 6 7（省略号折叠中间）
      expect(find.widgetWithText(FilledButton, '1'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '2'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '7'), findsOneWidget);
      // 省略号
      expect(find.text('…'), findsWidgets);
    });

    testWidgets('changing page size reloads with new size and resets to page 1',
        (tester) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [], // 侧栏
          _summaries(20), // page 1 (size=20)
          _summaries(20), // page 2 (size=20)
          _summaries(10), // page 1 (size=10)
        ],
        countResult: 50,
      );
      await _pumpHistoryScreen(tester, repo);

      // 跳到第 2 页
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();
      var container = ProviderScope.containerOf(
        tester.element(find.byType(HistoryPaginationBar)),
      );
      expect(container.read(historyPaginationProvider).currentPage, 2);

      // 切换每页条数为 10
      await tester.tap(
        find.byKey(const Key('pagination-page-size-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').last);
      await tester.pumpAndSettle();

      container = ProviderScope.containerOf(
        tester.element(find.byType(HistoryPaginationBar)),
      );
      final s = container.read(historyPaginationProvider);
      expect(s.pageSize, 10);
      expect(s.currentPage, 1);
      expect(s.totalPages, 5); // ceil(50/10)
    });

    testWidgets('jump to page clamps out-of-range input', (tester) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [], // 侧栏
          _summaries(20), // page 1
          _summaries(20), // page 2
          _summaries(10), // page 3
        ],
        countResult: 50,
      );
      await _pumpHistoryScreen(tester, repo);

      // 输入越界页码 999
      await tester.enterText(
        find.byKey(const Key('pagination-jump-input')),
        '999',
      );
      await tester.tap(find.widgetWithText(TextButton, '跳转'));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HistoryPaginationBar)),
      );
      expect(container.read(historyPaginationProvider).currentPage, 3); // 夹取到 last
    });

    testWidgets('jump to page triggers fetch with correct offset', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [], // 侧栏
          _summaries(20), // page 1
          _summaries(20), // page 2
          _summaries(20), // page 3
        ],
        countResult: 60,
      );
      await _pumpHistoryScreen(tester, repo);

      await tester.enterText(
        find.byKey(const Key('pagination-jump-input')),
        '3',
      );
      await tester.tap(find.widgetWithText(TextButton, '跳转'));
      await tester.pump();

      final paged = repo.pagedCalls;
      // 最后一次带 limit 的调用 offset 应为 (3-1)*20 = 40
      expect(paged.last.offset, 40);
    });

    testWidgets('current page button is visually distinguished (FilledButton)',
        (tester) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [], // 侧栏
          _summaries(20), // page 1
          _summaries(20), // page 2
        ],
        countResult: 40,
      );
      await _pumpHistoryScreen(tester, repo);

      // 第 1 页：页码 1 用 FilledButton，页码 2 用 OutlinedButton
      expect(find.widgetWithText(FilledButton, '1'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '2'), findsOneWidget);

      // 跳到第 2 页
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();

      expect(find.widgetWithText(FilledButton, '2'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '1'), findsOneWidget);
    });

    testWidgets('disabled prev/next at boundaries do not trigger load', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [], // 侧栏
          _summaries(20), // page 1
        ],
        countResult: 20,
      );
      await _pumpHistoryScreen(tester, repo);

      final pagedBefore = repo.pagedCalls.length;

      // 点击 disabled 的下一页
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();

      expect(repo.pagedCalls.length, pagedBefore); // 没有新调用
      expect(
        ProviderScope.containerOf(
          tester.element(find.byType(HistoryPaginationBar)),
        ).read(historyPaginationProvider).currentPage,
        1,
      );
    });
  });
}
