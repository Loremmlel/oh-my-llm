import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/sqlite_entity_repository.dart';
import 'package:oh_my_llm/features/settings/data/migrations/preset_prompt_migration.dart';
import 'package:oh_my_llm/features/settings/data/preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';

import '../../../helpers/legacy_preferences_test_helpers.dart';

PresetPrompt _template(String id) {
  return PresetPrompt(
    id: id,
    name: '测试模板 $id',
    messages: [
      PromptMessage(
        id: '_legacy-system-message',
        role: PromptMessageRole.system,
        title: defaultSystemPromptTitle,
        content: '系统指令 $id',
      ),
    ],
    updatedAt: DateTime(2026, 1, 1),
  );
}

class _MigrationContext {
  const _MigrationContext({
    required this.preferences,
    required this.repository,
    required this.database,
  });

  final SharedPreferences preferences;
  final SqliteEntityRepository<PresetPrompt> repository;
  final AppDatabase database;
}

Future<_MigrationContext> _createMigrationContext({
  Map<String, Object> initialValues = const <String, Object>{},
  List<PresetPrompt> legacyTemplates = const <PresetPrompt>[],
  List<PresetPrompt> sqliteTemplates = const <PresetPrompt>[],
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final preferences = await SharedPreferences.getInstance();
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final repository = presetPromptRepository;

  if (sqliteTemplates.isNotEmpty) {
    await repository.saveAll(database, sqliteTemplates);
  }
  if (legacyTemplates.isNotEmpty) {
    await _saveLegacyPresetPromptsForTest(preferences, legacyTemplates);
  }

  return _MigrationContext(
    preferences: preferences,
    repository: repository,
    database: database,
  );
}

Future<void> _saveLegacyPresetPromptsForTest(
  SharedPreferences preferences,
  List<PresetPrompt> templates,
) async {
  await saveLegacyPreferenceCollectionForTest(
    preferences: preferences,
    storageKey: presetPromptsStorageKey,
    items: templates,
    toJson: (template) => template.toJson(),
  );
}

void main() {
  test('迁移会导入旧版模板、清理 SP，并置位标志', () async {
    final context = await _createMigrationContext(
      legacyTemplates: [_template('tpl-1')],
    );

    await migrateLegacyPresetPrompts(
      preferences: context.preferences,
      repository: context.repository,
      database: context.database,
    );

    expect(context.repository.loadAll(context.database), hasLength(1));
    expect(context.repository.loadAll(context.database).single.id, 'tpl-1');
    expect(context.preferences.getString(presetPromptsStorageKey), isNull);
    expect(
      context.preferences.getBool(presetPromptsSqliteMigrationFlagKey),
      isTrue,
    );
  });

  test('已满足迁移条件时保持幂等，并清理残留 SP 数据', () async {
    final migratedContext = await _createMigrationContext(
      initialValues: <String, Object>{
        presetPromptsSqliteMigrationFlagKey: true,
      },
    );

    await migrateLegacyPresetPrompts(
      preferences: migratedContext.preferences,
      repository: migratedContext.repository,
      database: migratedContext.database,
    );

    expect(migratedContext.repository.loadAll(migratedContext.database), isEmpty);

    final residueContext = await _createMigrationContext(
      initialValues: <String, Object>{
        presetPromptsSqliteMigrationFlagKey: true,
      },
      legacyTemplates: [_template('tpl-residue')],
    );

    await migrateLegacyPresetPrompts(
      preferences: residueContext.preferences,
      repository: residueContext.repository,
      database: residueContext.database,
    );

    expect(residueContext.repository.loadAll(residueContext.database), isEmpty);
    expect(
      residueContext.preferences.getString(presetPromptsStorageKey),
      isNull,
    );
  });

  test('SQLite 已有模板时保留现有数据并标记迁移完成', () async {
    final context = await _createMigrationContext(
      legacyTemplates: [_template('tpl-legacy')],
      sqliteTemplates: [_template('tpl-existing')],
    );

    await migrateLegacyPresetPrompts(
      preferences: context.preferences,
      repository: context.repository,
      database: context.database,
    );

    expect(context.repository.loadAll(context.database), hasLength(1));
    expect(context.repository.loadAll(context.database).single.id, 'tpl-existing');
    expect(context.preferences.getString(presetPromptsStorageKey), isNull);
    expect(
      context.preferences.getBool(presetPromptsSqliteMigrationFlagKey),
      isTrue,
    );
  });

  test('全新安装会直接置位迁移标志', () async {
    final context = await _createMigrationContext();

    await migrateLegacyPresetPrompts(
      preferences: context.preferences,
      repository: context.repository,
      database: context.database,
    );

    expect(context.repository.loadAll(context.database), isEmpty);
    expect(
      context.preferences.getBool(presetPromptsSqliteMigrationFlagKey),
      isTrue,
    );
  });
}
