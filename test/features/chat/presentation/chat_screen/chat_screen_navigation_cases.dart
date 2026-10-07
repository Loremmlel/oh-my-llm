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

void registerChatScreenNavigationTests() {
  testWidgets('路由首次和变更时选择会话，相同规范化 ID 重建及无效 ID 不覆盖手动选择', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      conversations: [
        TestFixtures.conversation('conv-a', '会话 A', DateTime(2026, 1, 2)),
        TestFixtures.conversation('conv-b', '会话 B', DateTime(2026, 1, 3)),
      ],
    );
    // 序号确保相同 ID 也真正重建 widget，单独重复赋值不会通知 ValueNotifier。
    final route = ValueNotifier<(String?, int)>(('conv-a', 0));
    addTearDown(route.dispose);
    await pumpTestApp(
      tester,
      child: ValueListenableBuilder<(String?, int)>(
        valueListenable: route,
        builder: (context, value, _) =>
            ChatScreen(initialConversationId: value.$1),
      ),
      preferences: preferences,
      database: database,
      extraOverrides: [
        chatGenerationClientProvider.overrideWithValue(
          FakeChatGenerationClient(),
        ),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    void expectActive(String id) {
      expect(container.read(chatSessionsProvider).activeConversationId, id);
      expect(container.read(chatSessionsProvider).errorMessage, isNull);
      expect(tester.takeException(), isNull);
    }

    expectActive('conv-a');

    route.value = ('conv-b', 1);
    await tester.pump();
    expectActive('conv-b');

    container.read(chatSessionsProvider.notifier).selectConversation('conv-a');
    await tester.pump();
    route.value = ('conv-b', 2);
    await tester.pump();
    expectActive('conv-a');
    route.value = (' conv-b ', 3);
    await tester.pump();
    expectActive('conv-a');

    route.value = ('conv-a', 4);
    await tester.pump();
    route.value = (' conv-b ', 5);
    await tester.pump();
    expectActive('conv-b');
    for (final id in <String?>[null, '', '   ', 'deleted-id']) {
      route.value = (id, route.value.$2 + 1);
      await tester.pump();
      expectActive('conv-b');
    }
  });
}
