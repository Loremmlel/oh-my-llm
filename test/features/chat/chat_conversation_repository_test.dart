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

  test('history summaries search only title and user messages', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteChatConversationRepository(database);

    await repository.saveAll([
      ChatConversation(
        id: 'conversation-1',
        title: 'Rust 重构计划',
        messages: const [],
        messageNodes: [
          ChatMessage(
            id: 'message-1',
            role: ChatMessageRole.user,
            content: '帮我整理 Rust 模块边界',
            parentId: rootConversationParentId,
            createdAt: DateTime(2026, 4, 27, 10),
          ),
          ChatMessage(
            id: 'message-2',
            role: ChatMessageRole.assistant,
            content: '这里包含不应匹配的 assistant 内容',
            parentId: 'message-1',
            createdAt: DateTime(2026, 4, 27, 10, 1),
          ),
        ],
        selectedChildByParentId: const {
          rootConversationParentId: 'message-1',
          'message-1': 'message-2',
        },
        createdAt: DateTime(2026, 4, 27, 10),
        updatedAt: DateTime(2026, 4, 27, 10, 1),
      ),
      ChatConversation(
        id: 'conversation-2',
        title: 'Flutter 路线图',
        messages: const [],
        messageNodes: [
          ChatMessage(
            id: 'message-3',
            role: ChatMessageRole.user,
            content: '请给我一份 Widget 测试清单',
            parentId: rootConversationParentId,
            createdAt: DateTime(2026, 4, 27, 11),
          ),
        ],
        selectedChildByParentId: const {rootConversationParentId: 'message-3'},
        createdAt: DateTime(2026, 4, 27, 11),
        updatedAt: DateTime(2026, 4, 27, 11),
      ),
    ]);

    expect(
      repository.loadHistorySummaries(keyword: 'Rust').map((item) => item.id),
      ['conversation-1'],
    );
    expect(
      repository
          .loadHistorySummaries(keyword: 'Widget 测试')
          .map((item) => item.id),
      ['conversation-2'],
    );
    expect(repository.loadHistorySummaries(keyword: '不应匹配'), isEmpty);
  });

  test('history summaries search user messages across all branches', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteChatConversationRepository(database);

    await repository.saveAll([
      ChatConversation(
        id: 'conversation-tree',
        title: '树状会话',
        messages: const [],
        messageNodes: [
          ChatMessage(
            id: 'u-root-a',
            role: ChatMessageRole.user,
            content: '当前分支用户消息',
            parentId: rootConversationParentId,
            createdAt: DateTime(2026, 4, 27, 12),
          ),
          ChatMessage(
            id: 'u-root-b',
            role: ChatMessageRole.user,
            content: '另一条分支关键词消息',
            parentId: rootConversationParentId,
            createdAt: DateTime(2026, 4, 27, 12, 1),
          ),
        ],
        selectedChildByParentId: const {rootConversationParentId: 'u-root-a'},
        createdAt: DateTime(2026, 4, 27, 12),
        updatedAt: DateTime(2026, 4, 27, 12, 1),
      ),
    ]);

    expect(
      repository.loadHistorySummaries(keyword: '分支关键词').map((item) => item.id),
      ['conversation-tree'],
    );
  });
}
