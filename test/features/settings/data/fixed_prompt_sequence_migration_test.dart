import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/fixed_prompt_sequence_migration.dart';
import 'package:oh_my_llm/features/settings/data/fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';

/// 构造一条测试用固定顺序提示词序列。
FixedPromptSequence _sequence(String id) {
  return FixedPromptSequence(
    id: id,
    name: '测试序列 $id',
    steps: const [
      FixedPromptSequenceStep(id: 'step-1', content: '第一步'),
    ],
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  // ── 路径 1：SP 有旧数据，SQLite 为空，未迁移 ─────────────────────────────

  test('路径1：SP 有旧数据，导入 SQLite 并清除 SP、置位标志', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await saveLegacyFixedPromptSequencesForTest(
      preferences,
      [_sequence('seq-1')],
    );

    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteFixedPromptSequenceRepository(database);

    await migrateLegacyFixedPromptSequences(
      preferences: preferences,
      repository: repository,
    );

    expect(repository.loadAll(), hasLength(1));
    expect(repository.loadAll().single.id, 'seq-1');
    expect(preferences.getString(fixedPromptSequencesStorageKey), isNull);
    expect(
      preferences.getBool(fixedPromptSequencesSqliteMigrationFlagKey),
      isTrue,
    );
  });

  // ── 路径 2：迁移标志已置位 ────────────────────────────────────────────────

  test('路径2：迁移标志已置位，无残留 SP → 直接返回，SQLite 保持不变', () async {
    SharedPreferences.setMockInitialValues({
      fixedPromptSequencesSqliteMigrationFlagKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteFixedPromptSequenceRepository(database);

    await migrateLegacyFixedPromptSequences(
      preferences: preferences,
      repository: repository,
    );

    expect(repository.loadAll(), isEmpty);
  });

  test('路径2b：迁移标志已置位，但 SP 仍有残留 → 清除 SP，不重复导入', () async {
    SharedPreferences.setMockInitialValues({
      fixedPromptSequencesSqliteMigrationFlagKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    await saveLegacyFixedPromptSequencesForTest(
      preferences,
      [_sequence('seq-residue')],
    );
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteFixedPromptSequenceRepository(database);

    await migrateLegacyFixedPromptSequences(
      preferences: preferences,
      repository: repository,
    );

    expect(repository.loadAll(), isEmpty);
    expect(preferences.getString(fixedPromptSequencesStorageKey), isNull);
  });

  // ── 路径 3：SQLite 已有数据 ───────────────────────────────────────────────

  test('路径3：SQLite 已有数据 + SP 有旧数据 → 跳过导入，清除 SP，置位标志', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteFixedPromptSequenceRepository(database);

    // 先向 SQLite 写入数据。
    await repository.saveAll([_sequence('seq-existing')]);
    // 再向 SP 写入旧数据。
    await saveLegacyFixedPromptSequencesForTest(
      preferences,
      [_sequence('seq-legacy')],
    );

    await migrateLegacyFixedPromptSequences(
      preferences: preferences,
      repository: repository,
    );

    expect(repository.loadAll(), hasLength(1));
    expect(repository.loadAll().single.id, 'seq-existing');
    expect(preferences.getString(fixedPromptSequencesStorageKey), isNull);
    expect(
      preferences.getBool(fixedPromptSequencesSqliteMigrationFlagKey),
      isTrue,
    );
  });

  // ── 路径 4：全新安装 ──────────────────────────────────────────────────────

  test('路径4：全新安装（SP 和 SQLite 均为空）→ 直接置位标志', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteFixedPromptSequenceRepository(database);

    await migrateLegacyFixedPromptSequences(
      preferences: preferences,
      repository: repository,
    );

    expect(repository.loadAll(), isEmpty);
    expect(
      preferences.getBool(fixedPromptSequencesSqliteMigrationFlagKey),
      isTrue,
    );
  });
}
