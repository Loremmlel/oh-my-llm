import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

void main() {
  for (final sourceVersion in [23, 24]) {
    test('合法 v$sourceVersion 预设升级保留单 System 模式，新语法与条目元数据可重开', () async {
      final directory = await Directory.systemTemp.createTemp('preset-syntax-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/chat.sqlite';
      final legacy = sqlite3.open(path);
      legacy.execute(
        File('test/helpers/fixtures/schema_v21.sql').readAsStringSync(),
      );
      legacy.execute(
        File('test/helpers/fixtures/schema_v22_from_v21.sql')
            .readAsStringSync(),
      );
      legacy.execute(
        File('test/helpers/fixtures/schema_v23_from_v22.sql')
            .readAsStringSync(),
      );
      if (sourceVersion == 24) {
        legacy.execute(
          File('test/helpers/fixtures/schema_v24_from_v23.sql')
              .readAsStringSync(),
        );
      }
      legacy.execute(
        "INSERT INTO preset_prompts (id, name, messages_json, updated_at) VALUES ('old', '旧预设', '[]', '2026-01-01');",
      );
      if (sourceVersion == 24) {
        legacy.execute(
          "UPDATE preset_prompts SET single_system_prompt = 1 WHERE id = 'old';",
        );
      }
      legacy.close();
      final migrated = AppDatabase.forPath(path);
      var migratedOpen = true;
      addTearDown(() {
        if (migratedOpen) migrated.close();
      });
      final old = presetPromptRepository.loadAll(migrated).single;
      expect(old.syntax, PresetPromptSyntax.plain);
      expect(old.singleSystemPrompt, sourceVersion == 24);
      final incoming = old.copyWith(
        syntax: PresetPromptSyntax.sillyTavernSubsetV1,
        singleSystemPrompt: true,
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
      migratedOpen = false;
      final reopened = AppDatabase.forPath(path);
      addTearDown(reopened.close);
      final loaded = presetPromptRepository.loadAll(reopened);
      expect(
        loaded.singleWhere((p) => p.id == 'new'),
        incoming.copyWith(id: 'new'),
      );
      expect(loaded.singleWhere((p) => p.id == 'old'), old);
      expect(
        reopened.connection
            .select('PRAGMA user_version')
            .single['user_version'],
        greaterThanOrEqualTo(AppDatabase.currentSchemaVersion),
      );
      expect(
        () =>
            PresetPrompt.fromJson({...incoming.toJson(), 'syntax': 'unknown'}),
        throwsFormatException,
      );
      expect(
        PresetPrompt.fromJson(incoming.toJson()).messages.single.title,
        '',
      );
    });
  }
}
