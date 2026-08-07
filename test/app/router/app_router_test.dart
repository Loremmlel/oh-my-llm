import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';

import '../../features/favorites/favorites_screen_test_helpers.dart';
import '../../helpers/test_harness.dart';

Future<SharedPreferences> _testPrefs(AppDatabase db) async {
  return createEmptyPreferences(db);
}

void main() {
  testWidgets('favorite detail direct URL 不依赖 extra 恢复完整内容', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-direct',
      userMessageContent: '直接打开的用户消息',
      assistantContent: '直接打开的助手回复',
      assistantModelDisplayName: 'DeepSeek V4 Flash',
    );
    final prefs = await _testPrefs(db);

    final router = createAppRouter(initialLocation: '/favorites/fav-direct');
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('直接打开的用户消息'), findsOneWidget);
    expect(find.text('直接打开的助手回复'), findsOneWidget);
    expect(find.text('DeepSeek V4 Flash'), findsOneWidget);
  });

  testWidgets('fresh router rebuild 后同一 URL 仍恢复详情', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavorite(
      db,
      id: 'fav-rebuild',
      userMessageContent: '重建后的用户消息',
      assistantContent: '重建后的助手回复',
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
  });

  testWidgets('invalid ID 显示收藏链接无效并可返回列表', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final prefs = await _testPrefs(db);

    final router = createAppRouter(initialLocation: '/favorites/%20');
    await pumpTestApp(tester, preferences: prefs, database: db, router: router);

    expect(find.text('收藏链接无效'), findsOneWidget);

    await tester.tap(find.text('返回收藏列表'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
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
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // push 是 imperative 路由，currentConfiguration.uri 只反映非 push 的
    // 顶层匹配，故用最后匹配位置的 matchedLocation 断言进入详情。
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites/fav-push',
    );
    expect(find.text('列表进入的回复'), findsOneWidget);

    // AppBar 自动 leading 是 BackButton（tooltip 随 locale 变化，用类型 finder）。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(router.routerDelegate.currentConfiguration.uri.path, '/favorites');
    expect(find.text('列表进入的问题'), findsOneWidget);
  });
}
