import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'history_screen_test_helpers.dart';

void registerHistoryScreenPaginationBarTests() {
  testWidgets('翻页清空选择并显示下一窗口', (tester) async {
    await setUpHistoryScreenWithBulkConversations(tester, count: 25);

    await tester.longPress(find.text('批量会话 0'));
    await tester.pump();
    await tester.longPress(find.text('批量会话 1'));
    await tester.pump();
    expect(find.textContaining('已选择 2 项'), findsOneWidget);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();

    expect(find.textContaining('已选择'), findsNothing);
    expect(find.text('批量会话 20'), findsOneWidget);
    expect(find.text('批量会话 24'), findsOneWidget);
    expect(find.text('批量会话 0'), findsNothing);
  });

  testWidgets('修改每页容量清空选择并回到第 1 页', (tester) async {
    await setUpHistoryScreenWithBulkConversations(tester, count: 25);

    // 跳到第 2 页并选择一项。
    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();
    await tester.longPress(find.text('批量会话 20'));
    await tester.pump();
    expect(find.textContaining('已选择 1 项'), findsOneWidget);

    // 切换容量为 10：回到第 1 页且选择态清空。
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('已选择'), findsNothing);
    expect(find.text('批量会话 0'), findsOneWidget);
    expect(find.textContaining('共 25 条 · 1/3 页'), findsOneWidget);
  });

  testWidgets('外部路由切换页面时清空当前页选择', (tester) async {
    await setUpHistoryScreenWithBulkConversations(tester, count: 25);

    await tester.longPress(find.text('批量会话 0'));
    await tester.pump();
    await tester.longPress(find.text('批量会话 1'));
    await tester.pump();
    expect(find.textContaining('已选择 2 项'), findsOneWidget);

    // 深链直达第 2 页：不经过分页栏回调，等同前进/后退/外部导航改窗口；
    // go_router 对 query-only 变化复用同一页面 State，选择必须被主动清空。
    final router = GoRouter.of(tester.element(find.textContaining('共 25 条')));
    router.go('/history?page=2&pageSize=20');
    // 第一帧结算 didUpdateWidget 的 post-frame 路由应用，第二帧渲染新窗口。
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('已选择'), findsNothing);
    expect(find.text('批量会话 20'), findsOneWidget);
    expect(find.textContaining('共 25 条 · 2/2 页'), findsOneWidget);
  });

  testWidgets('打开会话可返回且返回后恢复页码与滚动位置', (tester) async {
    await setUpHistoryScreenWithBulkConversations(tester, count: 25);

    // 第 1 页滚动到深处，露出靠后的行。
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pump();
    expect(find.text('批量会话 15'), findsOneWidget);

    await tester.tap(find.text('批量会话 15'));
    await tester.pumpAndSettle();
    expect(find.text('聊天落点'), findsOneWidget);
    expect(
      GoRouter.of(tester.element(find.text('聊天落点')))
          .routerDelegate
          .state
          .uri
          .queryParameters['conversationId'],
      'bulk-15',
    );

    // 系统返回 pop 回历史页：页码与滚动都保持。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('聊天落点'), findsNothing);
    expect(find.textContaining('共 25 条 · 1/2 页'), findsOneWidget);
    expect(find.text('批量会话 15'), findsOneWidget);
    expect(find.text('批量会话 0'), findsNothing);
  });
}
