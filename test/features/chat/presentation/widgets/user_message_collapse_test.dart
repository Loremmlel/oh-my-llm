import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/user_message_collapse.dart';

ChatMessage userMsg(String content) {
  return ChatMessage(
    id: 'test',
    role: ChatMessageRole.user,
    content: content,
    parentId: 'root',
    createdAt: DateTime(2026),
  );
}

ChatMessage assistantMsg(String content) {
  return ChatMessage(
    id: 'test',
    role: ChatMessageRole.assistant,
    content: content,
    parentId: 'root',
    createdAt: DateTime(2026),
  );
}

void main() {
  group('shouldCollapseUserMessage', () {
    test('非用户消息返回 false', () {
      expect(shouldCollapseUserMessage(assistantMsg('x' * 500)), isFalse);
    });

    test('用户消息行数 ≤ 20 返回 false', () {
      expect(shouldCollapseUserMessage(userMsg('line')), isFalse);
    });

    test('用户消息行数 = 20 返回 false（边界）', () {
      final content = List.filled(20, 'line').join('\n');
      expect(shouldCollapseUserMessage(userMsg(content)), isFalse);
    });

    test('用户消息行数 > 20 返回 true', () {
      final content = List.filled(21, 'line').join('\n');
      expect(shouldCollapseUserMessage(userMsg(content)), isTrue);
    });
  });
}
