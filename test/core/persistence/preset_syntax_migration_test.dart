import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

void main() {
  test('合法 v23 预设默认普通文本，新语法与条目元数据保存后可重开', () async {
    final directory = await Directory.systemTemp.createTemp('preset-syntax-');
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
      "ALTER TABLE messages ADD COLUMN images_json TEXT NOT NULL DEFAULT '[]'; PRAGMA user_version = 23;",
    );
    legacy.execute(
      "INSERT INTO preset_prompts (id, name, messages_json, updated_at) VALUES ('old', '旧预设', '[]', '2026-01-01');",
    );
    legacy.close();
    final migrated = AppDatabase.forPath(path);
    final old = presetPromptRepository.loadAll(migrated).single;
    expect(old.syntax, PresetPromptSyntax.plain);
    final incoming = old.copyWith(
      syntax: PresetPromptSyntax.sillyTavernSubsetV1,
      messages: [
        const PromptMessage(
          id: 'entry',
          role: PromptMessageRole.system,
          title: '',
          content: '\n{{user}}\n',
          enabled: false,
          sourceIdentifier: 'original',
          importInsertionOrder: 3,
        ),
      ],
    );
    await presetPromptRepository.saveAll(migrated, [
      old,
      incoming.copyWith(id: 'new'),
    ]);
    migrated.close();
    final reopened = AppDatabase.forPath(path);
    addTearDown(reopened.close);
    final loaded = presetPromptRepository.loadAll(reopened);
    expect(
      loaded.singleWhere((p) => p.id == 'new'),
      incoming.copyWith(id: 'new'),
    );
    expect(loaded.singleWhere((p) => p.id == 'old'), old);
    expect(
      reopened.connection.select('PRAGMA user_version').single['user_version'],
      greaterThanOrEqualTo(AppDatabase.currentSchemaVersion),
    );
    expect(
      () => PresetPrompt.fromJson({...incoming.toJson(), 'syntax': 'unknown'}),
      throwsFormatException,
    );
    expect(PresetPrompt.fromJson(incoming.toJson()).messages.single.title, '');
  });
}
