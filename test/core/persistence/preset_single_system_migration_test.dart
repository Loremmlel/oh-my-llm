import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_preset_prompt_repository.dart';

void main() {
  test('合法 v23 预设迁移后保留消息且默认关闭单 System 模式', () async {
    final directory = await Directory.systemTemp.createTemp(
      'preset-single-system-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/chat.sqlite';
    final legacy = sqlite3.open(path);
    legacy.execute(
      File('test/helpers/fixtures/schema_v21.sql').readAsStringSync(),
    );
    legacy.execute(
      File('test/helpers/fixtures/schema_v22_from_v21.sql').readAsStringSync(),
    );
    legacy.execute(
      File('test/helpers/fixtures/schema_v23_from_v22.sql').readAsStringSync(),
    );
    legacy.execute(
      "INSERT INTO preset_prompts (id, name, messages_json, updated_at) "
      "VALUES ('old', '旧预设', '[{\"id\":\"m1\",\"role\":\"system\",\"content\":\"旧规则\"}]', '2026-01-01');",
    );
    legacy.close();

    final migrated = AppDatabase.forPath(path);
    final preset = presetPromptRepository.loadAll(migrated).single;
    expect(preset.name, '旧预设');
    expect(preset.messages.single.content, '旧规则');
    expect(preset.singleSystemPrompt, isFalse);
    expect(
      migrated.connection.select('PRAGMA user_version').single['user_version'],
      greaterThanOrEqualTo(AppDatabase.currentSchemaVersion),
    );
    await presetPromptRepository.saveAll(migrated, [
      preset.copyWith(singleSystemPrompt: true),
    ]);
    migrated.close();

    final reopened = AppDatabase.forPath(path);
    addTearDown(reopened.close);
    expect(
      presetPromptRepository.loadAll(reopened).single.singleSystemPrompt,
      isTrue,
    );
  });
}
