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

void main() {
  // ── 路径 1：SP 有旧数据，SQLite 为空，未迁移 ─────────────────────────────

  test('路径1：SP 有旧数据，导入 SQLite 并清除 SP、置位标志', () async {
    SharedPreferences.setMockInitialValues({
      chatConversationsStorageKey: _legacyPayload(),
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
  });

  // ── 路径 2：迁移标志已置位 ────────────────────────────────────────────────

  test('路径2：迁移标志已置位，SP 无残留 → 直接返回，不导入', () async {
    SharedPreferences.setMockInitialValues({
      chatConversationsSqliteMigrationFlagKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteChatConversationRepository(database);

    await migrateLegacyChatConversations(
      preferences: preferences,
      repository: repository,
    );

    expect(repository.loadAll(), isEmpty);
  });

  test('路径2b：迁移标志已置位，但 SP 中仍有残留旧数据 → 清除 SP，不重复导入', () async {
    // 构造已有 SQLite 数据（需要先导入一次）。
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteChatConversationRepository(database);

    SharedPreferences.setMockInitialValues({
      chatConversationsStorageKey: _legacyPayload(),
    });
    var preferences = await SharedPreferences.getInstance();
    // 第一次正常迁移。
    await migrateLegacyChatConversations(
      preferences: preferences,
      repository: repository,
    );
    expect(repository.loadAll(), hasLength(1));

    // 模拟 SP 键被意外恢复（遗留数据场景）。
    await preferences.setString(
      chatConversationsStorageKey,
      _legacyPayload('conv-duplicate'),
    );
    // 标志仍为 true。
    expect(
      preferences.getBool(chatConversationsSqliteMigrationFlagKey),
      isTrue,
    );

    // 再次迁移：应清除 SP，不重复写入 SQLite。
    await migrateLegacyChatConversations(
      preferences: preferences,
      repository: repository,
    );

    // 仍然只有原来那 1 条，不增加。
    expect(repository.loadAll(), hasLength(1));
    expect(preferences.getString(chatConversationsStorageKey), isNull);
  });

  // ── 路径 3：SQLite 已有数据 ───────────────────────────────────────────────

  test('路径3：SQLite 已有数据 + SP 有旧数据 → 跳过导入，清除 SP，置位标志', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteChatConversationRepository(database);

    // 先向 SQLite 写入一条数据（模拟其他设备同步场景）。
    SharedPreferences.setMockInitialValues({
      chatConversationsStorageKey: _legacyPayload(),
    });
    var preferences = await SharedPreferences.getInstance();
    await migrateLegacyChatConversations(
      preferences: preferences,
      repository: repository,
    );
    // 重置标志，模拟"标志丢失但 SQLite 已有数据"。
    await preferences.remove(chatConversationsSqliteMigrationFlagKey);

    // SP 重新写入旧数据（不同 id，确保不是同一条）。
    await preferences.setString(
      chatConversationsStorageKey,
      _legacyPayload('conv-other-device'),
    );

    await migrateLegacyChatConversations(
      preferences: preferences,
      repository: repository,
    );

    // SQLite 仍然只有第一次写入的那 1 条。
    expect(repository.loadAll(), hasLength(1));
    expect(repository.loadAll().single.id, 'conv-1');
    // SP 旧数据已清除，标志已置位。
    expect(preferences.getString(chatConversationsStorageKey), isNull);
    expect(
      preferences.getBool(chatConversationsSqliteMigrationFlagKey),
      isTrue,
    );
  });

  // ── 路径 4：全新安装（SP 无数据，SQLite 为空）────────────────────────────

  test('路径4：全新安装 → 不导入，直接置位标志', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteChatConversationRepository(database);

    await migrateLegacyChatConversations(
      preferences: preferences,
      repository: repository,
    );

    expect(repository.loadAll(), isEmpty);
    expect(
      preferences.getBool(chatConversationsSqliteMigrationFlagKey),
      isTrue,
    );
  });
}
