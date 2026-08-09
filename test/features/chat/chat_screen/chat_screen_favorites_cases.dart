import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';

import '../../../helpers/widget_test_animation.dart';
import 'chat_screen_test_helpers.dart';

void registerChatScreenFavoritesTests() {
  testWidgets('chat screen bookmark tap shows add to favorites dialog', (
    tester,
  ) async {
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

    await tester.tap(find.byTooltip('收藏回复'));
    await settleOverlayTransition(tester);

    expect(find.text('收藏到'), findsOneWidget);
    expect(find.text('未分类'), findsOneWidget);
  });

  testWidgets('chat screen cancel favorites dialog does not add favorite', (
    tester,
  ) async {
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

    await tester.tap(find.byTooltip('收藏回复'));
    await settleOverlayTransition(tester);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await settleOverlayTransition(tester);

    expect(container.read(favoritesProvider), isEmpty);
    expect(find.byTooltip('收藏回复'), findsOneWidget);
    expect(find.byTooltip('已收藏'), findsNothing);
  });

  testWidgets(
    'chat screen second bookmark tap removes favorite and restores icon',
    (tester) async {
      final fakeClient = FakeChatGenerationClient()
        ..enqueueChunks(['取消收藏流程测试']);

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

      // First tap: open dialog, select uncategorized, confirm
      await tester.tap(find.byTooltip('收藏回复'));
      await settleOverlayTransition(tester);
      await tester.tap(find.text('未分类'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '收藏'));
      await settleOverlayTransition(tester);

      expect(container.read(favoritesProvider), hasLength(1));
      expect(find.byTooltip('已收藏'), findsOneWidget);

      // 再次点击直接移除收藏（无确认弹窗），收藏状态同步更新。
      await tester.tap(find.byTooltip('已收藏'));
      await tester.pump();

      expect(container.read(favoritesProvider), isEmpty);
      expect(find.byTooltip('收藏回复'), findsOneWidget);
      expect(find.byTooltip('已收藏'), findsNothing);
    },
  );

  testWidgets('chat screen favorite dialog creates new collection and saves', (
    tester,
  ) async {
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

    await tester.tap(find.byTooltip('收藏回复'));
    await settleOverlayTransition(tester);

    // 嵌套的新建收藏夹对话框同样经 overlay 开合动画。
    await tester.tap(find.text('新建收藏夹'));
    await settleOverlayTransition(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '我的新收藏夹',
    );
    await tester.tap(find.widgetWithText(FilledButton, '新建并收藏'));
    await settleOverlayTransition(tester);

    expect(find.text('已收藏'), findsOneWidget);
    expect(find.byTooltip('已收藏'), findsOneWidget);

    expect(container.read(favoritesProvider).length, 1);
    expect(container.read(favoritesProvider).first.collectionId, isNotNull);
  });
}
