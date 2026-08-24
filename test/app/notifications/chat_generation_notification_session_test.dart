import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/notifications/chat_generation_notification_session.dart';

void main() {
  group('createChatGenerationNotificationSessionId', () {
    test('session ID 为 32 位小写十六进制', () {
      final pattern = RegExp(r'^[0-9a-f]{32}$');
      for (var i = 0; i < 50; i += 1) {
        expect(createChatGenerationNotificationSessionId(), matches(pattern));
      }
    });

    test('session ID 每次生成都不同', () {
      final ids = <String>{
        for (var i = 0; i < 50; i += 1)
          createChatGenerationNotificationSessionId(),
      };
      expect(ids.length, 50);
    });
  });

  group('chatGenerationNotificationSessionIdProvider', () {
    test('同一 ProviderScope 内 session 只创建一次', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final first = container.read(chatGenerationNotificationSessionIdProvider);
      final second = container.read(
        chatGenerationNotificationSessionIdProvider,
      );
      expect(first, same(second));
      expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('不同 ProviderScope 使用不同 session', () {
      final containerA = ProviderContainer();
      final containerB = ProviderContainer();
      addTearDown(containerA.dispose);
      addTearDown(containerB.dispose);
      final sessionA = containerA.read(
        chatGenerationNotificationSessionIdProvider,
      );
      final sessionB = containerB.read(
        chatGenerationNotificationSessionIdProvider,
      );
      expect(sessionA, isNot(sessionB));
    });
  });
}
