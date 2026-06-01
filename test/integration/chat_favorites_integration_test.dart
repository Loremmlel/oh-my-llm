/// Chat → Favorites 跨模块集成测试。
///
/// 验证从对话消息到收藏记录的完整数据流，确保收藏功能的核心用户路径
/// 不会因单侧变动而断裂。所有测试在 ProviderContainer 级别运行，不涉及 UI。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/favorites/application/collections_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';

import '../features/chat/chat_screen/chat_screen_test_helpers.dart';
import '../helpers/integration_test_helpers.dart';

void main() {
  late AppDatabase database;
  late SharedPreferences preferences;
  late FakeChatCompletionClient fakeClient;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      llmModelConfigsStorageKey: jsonEncode([
        {
          'id': 'model-1',
          'displayName': 'Test Model',
          'apiUrl': 'https://api.example.com/v1/chat/completions',
          'apiKey': 'sk-test',
          'modelName': 'test-model',
          'supportsReasoning': false,
        },
      ]),
    });
    preferences = await SharedPreferences.getInstance();
    database = AppDatabase.inMemory();
    fakeClient = FakeChatCompletionClient();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
        favoritesRepositoryProvider.overrideWithValue(
          SqliteFavoritesRepository(database),
        ),
        collectionsRepositoryProvider.overrideWithValue(
          SqliteCollectionsRepository(database),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
  });

  /// 获取当前对话的 assistant 回复内容。
  String assistantContent() {
    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    return messages.last.content;
  }

  /// 获取当前活动对话的 ID。
  String conversationId() {
    return container.read(chatSessionsProvider).activeConversationId;
  }

  // ── 收藏后出现在列表中 ──────────────────────────────────────────────────────

  test('发送消息后收藏助手回复 — 收藏列表中出现该记录', () async {
    fakeClient.enqueueChunks(['这是一条模型的回复']);
    await sendMsg(container, content: '用户的消息');

    final replyContent = assistantContent();
    expect(replyContent, '这是一条模型的回复');

    final favId = container.read(favoritesProvider.notifier).add(
          userMessageContent: '用户的消息',
          assistantContent: replyContent,
          sourceConversationId: conversationId(),
        );

    expect(favId, isNotEmpty);

    final favorites = container.read(favoritesProvider);
    expect(favorites, hasLength(1));
    expect(favorites.first.assistantContent, '这是一条模型的回复');
    expect(favorites.first.userMessageContent, '用户的消息');
    expect(favorites.first.sourceConversationId, conversationId());
  });

  // ── 删除原对话后收藏仍保留 ─────────────────────────────────────────────────

  test('删除原对话后收藏数据仍保留', () async {
    fakeClient.enqueueChunks(['这条回复会被收藏']);
    await sendMsg(container, content: '收藏前的消息');

    final replyContent = assistantContent();
    final convId = conversationId();

    container.read(favoritesProvider.notifier).add(
          userMessageContent: '收藏前的消息',
          assistantContent: replyContent,
          sourceConversationId: convId,
        );

    await container.read(chatSessionsProvider.notifier).deleteConversations({
      convId,
    });

    final favorites = container.read(favoritesProvider);
    expect(favorites, hasLength(1));
    expect(favorites.first.assistantContent, '这条回复会被收藏');
    expect(favorites.first.sourceConversationId, convId);
  });

  // ── 收藏移动到收藏夹后筛选正确 ─────────────────────────────────────────────

  test('收藏移动到收藏夹后筛选正确', () async {
    fakeClient.enqueueChunks(['放入收藏夹的回复']);
    await sendMsg(container, content: '测试消息');

    final replyContent = assistantContent();

    final favId = container.read(favoritesProvider.notifier).add(
          userMessageContent: '测试消息',
          assistantContent: replyContent,
        );

    final collectionId = container
        .read(collectionsProvider.notifier)
        .create('测试收藏夹');

    container.read(favoritesProvider.notifier).moveTo(favId, collectionId);

    container.read(favoritesFilterProvider.notifier).setFilter(collectionId);
    var favorites = container.read(favoritesProvider);
    expect(favorites, hasLength(1));
    expect(favorites.first.id, favId);
    expect(favorites.first.collectionId, collectionId);

    container.read(favoritesFilterProvider.notifier).setFilter(null);
    favorites = container.read(favoritesProvider);
    expect(favorites, hasLength(1));
    expect(favorites.first.id, favId);
  });
}
