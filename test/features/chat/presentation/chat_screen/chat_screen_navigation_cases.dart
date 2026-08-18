import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/test_harness.dart';
import 'chat_screen_test_helpers.dart';

/// ChatScreen 对路由 query 传入的 initialConversationId 的消费契约：
/// trim 后非空且变化时才调度一次 post-frame 选择，无效 ID 静默 no-op。
void registerChatScreenNavigationTests() {
  testWidgets('initialConversationId 在 post-frame 后选中目标会话', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      conversations: [
        TestFixtures.conversation('conv-a', '会话 A', DateTime(2026, 1, 2)),
        TestFixtures.conversation('conv-b', '会话 B', DateTime(2026, 1, 3)),
      ],
    );
    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(
      tester,
      preferences: preferences,
      database: database,
      fakeClient: fakeClient,
      initialConversationId: 'conv-a',
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(container.read(chatSessionsProvider).activeConversationId, 'conv-a');
    expect(tester.takeException(), isNull);
  });

  testWidgets('didUpdateWidget 中 changed ID 重新选中、未变 ID 不重复选中', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      conversations: [
        TestFixtures.conversation('conv-a', '会话 A', DateTime(2026, 1, 2)),
        TestFixtures.conversation('conv-b', '会话 B', DateTime(2026, 1, 3)),
      ],
    );
    final fakeClient = FakeChatGenerationClient();
    final initialConversationId = ValueNotifier<String?>('conv-a');
    await pumpTestApp(
      tester,
      child: ValueListenableBuilder<String?>(
        valueListenable: initialConversationId,
        builder: (context, id, _) => ChatScreen(initialConversationId: id),
      ),
      preferences: preferences,
      database: database,
      extraOverrides: [
        chatGenerationClientProvider.overrideWithValue(fakeClient),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(container.read(chatSessionsProvider).activeConversationId, 'conv-a');

    // changed ID：didUpdateWidget 重新调度一次 post-frame 选择。
    initialConversationId.value = 'conv-b';
    await tester.pump();
    expect(container.read(chatSessionsProvider).activeConversationId, 'conv-b');

    // 未变 ID：不重复调度，会话保持 conv-b 且无异常。
    initialConversationId.value = 'conv-b';
    await tester.pump();
    expect(container.read(chatSessionsProvider).activeConversationId, 'conv-b');
    expect(tester.takeException(), isNull);
  });

  testWidgets('空白或已删除的 initialConversationId 保持默认会话且无错误', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      conversations: [
        TestFixtures.conversation('conv-default', '默认会话', DateTime(2026, 1, 3)),
      ],
    );
    for (final id in ['', '   ', 'deleted-id']) {
      final fakeClient = FakeChatGenerationClient();
      await pumpChatScreen(
        tester,
        preferences: preferences,
        database: database,
        fakeClient: fakeClient,
        initialConversationId: id,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      expect(
        container.read(chatSessionsProvider).activeConversationId,
        'conv-default',
      );
      expect(container.read(chatSessionsProvider).errorMessage, isNull);
      expect(tester.takeException(), isNull);
    }
  });
}
