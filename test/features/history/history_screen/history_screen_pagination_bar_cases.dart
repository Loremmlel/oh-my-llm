import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/history_pagination_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/history_pagination_state.dart';
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

/// 读取 provider 当前状态。
HistoryPaginationState _readState(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(HistoryPaginationBar)),
    ).read(historyPaginationProvider);

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
    testWidgets('renders pagination bar with correct state info', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [],
          _summaries(20),
        ],
        countResult: 100,
      );
      await _pumpHistoryScreen(tester, repo);

      expect(find.byType(HistoryPaginationBar), findsOneWidget);
      expect(find.textContaining('100 条'), findsOneWidget);
      expect(find.textContaining('1/5'), findsOneWidget);
      expect(_readState(tester).currentPage, 1);
    });

    testWidgets('clicking next page button loads page 2', (tester) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [],
          _summaries(20), // page 1 (loadInitial)
          _summaries(20), // page 2 (next)
        ],
        countResult: 100,
      );
      await _pumpHistoryScreen(tester, repo);

      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();

      expect(_readState(tester).currentPage, 2);
    });

    testWidgets('clicking page number navigates to that page', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [],
          _summaries(20), // page 1
          _summaries(20), // page 2
          _summaries(20), // page 3
        ],
        countResult: 60,
      );
      await _pumpHistoryScreen(tester, repo);

      // 点击页码 3（非当前页的 OutlinedButton）
      await tester.tap(find.widgetWithText(OutlinedButton, '3'));
      await tester.pump();

      expect(_readState(tester).currentPage, 3);
    });

    testWidgets('prev/next buttons at boundaries do not trigger navigation', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [],
          _summaries(20), // page 1
          _summaries(20), // page 2
        ],
        countResult: 40,
      );
      await _pumpHistoryScreen(tester, repo);

      final pagedBefore = repo.pagedCalls.length;

      // 第 1 页：点击上一页不应触发翻页（边界守卫）
      await tester.tap(find.byTooltip('上一页'));
      await tester.pump();
      expect(_readState(tester).currentPage, 1);
      expect(repo.pagedCalls.length, pagedBefore);

      // 跳到第 2 页（最后一页）
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();
      expect(_readState(tester).currentPage, 2);

      final pagedAfterNext = repo.pagedCalls.length;

      // 第 2 页（最后一页）：点击下一页不应触发翻页
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();
      expect(_readState(tester).currentPage, 2);
      expect(repo.pagedCalls.length, pagedAfterNext);
    });

    testWidgets('page number sequence folds with ellipsis for many pages', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [],
          _summaries(20),
          _summaries(20),
          _summaries(20),
          _summaries(20),
          _summaries(20),
          _summaries(20),
          _summaries(20),
        ],
        countResult: 160,
      );
      await _pumpHistoryScreen(tester, repo);

      // 第 1 页：应显示 1 2 … 8（省略号折叠中间）
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      // 省略号
      expect(find.text('…'), findsWidgets);
      expect(_readState(tester).currentPage, 1);
    });

    testWidgets('changing page size reloads with new size and resets to page 1',
        (tester) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [],
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
      expect(_readState(tester).currentPage, 2);

      // 切换每页条数为 10（通过下拉菜单 label 定位）
      await tester.tap(find.text('每页'), warnIfMissed: false); // 左标签文本会因 button 内边距偏移到 decoration 区域，tap 坐标落在 DropdownButton 装饰层属正常行为
      await tester.pumpAndSettle();
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();

      final s = _readState(tester);
      expect(s.pageSize, 10);
      expect(s.currentPage, 1);
      expect(s.totalPages, 5); // ceil(50/10)
    });

    testWidgets('jump to page clamps out-of-range input', (tester) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [],
          _summaries(20), // page 1
          _summaries(20), // page 2
          _summaries(10), // page 3
        ],
        countResult: 50,
      );
      await _pumpHistoryScreen(tester, repo);

      // 跳转输入框（label 为「页码」的 TextField）
      final jumpInput = find.ancestor(
        of: find.text('页码'),
        matching: find.byType(TextField),
      );
      await tester.enterText(jumpInput, '999');
      await tester.tap(find.widgetWithText(TextButton, '跳转'));
      await tester.pump();

      expect(_readState(tester).currentPage, 3); // 夹取到 last
    });

    testWidgets('jump to page navigates to target', (tester) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [],
          _summaries(20), // page 1
          _summaries(20), // page 2
          _summaries(20), // page 3
        ],
        countResult: 60,
      );
      await _pumpHistoryScreen(tester, repo);

      final jumpInput = find.ancestor(
        of: find.text('页码'),
        matching: find.byType(TextField),
      );
      await tester.enterText(jumpInput, '3');
      await tester.tap(find.widgetWithText(TextButton, '跳转'));
      await tester.pump();

      expect(_readState(tester).currentPage, 3);
    });

    testWidgets('current page is visually distinguished after navigation', (
      tester,
    ) async {
      final repo = FakeHistoryRepository(
        pages: [
          const [],
          _summaries(20), // page 1
          _summaries(20), // page 2
        ],
        countResult: 40,
      );
      await _pumpHistoryScreen(tester, repo);

      // 第 1 页：当前页 1 用 FilledButton，非当前页 2 用 OutlinedButton
      expect(find.widgetWithText(FilledButton, '1'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '2'), findsOneWidget);
      expect(_readState(tester).currentPage, 1);

      // 跳到第 2 页
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();

      expect(_readState(tester).currentPage, 2);
      // 当前页 2 用 FilledButton，非当前页 1 用 OutlinedButton
      expect(find.widgetWithText(FilledButton, '2'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '1'), findsOneWidget);
    });
  });
}
