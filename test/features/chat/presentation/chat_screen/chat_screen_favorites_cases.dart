import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';

import '../../../../helpers/async/widget_test_animation.dart';
import 'chat_screen_test_helpers.dart';

/// 直接经 repository 按 assistant 内容定位收藏；与收藏身份判定同通道，
/// 不依赖浏览窗口投影。
Favorite? _findFavorite(ProviderContainer container, String assistantContent) {
  return SqliteFavoritesRepository(container.read(appDatabaseProvider))
      .findByAssistantContent(assistantContent);
}

/// 打开 assistant 回复的收藏对话框。
Future<void> _openAddDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('收藏回复'));
  await settleOverlayTransition(tester);
}

void registerChatScreenFavoritesTests() {
  testWidgets('流式助手回复不提供收藏入口，完成后恢复', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    final controlled = fakeClient.enqueueControlledStream();
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '流式收藏边界');
    await controlled.listened;
    controlled.add(const ChatGenerationChunk(contentDelta: '尚未完成的回复'));
    await tester.pump();

    expect(find.byTooltip('收藏回复'), findsNothing);
    expect(_findFavorite(container, '尚未完成的回复'), isNull);

    await controlled.close();
    await waitForChatGeneration(
      tester,
      container,
      (state) => state.generation?.phase == ChatGenerationPhase.succeeded,
      description: '流式收藏边界用例生成完成',
    );
    expect(find.byTooltip('收藏回复'), findsOneWidget);
  });

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

    expect(_findFavorite(container, '收藏对话框测试回复'), isNull);

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

    final favorite = _findFavorite(container, '收藏对话框测试回复');
    expect(favorite, isNotNull);
    expect(
      favorite!.collectionId,
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

    expect(_findFavorite(container, '取消收藏测试回复'), isNull);
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

    expect(_findFavorite(container, '取消收藏流程测试'), isNotNull);
    expect(find.byTooltip('已收藏'), findsOneWidget);

    // 再次点击直接移除收藏（无确认弹窗），收藏状态同步更新。
    await tester.tap(find.byTooltip('已收藏'));
    await tester.pump();

    expect(_findFavorite(container, '取消收藏流程测试'), isNull);
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

    final newCollectionId = _findFavorite(container, '预选上次归类测试')!.collectionId;
    expect(
      newCollectionId,
      isNot(AppReservedEntities.uncategorizedFavoriteCollectionId),
    );

    // 取消收藏后重新打开对话框：上次归类目标已被预选，
    // 直接确认即落库到该夹，无需再点选项。
    await tester.tap(find.byTooltip('已收藏'));
    await tester.pump();
    expect(_findFavorite(container, '预选上次归类测试'), isNull);

    await _openAddDialog(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '收藏'),
      ),
    );
    await settleOverlayTransition(tester);

    expect(_findFavorite(container, '预选上次归类测试'), isNotNull);
    expect(_findFavorite(container, '预选上次归类测试')!.collectionId, newCollectionId);
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
    expect(_findFavorite(container, '新建收藏夹测试回复'), isNull);
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
    final favorite = _findFavorite(container, '新建收藏夹测试回复');
    expect(favorite, isNotNull);
    expect(favorite!.collectionId, isNotEmpty);
    expect(
      favorite.collectionId,
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
    expect(_findFavorite(container, '保留名校验测试'), isNull);
  });

  testWidgets('取消收藏后点击撤销通知按原收藏夹恢复收藏', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['撤销路径测试回复']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '测试问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '撤销路径用例生成完成',
    );

    // 首次点击：确认收藏到预选的系统未分类，并捕获移除前的完整收藏记录。
    await _openAddDialog(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '收藏'),
      ),
    );
    await settleOverlayTransition(tester);

    final before = _findFavorite(container, '撤销路径测试回复');
    expect(before, isNotNull);

    // 再次点击已收藏消息：直接移除并弹出带撤销按钮的通知气泡。
    await tester.tap(find.byTooltip('已收藏'));
    await settleAnimatedWidgetTransition(tester);
    expect(_findFavorite(container, '撤销路径测试回复'), isNull);
    expect(find.text('已取消收藏'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    // 点击撤销：按移除前捕获的 draft 恢复落库（原 collectionId 与来源元数据）。
    await tester.tap(find.widgetWithText(TextButton, '撤销'));
    await settleAnimatedWidgetTransition(tester);

    final restored = _findFavorite(container, '撤销路径测试回复');
    expect(restored, isNotNull);
    expect(restored!.collectionId, before!.collectionId);
    expect(restored.userMessageContent, before.userMessageContent);
    expect(restored.assistantContent, before.assistantContent);
    expect(
      restored.assistantReasoningContent,
      before.assistantReasoningContent,
    );
    expect(
      restored.assistantModelDisplayName,
      before.assistantModelDisplayName,
    );
    expect(restored.sourceConversationId, before.sourceConversationId);
    expect(restored.sourceConversationTitle, before.sourceConversationTitle);
    expect(restored.sourceAssistantMessageId, before.sourceAssistantMessageId);
    // 点击操作按钮后气泡自动关闭，图标恢复为已收藏。
    expect(find.text('撤销'), findsNothing);
    expect(find.byTooltip('已收藏'), findsOneWidget);
  });
}
