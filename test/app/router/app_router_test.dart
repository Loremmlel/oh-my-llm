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
  testWidgets('fresh router rebuild 后同一 URL 仍恢复详情', (tester) async {
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

  testWidgets('invalid ID 显示收藏链接无效并可返回列表', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    final router = createAppRouter(
      initialLocation: '/favorites/%20',
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('收藏链接无效'), findsOneWidget);

    await tester.tap(find.text('返回收藏列表'));
    await settleRouteTransition(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/favorites');
  });

  testWidgets('deleted 收藏直接打开旧 URL 显示收藏不存在', (tester) async {
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

  testWidgets('旧详情 URL 自动重定向到新的 item 路由并显示内容', (tester) async {
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

  testWidgets('收藏夹与条目静态段不被旧的动态详情参数吞掉', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    for (final location in ['/favorites/collections', '/favorites/items']) {
      final router = createAppRouter(
        initialLocation: location,
        videoPlayerBindingsFactory: _mobileTestBindings,
      );
      await pumpTestApp(
        tester,
        preferences: prefs,
        database: db,
        router: router,
      );

      // 保留前缀回到收藏总览网格，而不是把 "collections"/"items"
      // 当作收藏 ID 拼成畸形详情 URL。
      expect(
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
        AppDestination.favorites.path,
        reason: 'location=$location',
      );
      expect(find.text('未分类'), findsOneWidget, reason: 'location=$location');
    }
  });

  testWidgets('collection 深链命中收藏夹路由而不落错误页', (tester) async {
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

  testWidgets('新 item 路由深链直达详情并可返回收藏总览', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-push',
      userMessageContent: '列表进入的问题',
      assistantContent: '列表进入的回复',
    );
    final prefs = await _testPrefs(db);

    final router = createAppRouter(
      initialLocation: '${AppDestination.favorites.path}/items/fav-push',
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites/items/fav-push',
    );
    expect(find.text('列表进入的回复'), findsOneWidget);

    // AppBar 自动 leading 是 BackButton（tooltip 随 locale 变化，用类型 finder）。
    await tester.tap(find.byType(BackButton));
    await settleRouteTransition(tester);

    expect(router.routerDelegate.currentConfiguration.uri.path, '/favorites');
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites',
    );
    // 返回的是收藏总览网格，系统未分类卡片可见。
    expect(find.text('未分类'), findsOneWidget);
  });

  testWidgets('从收藏总览点击收藏夹卡片进入对应收藏夹路由', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-in-sys',
      userMessageContent: '系统夹的问题',
      assistantContent: '系统夹的回复',
    );
    seedCollection(db, id: 'col-grid', name: '网格收藏夹');
    final prefs = await _testPrefs(db);

    final router = createAppRouter(
      initialLocation: AppDestination.favorites.path,
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    await tester.tap(find.text('未分类'));
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites/collections/__uncategorized_favorites__',
    );
    expect(find.text('未找到页面'), findsNothing);
  });

  testWidgets('pushNamed(mediaImage) 后 URI 携带 path，pop 回 /sync', (
    tester,
  ) async {
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

  testWidgets('pushNamed(mediaVideo) 同理', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    final router = createAppRouter(
      initialLocation: AppDestination.sync.path,
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    router.pushNamed(
      AppRouteName.mediaVideo,
      queryParameters: {AppRouteParameter.mediaPath: '/视频/demo.mp4'},
    );
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync/media/video',
    );
    expect(find.text('媒体会话已失效'), findsOneWidget);
  });

  testWidgets('media route 缺 query 仍匹配并显示恢复页，不抛异常', (tester) async {
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

  testWidgets('initial /chat?conversationId=<existing> 在 post-frame 后选中目标会话', (
    tester,
  ) async {
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

  testWidgets('仅改变 query 到第二个已有会话 ID 时经 didUpdateWidget 生效', (tester) async {
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

    router.go('/chat?conversationId=conv-b');
    await settleRouteTransition(tester);
    await tester.pump();

    expect(container.read(chatSessionsProvider).activeConversationId, 'conv-b');
    expect(find.text('会话 B'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空白/已删除 ID 打开默认会话且无错误提示', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await TestFixtures.seedPreferences(
      database: db,
      conversations: [
        TestFixtures.conversation('conv-default', '默认会话', DateTime(2026, 1, 3)),
      ],
    );
    for (final location in [
      '/chat?conversationId=%20',
      '/chat?conversationId=deleted-id',
    ]) {
      final router = createAppRouter(
        initialLocation: location,
        videoPlayerBindingsFactory: _mobileTestBindings,
      );
      await pumpTestApp(
        tester,
        preferences: prefs,
        database: db,
        router: router,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      expect(
        container.read(chatSessionsProvider).activeConversationId,
        'conv-default',
      );
      expect(container.read(chatSessionsProvider).errorMessage, isNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('route URI 携带编码 Unicode/特殊字符 ID 时选中对应会话（state.extra 不参与）', (
    tester,
  ) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    const specialId = '会话/猫 #1';
    final prefs = await TestFixtures.seedPreferences(
      database: db,
      conversations: [
        TestFixtures.conversation(specialId, '特殊会话', DateTime(2026, 1, 3)),
      ],
    );
    final encoded = Uri.encodeQueryComponent(specialId);
    final router = createAppRouter(
      initialLocation: '/chat?conversationId=$encoded',
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    // 导航契约只依赖 query：URI 解码回原始 ID，不依赖 state.extra。
    expect(
      router.routerDelegate.state.uri.queryParameters[AppRouteParameter
          .conversationId],
      specialId,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(
      container.read(chatSessionsProvider).activeConversationId,
      specialId,
    );
    expect(find.text('特殊会话'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('History route query', () {
    HistoryBrowseRouteQuery parse(Map<String, String> params) =>
        HistoryBrowseRouteQuery.fromQueryParameters(params);

    test('无参数时页码与容量为空、关键词为空串', () {
      final query = parse(const {});

      expect(query.page, isNull);
      expect(query.pageSize, isNull);
      expect(query.keyword, isEmpty);
    });

    test('非法整数解析为空交由运行时回退', () {
      final query = parse(const {'page': 'abc', 'pageSize': '1.5'});

      expect(query.page, isNull);
      expect(query.pageSize, isNull);
    });

    test('负数页码保留数值交由运行时夹取', () {
      final query = parse(const {'page': '-5'});

      expect(query.page, -5);
    });

    test('query 参数经 round-trip 后窗口一致', () {
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

    test('空关键词在序列化时省略 q 参数', () {
      const query = HistoryBrowseRouteQuery(page: 2, pageSize: 20);

      expect(
        query
            .toQueryParameters(resolvedPage: 2, resolvedPageSize: 20)
            .containsKey('q'),
        isFalse,
      );
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

    testWidgets('page 与 pageSize 深链直接恢复目标窗口', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final prefs = await createBulkSeededPreferences(db, count: 25);

      final router = createAppRouter(
        initialLocation: '/history?page=2&pageSize=10',
        videoPlayerBindingsFactory: _mobileTestBindings,
      );
      await pumpTestApp(
        tester,
        preferences: prefs,
        database: db,
        router: router,
      );

      // 每页 10 条时第 2 页为第 11-20 条（排序按更新时间倒序）；
      // 列表虚拟化只渲染可视区，断言页首附近的条目即可锁定窗口位置。
      expect(find.text('批量会话 10'), findsOneWidget);
      expect(find.text('批量会话 12'), findsOneWidget);
      expect(find.text('批量会话 9'), findsNothing);
      expect(find.textContaining('共 25 条 · 2/3 页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
