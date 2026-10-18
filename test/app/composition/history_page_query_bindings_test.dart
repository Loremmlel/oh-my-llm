import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/ports/history_page_query.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

import '../../helpers/fixtures.dart';

void main() {
  late AppDatabase database;
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    database = AppDatabase.inMemory();
    addTearDown(database.close);
  });

  ProviderContainer createContainer() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        ...appCompositionOverrides(
          bindChatGenerationClient: false,
          bindChatConversationRepository: false,
          bindMediaLibraryFactory: false,
          bindChatGenerationForegroundService: false,
          bindFavoritesRepositories: false,
          bindHistoryPageQuery: true,
          hostPlatform: TargetPlatform.windows,
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  ChatConversation conversation(String id, String title) {
    final messageId = '$id-user';
    return ChatConversation(
      id: id,
      title: title,
      messageNodes: [
        TestFixtures.userMessage(
          id: messageId,
          content: '$id 的用户消息',
          createdAt: DateTime(2026, 6, 1),
          parentId: rootConversationParentId,
        ),
      ],
      selectedChildByParentId: {rootConversationParentId: messageId},
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
    );
  }

  test('composition 绑定的 HistoryPageQuery 可完成一页内存库查询', () async {
    await SqliteChatConversationRepository(database)
        .saveConversations([conversation('c1', '组合绑定会话')]);
    final c = createContainer();

    final query = c.read(historyPageQueryProvider);
    final result = await query.load(
      HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
    );

    final summaries = result.items.cast<ChatConversationSummary>();
    expect(summaries.map((e) => e.id), ['c1']);
    expect(result.totalItems, 1);
    expect(result.committedPage, 1);
    await query.dispose();
  });
}
