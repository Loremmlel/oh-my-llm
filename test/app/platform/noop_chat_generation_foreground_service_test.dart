import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/platform/noop_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';

const _payload = ChatGenerationForegroundPayload(
  token: 1,
  conversationId: 'conv-1',
  title: '正在生成',
  text: '正文',
  publicTitle: '正在生成',
  publicText: '请打开应用查看进度',
  actionKind: ChatGenerationNotificationActionKind.none,
);

void main() {
  test('所有命令返回 unsupportedPlatform', () async {
    final noop = NoopChatGenerationForegroundService();

    expect(
      await noop.start(_payload),
      const ChatForegroundCommandResult.unavailable(
        ChatForegroundFailureCode.unsupportedPlatform,
      ),
    );
    expect(
      await noop.update(_payload),
      const ChatForegroundCommandResult.unavailable(
        ChatForegroundFailureCode.unsupportedPlatform,
      ),
    );
    expect(
      await noop.remove(token: 1, conversationId: 'conv-1'),
      const ChatForegroundCommandResult.unavailable(
        ChatForegroundFailureCode.unsupportedPlatform,
      ),
    );
    expect(
      await noop.fail(_payload),
      const ChatForegroundCommandResult.unavailable(
        ChatForegroundFailureCode.unsupportedPlatform,
      ),
    );
  });

  test('权限返回 notRequired', () async {
    final noop = NoopChatGenerationForegroundService();

    expect(
      await noop.ensureNotificationPermission(),
      ChatNotificationPermissionStatus.notRequired,
    );
  });

  test('待打开会话 ID 恒为 null', () async {
    final noop = NoopChatGenerationForegroundService();

    expect(await noop.takePendingOpenConversation(), isNull);
  });

  test('actions 永不 emit', () async {
    final noop = NoopChatGenerationForegroundService();
    final collected = <ChatGenerationForegroundAction>[];
    final subscription = noop.actions.listen(collected.add);

    // 空流立即完成，等待 onDone 后断言全程零事件。
    await subscription.asFuture<void>();
    expect(collected, isEmpty);
    await subscription.cancel();
  });

  test('dispose 是安全 no-op', () async {
    final noop = NoopChatGenerationForegroundService();

    noop.dispose();
    noop.dispose(); // 幂等：不抛错。
  });
}
