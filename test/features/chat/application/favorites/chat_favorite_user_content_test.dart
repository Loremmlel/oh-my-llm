import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/favorites/chat_favorite_user_content.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

ChatMessage _user(String id, String content) {
  return ChatMessage(
    id: id,
    role: ChatMessageRole.user,
    content: content,
    createdAt: DateTime(2026, 1, 1),
  );
}

ChatMessage _system(String id, String content) {
  return ChatMessage(
    id: id,
    role: ChatMessageRole.system,
    content: content,
    createdAt: DateTime(2026, 1, 1),
  );
}

ChatMessage _assistant(String id, String content) {
  return ChatMessage(
    id: id,
    role: ChatMessageRole.assistant,
    content: content,
    createdAt: DateTime(2026, 1, 1),
  );
}

/// 按显示顺序把消息连成一条选中路径：首条为 root，后一条父节点指向前一条。
ChatConversation _conversationWithPath(List<ChatMessage> nodes) {
  final connected = <ChatMessage>[
    for (var i = 0; i < nodes.length; i++)
      nodes[i].copyWith(parentId: i == 0 ? null : nodes[i - 1].id),
  ];
  return ChatConversation(
    id: 'conv-1',
    title: '测试对话',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    messageNodes: connected,
  );
}

void main() {
  test('参数化锁定 user metadata 三分支 fallback', () {
    final user1 = _user('user-1', '第一条问题');
    final assistant1 = _assistant('assistant-1', '回复一');
    final user2 = _user('user-2', '第二条问题');
    final assistant2 = _assistant('assistant-2', '回复二');
    final absent = _assistant('absent', '不存在');

    final cases = [
      // 前缀有 user：取最近 user（user2，而非更早的 user1）。
      (
        name: '最近 user',
        nodes: [user1, assistant1, user2, assistant2],
        target: assistant2,
        expected: '第二条问题',
      ),
      // 前缀非空但无 user：回退前缀第一条（system）。
      (
        name: '无 user 回退前缀首条',
        nodes: [_system('system-1', '系统提示'), assistant1],
        target: assistant1,
        expected: '系统提示',
      ),
      // assistant 位于索引 0：空字符串。
      (
        name: 'assistant 首条',
        nodes: [assistant1],
        target: assistant1,
        expected: '',
      ),
      // assistant 不在消息列表：索引 -1，空字符串。
      (
        name: 'assistant 不存在',
        nodes: [user1, assistant1],
        target: absent,
        expected: '',
      ),
    ];

    for (final c in cases) {
      final conversation = _conversationWithPath(c.nodes);
      expect(
        resolveFavoriteUserContent(conversation, c.target),
        c.expected,
        reason: c.name,
      );
    }
  });
}
