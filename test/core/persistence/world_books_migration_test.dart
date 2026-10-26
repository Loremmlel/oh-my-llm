import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/worldbooks/sqlite_world_book_repository.dart';

import '../../helpers/fixtures.dart';

void main() {
  test('合法 v25 升级保留预设和会话，世界书、选择与 CoT 标签可重开', () async {
    final directory = Directory.systemTemp.createTempSync('worldbooks-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/chat.sqlite';
    final legacy = sqlite3.open(path);
    for (final file in [
      'schema_v21.sql',
      'schema_v22_from_v21.sql',
      'schema_v23_from_v22.sql',
      'schema_v24_from_v23.sql',
      'schema_v25_from_v24.sql',
    ]) {
      legacy.execute(File('test/helpers/fixtures/$file').readAsStringSync());
    }
    legacy.execute(
      "INSERT INTO preset_prompts (id, name, messages_json, updated_at, syntax, single_system_prompt) VALUES ('old', '旧预设', '[]', '2026-01-01', 'sillyTavernSubsetV1', 1);",
    );
    legacy.execute(
      "INSERT INTO conversations (id, title, created_at, updated_at, reasoning_effort) VALUES ('old-chat', '旧对话', '2026-01-01', '2026-01-01', 'medium');",
    );
    legacy.close();

    final migrated = AppDatabase.forPath(path);
    final repository = SqliteChatConversationRepository(migrated);
    final old = repository.loadConversation('old-chat')!;
    expect(old.title, '旧对话');
    expect(old.selectedWorldBookIds, isEmpty);
    final preset = presetPromptRepository.loadAll(migrated).single;
    expect(preset.singleSystemPrompt, isTrue);
    expect(preset.syntax.name, 'sillyTavernSubsetV1');
    expect(preset.customReasoningTag, '');
    final book = TestFixtures.worldBook();
    await worldBookRepository.saveAll(migrated, [book]);
    await presetPromptRepository.saveAll(migrated, [
      preset.copyWith(customReasoningTag: 'thinking_diy'),
    ]);
    await repository.saveConversation(
      old.copyWith(selectedWorldBookIds: [book.id, 'second-book']),
    );
    // 全量保存世界书不能清空会话的选择。
    await worldBookRepository.saveAll(migrated, [book.copyWith(name: '改名')]);
    migrated.close();
    final reopened = AppDatabase.forPath(path);
    addTearDown(reopened.close);
    expect(
      worldBookRepository.loadAll(reopened).single,
      book.copyWith(name: '改名'),
    );
    expect(
      SqliteChatConversationRepository(reopened)
          .loadAll()
          .single
          .selectedWorldBookIds,
      [book.id, 'second-book'],
    );
    expect(
      presetPromptRepository.loadAll(reopened).single.customReasoningTag,
      'thinking_diy',
    );
    expect(
      reopened.connection.select('PRAGMA user_version').single['user_version'],
      AppDatabase.currentSchemaVersion,
    );
  });

  test('v27 单本选择迁移为有序列表，未选择的会话保持空列表', () {
    final directory = Directory.systemTemp.createTempSync('worldbooks-v27-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/chat.sqlite';
    final legacy = sqlite3.open(path);
    for (final file in [
      'schema_v21.sql',
      'schema_v22_from_v21.sql',
      'schema_v23_from_v22.sql',
      'schema_v24_from_v23.sql',
      'schema_v25_from_v24.sql',
      'schema_v26_from_v25.sql',
    ]) {
      legacy.execute(File('test/helpers/fixtures/$file').readAsStringSync());
    }
    legacy.execute('''
      ALTER TABLE preset_prompts ADD COLUMN random_header INTEGER NOT NULL DEFAULT 0;
      PRAGMA user_version = 27;
      INSERT INTO conversations (id, created_at, updated_at, reasoning_effort, selected_world_book_id)
      VALUES ('selected', '2026-01-01', '2026-01-01', 'medium', 'world-1'),
             ('empty', '2026-01-01', '2026-01-01', 'medium', NULL);
    ''');
    legacy.close();
    final database = AppDatabase.forPath(path);
    addTearDown(database.close);
    final repository = SqliteChatConversationRepository(database);
    expect(repository.loadConversation('selected')!.selectedWorldBookIds, [
      'world-1',
    ]);
    expect(repository.loadConversation('empty')!.selectedWorldBookIds, isEmpty);
  });
}
