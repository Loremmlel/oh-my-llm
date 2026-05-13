import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/fixed_prompt_sequence_migration.dart';
import 'package:oh_my_llm/features/settings/data/fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';

/// 构造一条测试用固定顺序提示词序列。
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
  });

  final SharedPreferences preferences;
  final SqliteFixedPromptSequenceRepository repository;
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
  final repository = SqliteFixedPromptSequenceRepository(database);

  if (sqliteSequences.isNotEmpty) {
  await repository.saveAll(sqliteSequences);
  }
  if (legacySequences.isNotEmpty) {
  await saveLegacyFixedPromptSequencesForTest(preferences, legacySequences);
  }

  return _MigrationContext(preferences: preferences, repository: repository);
}

void main() {
  test('迁移会导入旧版固定顺序提示词、清理 SP，并置位标志', () async {
  final context = await _createMigrationContext(
    legacySequences: [_sequence('seq-1')],
  );

  await migrateLegacyFixedPromptSequences(
    preferences: context.preferences,
    repository: context.repository,
  );

  expect(context.repository.loadAll(), hasLength(1));
  expect(context.repository.loadAll().single.id, 'seq-1');
  expect(context.preferences.getString(fixedPromptSequencesStorageKey), isNull);
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
  );

  expect(migratedContext.repository.loadAll(), isEmpty);

  final residueContext = await _createMigrationContext(
    initialValues: <String, Object>{
      fixedPromptSequencesSqliteMigrationFlagKey: true,
    },
    legacySequences: [_sequence('seq-residue')],
  );

  await migrateLegacyFixedPromptSequences(
    preferences: residueContext.preferences,
    repository: residueContext.repository,
  );

  expect(residueContext.repository.loadAll(), isEmpty);
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
  );

  expect(context.repository.loadAll(), hasLength(1));
  expect(context.repository.loadAll().single.id, 'seq-existing');
  expect(context.preferences.getString(fixedPromptSequencesStorageKey), isNull);
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
    );

  expect(context.repository.loadAll(), isEmpty);
    expect(
    context.preferences.getBool(fixedPromptSequencesSqliteMigrationFlagKey),
      isTrue,
    );
  });
}
