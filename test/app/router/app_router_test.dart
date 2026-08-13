import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';

import '../../features/favorites/favorites_screen_test_helpers.dart';
import '../../helpers/test_harness.dart';
import '../../helpers/async/widget_test_animation.dart';

Future<SharedPreferences> _testPrefs(AppDatabase db) async {
  return createEmptyPreferences(db);
}

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
      router: createAppRouter(initialLocation: '/favorites/fav-rebuild'),
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
      router: createAppRouter(initialLocation: '/favorites/fav-rebuild'),
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

    final router = createAppRouter(initialLocation: '/favorites/%20');
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
    SqliteFavoritesRepository(db).delete('fav-deleted');

    final router = createAppRouter(initialLocation: '/favorites/fav-deleted');
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('收藏不存在'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从收藏列表点击 item 进入详情，返回回到列表', (tester) async {
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
      initialLocation: AppDestination.favorites.path,
    );
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    await tester.tap(find.text('列表进入的问题'));
    await settleRouteTransition(tester);

    // push 是 imperative 路由，currentConfiguration.uri 只反映非 push 的
    // 顶层匹配，故用最后匹配位置的 matchedLocation 断言进入详情。
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites/fav-push',
    );
    expect(find.text('列表进入的回复'), findsOneWidget);

    // AppBar 自动 leading 是 BackButton（tooltip 随 locale 变化，用类型 finder）。
    await tester.tap(find.byType(BackButton));
    await settleRouteTransition(tester);

    expect(router.routerDelegate.currentConfiguration.uri.path, '/favorites');
    // pop 后 uri 同样恒为 /favorites（uri 排除 imperative match），
    // 用最后匹配位置的 matchedLocation 验证确实回到列表页。
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites',
    );
    expect(find.text('列表进入的问题'), findsOneWidget);
    // 详情页专属 AppBar 标题不再出现，证明详情已出栈回到列表页。
    // 不用回复文本区分：回复摘要同样会出现在列表条目中。
    expect(find.text('收藏详情'), findsNothing);
  });

  testWidgets('pushNamed(mediaImage) 后 URI 携带 path，pop 回 /sync', (
    tester,
  ) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    final router = createAppRouter(initialLocation: AppDestination.sync.path);
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

    final router = createAppRouter(initialLocation: AppDestination.sync.path);
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

    final router = createAppRouter(initialLocation: '/sync/media/image');
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('媒体链接无效'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
