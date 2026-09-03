import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

import '../../features/favorites/favorites_screen_test_helpers.dart';
import '../../features/history/history_screen/history_screen_test_helpers.dart';
import '../../features/media/helpers/fake_video_player_platform_bindings.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_harness.dart';
import '../../helpers/async/widget_test_animation.dart';

Future<SharedPreferences> _testPrefs(AppDatabase db) async {
  return createEmptyPreferences(db);
}

/// 测试用的 Mobile bindings factory：显式注入 Fake，禁止依赖宿主 Windows 平台。
VideoPlayerPlatformBindings _mobileTestBindings() =>
    MobileVideoPlayerBindings(systemUi: FakeMobileVideoSystemUiController());

void main() {
  testWidgets('路由重建后同一收藏详情 URL 仍可恢复内容', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-rebuild',
      userMessageContent: '重建后的用户消息',
      assistantContent: '重建后的助手回复',
      assistantModelDisplayName: 'DeepSeek V4 Flash',
    );
    final prefs = await _testPrefs(db);

    final scope1 = await pumpTestAppScope(
      tester,
      preferences: prefs,
      database: db,
      router: createAppRouter(
        initialLocation: '/favorites/fav-rebuild',
        videoPlayerBindingsFactory: _mobileTestBindings,
      ),
    );
    await tester.pumpWidget(scope1);
    await tester.pump();
    expect(find.text('重建后的用户消息'), findsOneWidget);

    // 卸载旧树（ProviderScope 随树卸载销毁其 container），
    // 证明重建不依赖任何内存对象。
    await tester.pumpWidget(const SizedBox.shrink());

    final scope2 = await pumpTestAppScope(
      tester,
      preferences: prefs,
      database: db,
      router: createAppRouter(
        initialLocation: '/favorites/fav-rebuild',
        videoPlayerBindingsFactory: _mobileTestBindings,
      ),
    );
    await tester.pumpWidget(scope2);
    await tester.pump();

    expect(find.text('重建后的用户消息'), findsOneWidget);
    expect(find.text('重建后的助手回复'), findsOneWidget);
    expect(find.text('DeepSeek V4 Flash'), findsOneWidget);
  });

  testWidgets('已删除收藏的旧 URL 显示收藏不存在', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-deleted',
      userMessageContent: '将被删除的问题',
      assistantContent: '将被删除的回复',
    );
    final prefs = await _testPrefs(db);
    // 通过 repository API 删除，模拟记录已被移除。
    SqliteFavoritesRepository(db).deleteMany({'fav-deleted'});

    final router = createAppRouter(
      initialLocation: '/favorites/fav-deleted',
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('收藏不存在'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧收藏详情 URL 自动重定向到新路由并显示内容', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-legacy',
      userMessageContent: '旧链接的问题',
      assistantContent: '旧链接的回复',
    );
    final prefs = await _testPrefs(db);

    final router = createAppRouter(
      initialLocation: '/favorites/fav-legacy',
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites/items/fav-legacy',
    );
    expect(find.text('旧链接的问题'), findsOneWidget);
  });

  testWidgets('收藏夹深链命中目标路由而不落错误页', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedCollection(db, id: 'col-deep', name: '深链收藏夹');
    final prefs = await _testPrefs(db);

    final router = createAppRouter(
      initialLocation: '/favorites/collections/col-deep?page=2&pageSize=10',
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites/collections/col-deep',
    );
    expect(
      router.routerDelegate.state.uri.queryParameters[AppRouteParameter.page],
      '2',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片媒体命名路由保留路径参数且可返回同步页', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    final router = createAppRouter(
      initialLocation: AppDestination.sync.path,
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    router.pushNamed(
      AppRouteName.mediaImage,
      queryParameters: {AppRouteParameter.mediaPath: '/相册/猫.jpg'},
    );
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync/media/image',
    );
    expect(
      router.routerDelegate.state.uri.queryParameters[AppRouteParameter
          .mediaPath],
      '/相册/猫.jpg',
    );
    // 未 seed 会话 → 恢复页而非抛异常
    expect(find.text('媒体会话已失效'), findsOneWidget);

    router.pop();
    await settleRouteTransition(tester);
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
  });

  testWidgets('媒体路由缺少路径参数时显示恢复页且不抛异常', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    final router = createAppRouter(
      initialLocation: '/sync/media/image',
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('媒体链接无效'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('聊天会话深链在首帧后选中目标会话', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await TestFixtures.seedPreferences(
      database: db,
      conversations: [
        TestFixtures.conversation('conv-a', '会话 A', DateTime(2026, 1, 2)),
        TestFixtures.conversation('conv-b', '会话 B', DateTime(2026, 1, 3)),
      ],
    );

    final router = createAppRouter(
      initialLocation: '/chat?conversationId=conv-a',
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(container.read(chatSessionsProvider).activeConversationId, 'conv-a');
    // AppBar 标题；侧栏历史同样可能列出该条目，故用 findsWidgets。
    expect(find.text('会话 A'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('历史页路由参数', () {
    HistoryBrowseRouteQuery parse(Map<String, String> params) =>
        HistoryBrowseRouteQuery.fromQueryParameters(params);

    test('解析默认值、非法整数并完成有效参数往返', () {
      final defaults = parse(const {});
      expect(defaults.page, isNull);
      expect(defaults.pageSize, isNull);
      expect(defaults.keyword, isEmpty);

      final malformed = parse(const {'page': 'abc', 'pageSize': '1.5'});
      expect(malformed.page, isNull);
      expect(malformed.pageSize, isNull);

      const original = HistoryBrowseRouteQuery(
        page: 3,
        pageSize: 50,
        keyword: '关键词',
      );
      final restored = parse(
        original.toQueryParameters(resolvedPage: 3, resolvedPageSize: 50),
      );

      expect(restored.page, 3);
      expect(restored.pageSize, 50);
      expect(restored.keyword, '关键词');
    });

    testWidgets('中文关键词深链恢复搜索结果且不抛异常', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final prefs = await createSeededPreferences(db);

      final router = createAppRouter(
        initialLocation: '/history?q=${Uri.encodeQueryComponent('重构')}',
        videoPlayerBindingsFactory: _mobileTestBindings,
      );
      await pumpTestApp(
        tester,
        preferences: prefs,
        database: db,
        router: router,
      );

      expect(find.text('Rust 重构计划'), findsOneWidget);
      expect(find.text('Flutter 路线图'), findsNothing);
      expect(router.routerDelegate.state.uri.queryParameters['q'], '重构');
      expect(tester.takeException(), isNull);
    });
  });
}
