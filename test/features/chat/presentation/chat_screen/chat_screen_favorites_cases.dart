import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';

import '../../../../helpers/async/widget_test_animation.dart';
import 'chat_screen_test_helpers.dart';

/// 直接经 repository 统计收藏数量，不依赖浏览窗口投影。
int _favoriteCount(ProviderContainer container) {
  return SqliteFavoritesRepository(
    container.read(appDatabaseProvider),
  ).loadAll().length;
}

/// 打开 assistant 回复的收藏对话框。
Future<void> _openAddDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('收藏回复'));
  await settleOverlayTransition(tester);
}

void registerChatScreenFavoritesTests() {
  testWidgets('首次打开收藏对话框时系统未分类为预选且可直接确认', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['收藏对话框测试回复']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '测试问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '收藏对话框用例生成完成',
    );

    expect(_favoriteCount(container), 0);

    await _openAddDialog(tester);

    expect(find.text('收藏到'), findsOneWidget);
    expect(find.text('未分类'), findsOneWidget);

    // 无历史归类目标：不点任何选项直接确认，应落入系统未分类。
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '收藏'),
      ),
    );
    await settleOverlayTransition(tester);

    expect(_favoriteCount(container), 1);
    final favorites = SqliteFavoritesRepository(
      container.read(appDatabaseProvider),
    ).loadAll();
    expect(
      favorites.single.collectionId,
      AppReservedEntities.uncategorizedFavoriteCollectionId,
    );
  });

  testWidgets('取消收藏对话框不产生任何收藏', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['取消收藏测试回复']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '测试问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '取消收藏用例生成完成',
    );

    await _openAddDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await settleOverlayTransition(tester);

    expect(_favoriteCount(container), 0);
    expect(find.byTooltip('收藏回复'), findsOneWidget);
    expect(find.byTooltip('已收藏'), findsNothing);
  });

  testWidgets('再次点击已收藏消息直接移除并恢复图标', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['取消收藏流程测试']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '测试问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '取消收藏流程用例生成完成',
    );

    // 第一次点击：确认收藏到预选的系统未分类。
    await _openAddDialog(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '收藏'),
      ),
    );
    await settleOverlayTransition(tester);

    expect(_favoriteCount(container), 1);
    expect(find.byTooltip('已收藏'), findsOneWidget);

    // 再次点击直接移除收藏（无确认弹窗），收藏状态同步更新。
    await tester.tap(find.byTooltip('已收藏'));
    await tester.pump();

    expect(_favoriteCount(container), 0);
    expect(find.byTooltip('收藏回复'), findsOneWidget);
    expect(find.byTooltip('已收藏'), findsNothing);
  });

  testWidgets('对话框预选上次归类目标且无需再次选择即可确认', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['预选上次归类测试']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '测试问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '预选上次归类用例生成完成',
    );

    // 先经"新建收藏夹"路径归入新夹：成功归类会记录最近目标。
    await _openAddDialog(tester);
    await tester.tap(find.text('新建收藏夹'));
    await settleOverlayTransition(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '我的新收藏夹',
    );
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await settleOverlayTransition(tester);
    // 创建后仅选中：仍需再次确认才真正收藏。
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '收藏'),
      ),
    );
    await settleOverlayTransition(tester);

    final newCollectionId = SqliteFavoritesRepository(
      container.read(appDatabaseProvider),
    ).loadAll().single.collectionId;
    expect(
      newCollectionId,
      isNot(AppReservedEntities.uncategorizedFavoriteCollectionId),
    );

    // 取消收藏后重新打开对话框：上次归类目标已被预选，
    // 直接确认即落库到该夹，无需再点选项。
    await tester.tap(find.byTooltip('已收藏'));
    await tester.pump();
    expect(_favoriteCount(container), 0);

    await _openAddDialog(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '收藏'),
      ),
    );
    await settleOverlayTransition(tester);

    expect(_favoriteCount(container), 1);
    expect(
      SqliteFavoritesRepository(
        container.read(appDatabaseProvider),
      ).loadAll().single.collectionId,
      newCollectionId,
    );
  });

  testWidgets('对话框内新建收藏夹仅选中，需再次确认才落库', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['新建收藏夹测试回复']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '测试问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '新建收藏夹用例生成完成',
    );

    await _openAddDialog(tester);

    // 嵌套的创建表单同样经 overlay 开合动画。
    await tester.tap(find.text('新建收藏夹'));
    await settleOverlayTransition(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '我的新收藏夹',
    );
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await settleOverlayTransition(tester);

    // 创建后停留在对话框且新夹被选中，但尚未产生收藏。
    expect(find.text('收藏到'), findsOneWidget);
    expect(_favoriteCount(container), 0);
    expect(find.byTooltip('已收藏'), findsNothing);

    // 再次确认才真正收藏，归属为新夹。
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '收藏'),
      ),
    );
    await settleOverlayTransition(tester);

    expect(find.byTooltip('已收藏'), findsOneWidget);
    final favorites = SqliteFavoritesRepository(
      container.read(appDatabaseProvider),
    ).loadAll();
    expect(favorites, hasLength(1));
    expect(favorites.single.collectionId, isNotEmpty);
    expect(
      favorites.single.collectionId,
      isNot(AppReservedEntities.uncategorizedFavoriteCollectionId),
    );
  });

  testWidgets('保留名新建被拒绝并内联提示且不产生收藏', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['保留名校验测试']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '测试问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '保留名校验用例生成完成',
    );

    await _openAddDialog(tester);
    await tester.tap(find.text('新建收藏夹'));
    await settleOverlayTransition(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      AppReservedEntities.uncategorizedFavoriteCollectionName,
    );
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await settleOverlayTransition(tester);

    // 对话框保持打开并内联报错，收藏与收藏夹均未创建。
    expect(find.text('该名称被系统收藏夹保留'), findsOneWidget);
    expect(_favoriteCount(container), 0);
  });
}
