import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_preset_prompt_repository.dart';

void main() {
  test('合法 v26 升级保留预设内容与选项，随机头部默认关闭并可保存重开', () async {
    final directory = Directory.systemTemp.createTempSync('preset-header-');
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
      INSERT INTO preset_prompts (id, name, messages_json, single_system_prompt, syntax, custom_reasoning_tag, updated_at)
      VALUES ('old', '旧预设', '[{"id":"rule","role":"system","content":"保留正文"}]', 1, 'sillyTavernSubsetV1', 'thinking_diy', '2026-01-01');
    ''');
    legacy.close();
    final migrated = AppDatabase.forPath(path);
    try {
      final preset = presetPromptRepository.loadAll(migrated).single;
      expect(preset.messages.single.content, '保留正文');
      expect(preset.singleSystemPrompt, isTrue);
      expect(preset.syntax.name, 'sillyTavernSubsetV1');
      expect(preset.customReasoningTag, 'thinking_diy');
      expect(preset.randomHeader, isFalse);
      await presetPromptRepository.saveAll(migrated, [
        preset.copyWith(randomHeader: true),
      ]);
    } finally {
      migrated.close();
    }
    final reopened = AppDatabase.forPath(path);
    addTearDown(reopened.close);
    expect(
      presetPromptRepository.loadAll(reopened).single.randomHeader,
      isTrue,
    );
    expect(
      reopened.connection.select('PRAGMA user_version').single['user_version'],
      AppDatabase.currentSchemaVersion,
    );
  });
}
