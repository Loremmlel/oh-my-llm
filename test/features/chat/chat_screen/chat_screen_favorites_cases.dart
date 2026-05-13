import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/dialogs/add_to_favorites_dialog.dart';

import 'chat_screen_test_helpers.dart';

void registerChatScreenFavoritesTests() {
  testWidgets('chat screen bookmark tap shows add to favorites dialog', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['收藏对话框测试回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '测试问题');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('收藏回复'));
    await tester.pumpAndSettle();

    expect(find.byType(AddToFavoritesDialog), findsOneWidget);
    expect(find.text('收藏到'), findsOneWidget);
    expect(find.text('未分类'), findsOneWidget);
  });

  testWidgets('chat screen cancel favorites dialog does not add favorite', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['取消收藏测试回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '测试问题');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('收藏回复'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AddToFavoritesDialog)),
    );
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(container.read(favoritesProvider), isEmpty);
    expect(find.byTooltip('收藏回复'), findsOneWidget);
    expect(find.byTooltip('已收藏'), findsNothing);
  });

  testWidgets('chat screen favorites to uncategorized saves favorite and updates icon', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['收藏成功测试回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '测试问题');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收藏回复'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AddToFavoritesDialog)),
    );

    await tester.tap(find.text('未分类'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '收藏'));
    await tester.pumpAndSettle();

    expect(container.read(favoritesProvider), hasLength(1));
    expect(find.byTooltip('已收藏'), findsOneWidget);
    expect(find.byTooltip('收藏回复'), findsNothing);
  });

  testWidgets('chat screen second bookmark tap removes favorite and restores icon', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['取消收藏流程测试']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '测试问题');
    await tester.pumpAndSettle();

    // First tap: open dialog, select uncategorized, confirm
    await tester.tap(find.byTooltip('收藏回复'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AddToFavoritesDialog)),
    );
    await tester.tap(find.text('未分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '收藏'));
    await tester.pumpAndSettle();

    expect(container.read(favoritesProvider), hasLength(1));
    expect(find.byTooltip('已收藏'), findsOneWidget);

    await tester.tap(find.byTooltip('已收藏'));
    await tester.pumpAndSettle();

    expect(container.read(favoritesProvider), isEmpty);
    expect(find.byTooltip('收藏回复'), findsOneWidget);
    expect(find.byTooltip('已收藏'), findsNothing);
  });

  testWidgets('chat screen favorite dialog creates new collection and saves', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['新建收藏夹测试回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '测试问题');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('收藏回复'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AddToFavoritesDialog)),
    );

    await tester.tap(find.text('新建收藏夹'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '我的新收藏夹',
    );
    await tester.tap(find.widgetWithText(FilledButton, '新建并收藏'));
    await tester.pumpAndSettle();

    expect(find.text('已收藏'), findsOneWidget);
    expect(find.byTooltip('已收藏'), findsOneWidget);

    expect(container.read(favoritesProvider).length, 1);
    expect(
      container.read(favoritesProvider).first.collectionId,
      isNotNull,
    );
  });
}
