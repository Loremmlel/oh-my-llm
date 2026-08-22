import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/history/history_pagination_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/history_page_query.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';

import '../../../helpers/async/widget_test_animation.dart';
import 'history_screen_test_helpers.dart';

ChatConversationSummary summary(String id, String title) =>
    ChatConversationSummary(
      id: id,
      title: title,
      firstUserMessagePreview: '$id 的首条用户消息',
      latestUserMessagePreview: '$id 的最新用户消息',
      updatedAt: DateTime(2026, 6, 1),
    );

/// 完成第 [index] 次查询并结算到稳定帧（commit + 可能的 route replace）。
Future<void> _completeAndSettle(
  WidgetTester tester,
  HistoryScreenQueryEnv env,
  int index, {
  List<ChatConversationSummary> items = const [],
  required int totalItems,
  int committedPage = 1,
}) async {
  env.query.completeSuccess(
    index,
    items: items,
    totalItems: totalItems,
    committedPage: committedPage,
  );
  await tester.pump();
  await tester.pump();
}

void registerHistoryScreenAsyncQueryTests() {
  testWidgets('查询未完成时 loading 动画可 pump 且搜索输入仍可编辑', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);

    expect(env.query.pendingCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final searchField = find.byType(TextField).first;
    expect(tester.widget<TextField>(searchField).enabled ?? true, isTrue);
    await tester.enterText(searchField, '关键词');
    await tester.pump();
    expect(tester.widget<TextField>(searchField).controller!.text, '关键词');
  });

  testWidgets('搜索成功前 URL 保持旧值，成功后才 replace', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [summary('a', 'Rust 重构计划'), summary('b', 'Flutter 路线图')],
      totalItems: 2,
    );
    expect(env.router.routerDelegate.state.uri.queryParameters['q'], isNull);

    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    // 搜索在途：URL 与列表都保持旧窗口。
    expect(env.query.pendingCount, 1);
    expect(env.router.routerDelegate.state.uri.queryParameters['q'], isNull);
    expect(find.text('Flutter 路线图'), findsOneWidget);

    await _completeAndSettle(
      tester,
      env,
      1,
      items: [summary('a', 'Rust 重构计划')],
      totalItems: 1,
    );

    expect(env.router.routerDelegate.state.uri.queryParameters['q'], 'Rust');
    expect(find.text('Flutter 路线图'), findsNothing);
  });

  testWidgets('搜索失败保留旧 URL 和旧列表并显示加载失败', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [summary('a', 'Rust 重构计划'), summary('b', 'Flutter 路线图')],
      totalItems: 2,
    );

    await tester.enterText(find.byType(TextField).first, '不存在的关键词');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    env.query.completeFailure(1);
    await tester.pump();
    await tester.pump();

    expect(env.router.routerDelegate.state.uri.queryParameters['q'], isNull);
    expect(find.text('Rust 重构计划'), findsOneWidget);
    expect(find.text('Flutter 路线图'), findsOneWidget);
    expect(find.text(historyLoadErrorMessage), findsOneWidget);
    expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);
  });

  testWidgets('失败后点击重试会重新提交失败目标，成功后才更新 URL', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [summary('a', '种子')],
      totalItems: 1,
    );

    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();
    env.query.completeFailure(1);
    await tester.pump();
    expect(find.text(historyLoadErrorMessage), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '重试'));
    await tester.pump();

    // 重试重新提交失败目标，URL 仍保持旧窗口。
    expect(env.query.requests.last.keyword, 'Rust');
    expect(env.query.pendingCount, 1);
    expect(env.router.routerDelegate.state.uri.queryParameters['q'], isNull);

    await _completeAndSettle(
      tester,
      env,
      2,
      items: [summary('a', 'Rust 重构计划')],
      totalItems: 1,
    );

    expect(env.router.routerDelegate.state.uri.queryParameters['q'], 'Rust');
    expect(find.text(historyLoadErrorMessage), findsNothing);
  });

  testWidgets('外部 deep link 查询失败时 URL 回滚到查询前 committed 窗口', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [summary('a', 'Rust 重构计划')],
      totalItems: 1,
    );

    env.router.go('/history?q=外部关键词');
    await tester.pump();
    await tester.pump();
    expect(env.query.pendingCount, 1);

    env.query.completeFailure(1);
    await tester.pump();
    await tester.pump();

    final uri = env.router.routerDelegate.state.uri;
    expect(uri.queryParameters['q'], isNull);
    expect(uri.queryParameters['page'], '1');
    expect(find.text('Rust 重构计划'), findsOneWidget);
  });

  testWidgets('外部越界页成功夹取后 URL canonicalize 为 committed page', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [summary('a', '第一页')],
      totalItems: 45,
    );

    env.router.go('/history?page=99&pageSize=20');
    await tester.pump();
    await tester.pump();
    expect(env.query.requests.last.requestedPage, 99);

    await _completeAndSettle(
      tester,
      env,
      1,
      items: [summary('z', '第三页')],
      totalItems: 45,
      committedPage: 3,
    );

    expect(env.router.routerDelegate.state.uri.queryParameters['page'], '3');
    expect(find.textContaining('/3 页'), findsOneWidget);
  });

  testWidgets('在途非空搜索后立即清空时非空结果不能回写 URL 或列表', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [summary('a', 'Rust 重构计划'), summary('b', 'Flutter 路线图')],
      totalItems: 2,
    );

    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();
    expect(env.query.pendingCount, 1);

    // 搜索在途时点击清空：清空目标收编为 latest pending，等 A 结束后派发。
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();

    // 在途搜索的旧结果迟到：不写 URL、不缩列表。
    await _completeAndSettle(
      tester,
      env,
      1,
      items: [summary('a', 'Rust 重构计划')],
      totalItems: 1,
    );
    expect(env.router.routerDelegate.state.uri.queryParameters['q'], isNull);
    expect(find.text('Flutter 路线图'), findsOneWidget);

    // A 结束后清空目标立即派发进入查询。
    expect(env.query.requests.last.keyword, '');
    await _completeAndSettle(
      tester,
      env,
      2,
      items: [summary('a', 'Rust 重构计划'), summary('b', 'Flutter 路线图')],
      totalItems: 2,
    );
    expect(find.text('Rust 重构计划'), findsOneWidget);
  });

  testWidgets('A 在途、B pending、C latest 时只有 C 最终更新可见窗口和 URL', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [summary('a', 'Rust 重构计划')],
      totalItems: 1,
    );

    // A：搜索 Rust 进入在途。
    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();
    // B→C：连续输入使 C 成为 latest pending（B 未进入查询）。
    await tester.enterText(find.byType(TextField).first, 'Flutter');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.enterText(find.byType(TextField).first, '复盘');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    // A 的结果被 C 超越：不写状态。
    await _completeAndSettle(
      tester,
      env,
      1,
      items: [summary('a', 'Rust 命中')],
      totalItems: 1,
    );
    expect(find.text('Rust 重构计划'), findsOneWidget);
    expect(env.router.routerDelegate.state.uri.queryParameters['q'], isNull);

    // C 完成后才更新窗口与 URL。
    await _completeAndSettle(
      tester,
      env,
      2,
      items: [summary('c', '复盘命中')],
      totalItems: 1,
    );

    expect(env.router.routerDelegate.state.uri.queryParameters['q'], '复盘');
    expect(find.text('复盘命中'), findsOneWidget);
    expect(find.text('Rust 重构计划'), findsNothing);
  });

  testWidgets('页面 dispose 后迟到结果无 zone error、无 route mutation', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    expect(env.query.pendingCount, 1);

    env.router.go('/chat');
    await settleRouteTransition(tester);
    expect(find.text('聊天落点'), findsOneWidget);

    // History 页已卸载：迟到的初始结果提交进 controller，不触碰路由。
    env.query.completeSuccess(
      0,
      items: [summary('a', 'Rust 重构计划')],
      totalItems: 1,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('聊天落点'), findsOneWidget);
    expect(env.router.routerDelegate.state.uri.path, '/chat');
  });

  testWidgets('搜索态 rename 后等待刷新，退出匹配的条目按查询结果消失', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [
        summary('conversation-1', 'Rust 重构计划'),
        summary('conversation-2', 'Flutter 路线图'),
      ],
      totalItems: 2,
    );

    // 搜索态：只命中标题包含 Rust 的会话。
    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();
    await _completeAndSettle(
      tester,
      env,
      1,
      items: [
        summary('conversation-1', 'Rust 重构计划'),
        summary('conversation-2', 'Flutter 路线图'),
      ],
      totalItems: 2,
    );

    // 重命名首行为不再匹配的标题。
    await tester.tap(find.byTooltip('更多操作').first);
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '重命名').last);
    await settleOverlayTransition(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '不匹配的新标题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await settleOverlayTransition(tester);

    // rename 触发的重查在途：列表暂不变化。
    expect(env.query.pendingCount, 1);
    expect(find.text('Rust 重构计划'), findsOneWidget);

    await _completeAndSettle(
      tester,
      env,
      2,
      items: [summary('conversation-2', 'Flutter 路线图')],
      totalItems: 1,
    );

    expect(find.text('Rust 重构计划'), findsNothing);
    expect(find.text('Flutter 路线图'), findsOneWidget);
  });

  testWidgets('delete 后刷新不会被删除前在途查询复活', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [
        summary('conversation-1', 'Rust 重构计划'),
        summary('conversation-2', 'Flutter 路线图'),
        summary('conversation-3', '项目复盘'),
      ],
      totalItems: 3,
    );

    // 删除前先制造一个在途查询（进入搜索防抖窗口）。
    await tester.enterText(find.byType(TextField).first, '路');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();
    expect(env.query.pendingCount, 1);

    // 删除 conversation-1（真实落库）。
    await tester.longPress(find.text('Rust 重构计划'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    await settleOverlayTransition(tester);

    // 删除前发起的在途查询返回了仍含被删会话的两条数据：被 delete 目标
    // 超越后不得落地——「项目复盘」仍在列表即为未被旧窗口覆盖的证明。
    env.query.completeSuccess(
      1,
      items: [
        summary('conversation-1', 'Rust 重构计划'),
        summary('conversation-2', 'Flutter 路线图'),
      ],
      totalItems: 2,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('项目复盘'), findsOneWidget, reason: '旧查询结果不得覆盖 committed 窗口');
    expect(
      find.text('Rust 重构计划'),
      findsOneWidget,
      reason: '删除目标完成前列表保持 stale 内容',
    );

    // delete 触发的重查在 A 结束后派发，完成后被删会话消失。
    expect(env.query.requests.last.keyword, '路');
    await _completeAndSettle(
      tester,
      env,
      2,
      items: [
        summary('conversation-2', 'Flutter 路线图'),
        summary('conversation-3', '项目复盘'),
      ],
      totalItems: 2,
    );
    expect(find.text('Rust 重构计划'), findsNothing);
    expect(find.text('Flutter 路线图'), findsOneWidget);
    expect(find.text('项目复盘'), findsOneWidget);
  });

  testWidgets('busy 时分页操作被忽略，搜索输入仍可用', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [summary('a', '第一页')],
      totalItems: 45,
    );

    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();
    final requestsWhileBusy = env.query.requests.length;

    // 翻页在途：再次点击翻页被 busy 守卫忽略，不产生新请求。
    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();
    expect(env.query.requests, hasLength(requestsWhileBusy));

    // 搜索输入不受 busy 影响，可继续编辑。
    final searchField = find.byType(TextField).first;
    expect(tester.widget<TextField>(searchField).enabled ?? true, isTrue);
    await tester.enterText(searchField, '关键词');
    await tester.pump();

    await _completeAndSettle(
      tester,
      env,
      1,
      items: [summary('b', '第二页')],
      totalItems: 45,
      committedPage: 2,
    );

    // busy 结束后翻页恢复可用。
    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();
    expect(env.query.requests.last.requestedPage, 3);
  });

  testWidgets('深链 q/page/pageSize 在异步完成信号后恢复', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);
    await _completeAndSettle(
      tester,
      env,
      0,
      items: [summary('a', '种子')],
      totalItems: 1,
    );

    env.router.go('/history?q=Rust&page=2&pageSize=10');
    await tester.pump();
    await tester.pump();

    expect(
      env.query.requests.last,
      isA<HistoryPageRequest>()
          .having((r) => r.keyword, 'keyword', 'Rust')
          .having((r) => r.requestedPage, 'requestedPage', 2)
          .having((r) => r.pageSize, 'pageSize', 10),
    );

    await _completeAndSettle(
      tester,
      env,
      1,
      items: [summary('a', 'Rust 第二页')],
      totalItems: 15,
      committedPage: 2,
    );

    final uri = env.router.routerDelegate.state.uri;
    expect(uri.queryParameters['q'], 'Rust');
    expect(uri.queryParameters['page'], '2');
    expect(uri.queryParameters['pageSize'], '10');
    expect(find.text('Rust 第二页'), findsOneWidget);
  });
}
