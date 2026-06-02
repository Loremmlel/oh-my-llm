import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';

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
    expect(switched.toJson()['messageNodes'], isNotEmpty);
    expect(
      (switched.toJson()['selectedChildByParentId']
          as Map<String, dynamic>)[rootConversationParentId],
      'u1b',
    );
    expect(switched.excludedMessageIds, isEmpty);
  });
}
