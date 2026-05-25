import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/sqlite_entity_repository.dart';
import 'package:oh_my_llm/features/settings/data/migrations/fixed_prompt_sequence_migration.dart';
import 'package:oh_my_llm/features/settings/data/fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';

import '../../../helpers/legacy_preferences_test_helpers.dart';

FixedPromptSequence _sequence(String id) {
  return FixedPromptSequence(
    id: id,
    name: '测试序列 $id',
    steps: const [FixedPromptSequenceStep(id: 'step-1', content: '第一步')],
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
  final SqliteEntityRepository<FixedPromptSequence> repository;
  final AppDatabase database;
}

Future<_MigrationContext> _createMigrationContext({
  Map<String, Object> initialValues = const <String, Object>{},
  List<FixedPromptSequence> legacySequences = const <FixedPromptSequence>[],
  List<FixedPromptSequence> sqliteSequences = const <FixedPromptSequence>[],
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final preferences = await SharedPreferences.getInstance();
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final repository = fixedPromptSequenceRepository;

  if (sqliteSequences.isNotEmpty) {
    await repository.saveAll(database, sqliteSequences);
  }
  if (legacySequences.isNotEmpty) {
    await _saveLegacyFixedPromptSequencesForTest(preferences, legacySequences);
  }

  return _MigrationContext(
    preferences: preferences,
    repository: repository,
    database: database,
  );
}

Future<void> _saveLegacyFixedPromptSequencesForTest(
  SharedPreferences preferences,
  List<FixedPromptSequence> sequences,
) async {
  await saveLegacyPreferenceCollectionForTest(
    preferences: preferences,
    storageKey: fixedPromptSequencesStorageKey,
    items: sequences,
    toJson: (sequence) => sequence.toJson(),
  );
}

void main() {
  test('迁移会导入旧版固定顺序提示词、清理 SP，并置位标志', () async {
    final context = await _createMigrationContext(
      legacySequences: [_sequence('seq-1')],
    );

    await migrateLegacyFixedPromptSequences(
      preferences: context.preferences,
      repository: context.repository,
      database: context.database,
    );

    expect(context.repository.loadAll(context.database), hasLength(1));
    expect(context.repository.loadAll(context.database).single.id, 'seq-1');
    expect(
      context.preferences.getString(fixedPromptSequencesStorageKey),
      isNull,
    );
    expect(
      context.preferences.getBool(fixedPromptSequencesSqliteMigrationFlagKey),
      isTrue,
    );
  });

  test('已满足迁移条件时保持幂等，并清理残留 SP 数据', () async {
    final migratedContext = await _createMigrationContext(
      initialValues: <String, Object>{
        fixedPromptSequencesSqliteMigrationFlagKey: true,
      },
    );

    await migrateLegacyFixedPromptSequences(
      preferences: migratedContext.preferences,
      repository: migratedContext.repository,
      database: migratedContext.database,
    );

    expect(
      migratedContext.repository.loadAll(migratedContext.database),
      isEmpty,
    );

    final residueContext = await _createMigrationContext(
      initialValues: <String, Object>{
        fixedPromptSequencesSqliteMigrationFlagKey: true,
      },
      legacySequences: [_sequence('seq-residue')],
    );

    await migrateLegacyFixedPromptSequences(
      preferences: residueContext.preferences,
      repository: residueContext.repository,
      database: residueContext.database,
    );

    expect(
      residueContext.repository.loadAll(residueContext.database),
      isEmpty,
    );
    expect(
      residueContext.preferences.getString(fixedPromptSequencesStorageKey),
      isNull,
    );
  });

  test('SQLite 已有序列时保留现有数据并标记迁移完成', () async {
    final context = await _createMigrationContext(
      legacySequences: [_sequence('seq-legacy')],
      sqliteSequences: [_sequence('seq-existing')],
    );

    await migrateLegacyFixedPromptSequences(
      preferences: context.preferences,
      repository: context.repository,
      database: context.database,
    );

    expect(context.repository.loadAll(context.database), hasLength(1));
    expect(
      context.repository.loadAll(context.database).single.id,
      'seq-existing',
    );
    expect(
      context.preferences.getString(fixedPromptSequencesStorageKey),
      isNull,
    );
    expect(
      context.preferences.getBool(fixedPromptSequencesSqliteMigrationFlagKey),
      isTrue,
    );
  });

  test('全新安装会直接置位迁移标志', () async {
    final context = await _createMigrationContext();

    await migrateLegacyFixedPromptSequences(
      preferences: context.preferences,
      repository: context.repository,
      database: context.database,
    );

    expect(context.repository.loadAll(context.database), isEmpty);
    expect(
      context.preferences.getBool(fixedPromptSequencesSqliteMigrationFlagKey),
      isTrue,
    );
  });
}
