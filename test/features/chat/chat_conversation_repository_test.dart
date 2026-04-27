import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_migration.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  test('sqlite repository saves and restores branched conversations', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteChatConversationRepository(database);
    final conversation = ChatConversation(
      id: 'conversation-1',
      title: '分支会话',
      messages: [
        ChatMessage(
          id: 'user-1',
          role: ChatMessageRole.user,
          content: '当前用户分支',
          parentId: rootConversationParentId,
          createdAt: DateTime(2026, 4, 27, 10),
        ),
        ChatMessage(
          id: 'assistant-2',
          role: ChatMessageRole.assistant,
          content: '当前助手分支',
          parentId: 'user-1',
          reasoningContent: '保留思考内容',
          createdAt: DateTime(2026, 4, 27, 10, 2),
        ),
      ],
      messageNodes: [
        ChatMessage(
          id: 'user-1',
          role: ChatMessageRole.user,
          content: '当前用户分支',
          parentId: rootConversationParentId,
          createdAt: DateTime(2026, 4, 27, 10),
        ),
        ChatMessage(
          id: 'assistant-1',
          role: ChatMessageRole.assistant,
          content: '旧助手分支',
          parentId: 'user-1',
          createdAt: DateTime(2026, 4, 27, 10, 1),
        ),
        ChatMessage(
          id: 'assistant-2',
          role: ChatMessageRole.assistant,
          content: '当前助手分支',
          parentId: 'user-1',
          reasoningContent: '保留思考内容',
          createdAt: DateTime(2026, 4, 27, 10, 2),
        ),
      ],
      selectedChildByParentId: const {
        rootConversationParentId: 'user-1',
        'user-1': 'assistant-2',
      },
      createdAt: DateTime(2026, 4, 27, 10),
      updatedAt: DateTime(2026, 4, 27, 10, 2),
      selectedModelId: 'model-1',
      selectedPromptTemplateId: 'prompt-1',
      reasoningEnabled: true,
      reasoningEffort: ReasoningEffort.high,
    );

    await repository.saveAll([conversation]);
    final restored = repository.loadAll();

    expect(restored, hasLength(1));
    expect(restored.single.toJson(), equals(conversation.toJson()));
  });

  test(
    'migration imports legacy shared preferences payload into sqlite',
    () async {
      SharedPreferences.setMockInitialValues({
        chatConversationsStorageKey: jsonEncode([
          {
            'id': 'conversation-1',
            'title': '旧数据',
            'messages': [
              {
                'id': 'message-1',
                'role': 'user',
                'content': '旧用户消息',
                'createdAt': '2026-04-27T10:00:00.000',
              },
            ],
            'createdAt': '2026-04-27T10:00:00.000',
            'updatedAt': '2026-04-27T10:00:00.000',
            'selectedModelId': null,
            'selectedPromptTemplateId': null,
            'reasoningEnabled': false,
            'reasoningEffort': 'medium',
          },
        ]),
      });
      final preferences = await SharedPreferences.getInstance();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = SqliteChatConversationRepository(database);

      await migrateLegacyChatConversations(
        preferences: preferences,
        repository: repository,
      );

      expect(repository.loadAll(), hasLength(1));
      expect(preferences.getString(chatConversationsStorageKey), isNull);
      expect(
        preferences.getBool(chatConversationsSqliteMigrationFlagKey),
        isTrue,
      );
    },
  );
}
