import 'package:flutter/material.dart';
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

/// 完成第 [index] 次查询为失败并结算到稳定帧（失败态 + route 回滚）。
Future<void> _completeFailureAndSettle(
  WidgetTester tester,
  HistoryScreenQueryEnv env,
  int index,
) async {
  env.query.completeFailure(index);
  await tester.pump();
  await tester.pump();
}

/// 搜索框 finder：按 hintText 锚定；rename 对话框打开出现第二个
/// TextField 时仍指向搜索框，不依赖 widget 顺序。
Finder _searchField() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == '搜索历史对话',
);

void registerHistoryScreenAsyncQueryTests() {
  testWidgets('查询未完成时 loading 动画可 pump 且搜索输入仍可编辑', (tester) async {
    final env = await pumpControllableHistoryScreen(tester);

    expect(env.query.pendingCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final searchField = _searchField();
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

    await tester.enterText(_searchField(), 'Rust');
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

    await tester.enterText(_searchField(), '不存在的关键词');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    await _completeFailureAndSettle(tester, env, 1);

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

    await tester.enterText(_searchField(), 'Rust');
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

    await _completeFailureAndSettle(tester, env, 1);

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
