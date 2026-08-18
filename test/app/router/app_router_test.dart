import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

import '../../features/favorites/favorites_screen_test_helpers.dart';
import '../../features/media/helpers/fake_video_player_platform_bindings.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_harness.dart';
import '../../helpers/async/widget_test_animation.dart';

Future<SharedPreferences> _testPrefs(AppDatabase db) async {
  return createEmptyPreferences(db);
}

/// 构造一条含单条用户消息的会话 JSON，供深链选中测试种子。
///
/// 历史摘要只收录有消息或检查点的会话，无消息的裸会话不会出现在摘要里，
/// [selectConversation] 会因此静默 no-op，无法验证深链选中契约。
Map<String, dynamic> _conversation(
  String id,
  String title,
  DateTime updatedAt,
) {
  final messageId = '$id-message';
  return ChatConversation(
    id: id,
    title: title,
    messageNodes: [
      ChatMessage(
        id: messageId,
        role: ChatMessageRole.user,
        content: '$title 的首条用户消息',
        parentId: rootConversationParentId,
        createdAt: updatedAt.subtract(const Duration(minutes: 1)),
      ),
    ],
    selectedChildByParentId: {rootConversationParentId: messageId},
    createdAt: updatedAt.subtract(const Duration(minutes: 1)),
    updatedAt: updatedAt,
  ).toJson();
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
    SqliteFavoritesRepository(db).delete('fav-deleted');

    final router = createAppRouter(
      initialLocation: '/favorites/fav-deleted',
      videoPlayerBindingsFactory: _mobileTestBindings,
    );
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
      videoPlayerBindingsFactory: _mobileTestBindings,
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
        _conversation('conv-a', '会话 A', DateTime(2026, 1, 2)),
        _conversation('conv-b', '会话 B', DateTime(2026, 1, 3)),
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
        _conversation('conv-a', '会话 A', DateTime(2026, 1, 2)),
        _conversation('conv-b', '会话 B', DateTime(2026, 1, 3)),
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
        _conversation('conv-default', '默认会话', DateTime(2026, 1, 3)),
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
      conversations: [_conversation(specialId, '特殊会话', DateTime(2026, 1, 3))],
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
}
