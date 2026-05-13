import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_migration.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';

/// 最简聊天记录 SP 条目，用于模拟旧版本 SharedPreferences 数据。
String _legacyPayload([String id = 'conv-1']) => jsonEncode([
  {
    'id': id,
    'title': '旧数据',
    'messages': [
      {
        'id': 'msg-1',
        'role': 'user',
        'content': '旧消息',
        'createdAt': '2026-01-01T00:00:00.000',
      },
    ],
    'createdAt': '2026-01-01T00:00:00.000',
    'updatedAt': '2026-01-01T00:00:00.000',
    'selectedModelId': null,
    'selectedPromptTemplateId': null,
    'reasoningEnabled': false,
    'reasoningEffort': 'medium',
  },
]);

Future<
  ({
    SharedPreferences preferences,
    SqliteChatConversationRepository repository,
  })
>
createMigrationContext(Map<String, Object> initialValues) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final preferences = await SharedPreferences.getInstance();
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  return (
    preferences: preferences,
    repository: SqliteChatConversationRepository(database),
  );
}

void main() {
  test('首次迁移会导入旧 SP 数据、清理旧键并置位标志', () async {
    final context = await createMigrationContext({
      chatConversationsStorageKey: _legacyPayload(),
    });

    await migrateLegacyChatConversations(
      preferences: context.preferences,
      repository: context.repository,
    );

    expect(context.repository.loadAll(), hasLength(1));
    expect(context.preferences.getString(chatConversationsStorageKey), isNull);
    expect(
      context.preferences.getBool(chatConversationsSqliteMigrationFlagKey),
      isTrue,
    );
  });

  test('已满足迁移条件的场景不会重复导入，但会清理残留旧数据', () async {
    final alreadyMigrated = await createMigrationContext({
      chatConversationsSqliteMigrationFlagKey: true,
    });
    await migrateLegacyChatConversations(
      preferences: alreadyMigrated.preferences,
      repository: alreadyMigrated.repository,
    );
    expect(alreadyMigrated.repository.loadAll(), isEmpty);

    final leftoverLegacyData = await createMigrationContext({
      chatConversationsStorageKey: _legacyPayload(),
    });
    await migrateLegacyChatConversations(
      preferences: leftoverLegacyData.preferences,
      repository: leftoverLegacyData.repository,
    );
    expect(leftoverLegacyData.repository.loadAll(), hasLength(1));

    await leftoverLegacyData.preferences.setString(
      chatConversationsStorageKey,
      _legacyPayload('conv-duplicate'),
    );
    expect(
      leftoverLegacyData.preferences.getBool(chatConversationsSqliteMigrationFlagKey),
      isTrue,
    );
    await migrateLegacyChatConversations(
      preferences: leftoverLegacyData.preferences,
      repository: leftoverLegacyData.repository,
    );
    expect(leftoverLegacyData.repository.loadAll(), hasLength(1));
    expect(
      leftoverLegacyData.preferences.getString(chatConversationsStorageKey),
      isNull,
    );

    final sqliteAlreadySeeded = await createMigrationContext({
      chatConversationsStorageKey: _legacyPayload(),
    });
    await migrateLegacyChatConversations(
      preferences: sqliteAlreadySeeded.preferences,
      repository: sqliteAlreadySeeded.repository,
    );
    await sqliteAlreadySeeded.preferences.remove(
      chatConversationsSqliteMigrationFlagKey,
    );
    await sqliteAlreadySeeded.preferences.setString(
      chatConversationsStorageKey,
      _legacyPayload('conv-other-device'),
    );
    await migrateLegacyChatConversations(
      preferences: sqliteAlreadySeeded.preferences,
      repository: sqliteAlreadySeeded.repository,
    );
    expect(sqliteAlreadySeeded.repository.loadAll(), hasLength(1));
    expect(sqliteAlreadySeeded.repository.loadAll().single.id, 'conv-1');
    expect(
      sqliteAlreadySeeded.preferences.getString(chatConversationsStorageKey),
      isNull,
    );
    expect(
      sqliteAlreadySeeded.preferences.getBool(
        chatConversationsSqliteMigrationFlagKey,
      ),
      isTrue,
    );
  });

  test('全新安装会直接置位标志而不导入任何数据', () async {
    final context = await createMigrationContext({});
    await migrateLegacyChatConversations(
      preferences: context.preferences,
      repository: context.repository,
    );

    expect(context.repository.loadAll(), isEmpty);
    expect(
      context.preferences.getBool(chatConversationsSqliteMigrationFlagKey),
      isTrue,
    );
  });
}
