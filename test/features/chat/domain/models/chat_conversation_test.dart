import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_generation_usage.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  test('resolves active path from tree selections', () {
    final conversation = ChatConversation.fromJson({
      'id': 'c2',
      'title': 'tree',
      'messageNodes': [
        {
          'id': 'u1a',
          'role': 'user',
          'content': '用户1-分支A',
          'parentId': rootConversationParentId,
          'createdAt': DateTime(2026, 4, 27, 10, 0).toIso8601String(),
        },
        {
          'id': 'u1b',
          'role': 'user',
          'content': '用户1-分支B',
          'parentId': rootConversationParentId,
          'createdAt': DateTime(2026, 4, 27, 10, 1).toIso8601String(),
        },
        {
          'id': 'a1a',
          'role': 'assistant',
          'content': '模型1-A',
          'parentId': 'u1a',
          'createdAt': DateTime(2026, 4, 27, 10, 2).toIso8601String(),
        },
        {
          'id': 'a1b',
          'role': 'assistant',
          'content': '模型1-B',
          'parentId': 'u1b',
          'createdAt': DateTime(2026, 4, 27, 10, 3).toIso8601String(),
        },
      ],
      'selectedChildByParentId': {
        rootConversationParentId: 'u1a',
        'u1a': 'a1a',
      },
      'createdAt': DateTime(2026, 4, 27, 10, 0).toIso8601String(),
      'updatedAt': DateTime(2026, 4, 27, 10, 3).toIso8601String(),
      'reasoningEnabled': false,
      'reasoningEffort': 'medium',
    });

    expect(conversation.messages.map((message) => message.id).toList(), [
      'u1a',
      'a1a',
    ]);

    final switched = conversation.copyWith(
      selectedChildByParentId: {rootConversationParentId: 'u1b', 'u1b': 'a1b'},
    );
    expect(switched.messages.map((message) => message.id).toList(), [
      'u1b',
      'a1b',
    ]);
  });

  test('缓存命中率按整棵消息树的有效助手用量加权计算', () {
    final conversation = ChatConversation(
      id: 'usage',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      messageNodes: [
        ChatMessage(
          id: 'a1',
          role: ChatMessageRole.assistant,
          content: 'active',
          createdAt: DateTime(2026),
          tokenUsage: const ChatGenerationUsage(
            inputTokens: 100,
            cachedInputTokens: 25,
          ),
        ),
        ChatMessage(
          id: 'a2',
          role: ChatMessageRole.assistant,
          content: 'other branch',
          createdAt: DateTime(2026),
          tokenUsage: const ChatGenerationUsage(
            inputTokens: 300,
            cachedInputTokens: 150,
          ),
        ),
        ChatMessage(
          id: 'ignored-zero-input',
          role: ChatMessageRole.assistant,
          content: 'ignored',
          createdAt: DateTime(2026),
          tokenUsage: const ChatGenerationUsage(
            inputTokens: 0,
            cachedInputTokens: 10,
          ),
        ),
        ChatMessage(
          id: 'user',
          role: ChatMessageRole.user,
          content: 'ignored',
          createdAt: DateTime(2026),
          tokenUsage: const ChatGenerationUsage(
            inputTokens: 100,
            cachedInputTokens: 100,
          ),
        ),
      ],
    );

    expect(conversation.cacheHitRate, 0.4375);
    expect(
      ChatConversation(
        id: 'none',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ).cacheHitRate,
      isNull,
    );
  });
}
