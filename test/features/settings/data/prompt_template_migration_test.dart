import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_migration.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_template.dart';

/// 构造一条测试用 Prompt 模板。
PromptTemplate _template(String id) {
  return PromptTemplate(
    id: id,
    name: '测试模板 $id',
    systemPrompt: '系统指令 $id',
    messages: const [],
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  // ── 路径 1：SP 有旧数据，SQLite 为空，未迁移 ─────────────────────────────

  test('路径1：SP 有旧数据，导入 SQLite 并清除 SP、置位标志', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await saveLegacyPromptTemplatesForTest(preferences, [_template('tpl-1')]);

    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqlitePromptTemplateRepository(database);

    await migrateLegacyPromptTemplates(
      preferences: preferences,
      repository: repository,
    );

    expect(repository.loadAll(), hasLength(1));
    expect(repository.loadAll().single.id, 'tpl-1');
    expect(preferences.getString(promptTemplatesStorageKey), isNull);
    expect(
      preferences.getBool(promptTemplatesSqliteMigrationFlagKey),
      isTrue,
    );
  });

  // ── 路径 2：迁移标志已置位 ────────────────────────────────────────────────

  test('路径2：迁移标志已置位，无残留 SP → 直接返回，SQLite 保持不变', () async {
    SharedPreferences.setMockInitialValues({
      promptTemplatesSqliteMigrationFlagKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqlitePromptTemplateRepository(database);

    await migrateLegacyPromptTemplates(
      preferences: preferences,
      repository: repository,
    );

    expect(repository.loadAll(), isEmpty);
  });

  test('路径2b：迁移标志已置位，但 SP 仍有残留 → 清除 SP，不重复导入', () async {
    SharedPreferences.setMockInitialValues({
      promptTemplatesSqliteMigrationFlagKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    // 向 SP 写入残留数据。
    await saveLegacyPromptTemplatesForTest(
      preferences,
      [_template('tpl-residue')],
    );
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqlitePromptTemplateRepository(database);

    await migrateLegacyPromptTemplates(
      preferences: preferences,
      repository: repository,
    );

    // 残留数据未被导入，SP 已清除。
    expect(repository.loadAll(), isEmpty);
    expect(preferences.getString(promptTemplatesStorageKey), isNull);
  });

  // ── 路径 3：SQLite 已有数据 ───────────────────────────────────────────────

  test('路径3：SQLite 已有数据 + SP 有旧数据 → 跳过导入，清除 SP，置位标志', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqlitePromptTemplateRepository(database);

    // 先向 SQLite 写入数据（模拟其他设备同步）。
    await repository.saveAll([_template('tpl-existing')]);
    // 再向 SP 写入旧数据。
    await saveLegacyPromptTemplatesForTest(
      preferences,
      [_template('tpl-legacy')],
    );

    await migrateLegacyPromptTemplates(
      preferences: preferences,
      repository: repository,
    );

    // SQLite 仍只有原始数据，旧数据未被覆盖。
    expect(repository.loadAll(), hasLength(1));
    expect(repository.loadAll().single.id, 'tpl-existing');
    expect(preferences.getString(promptTemplatesStorageKey), isNull);
    expect(
      preferences.getBool(promptTemplatesSqliteMigrationFlagKey),
      isTrue,
    );
  });

  // ── 路径 4：全新安装 ──────────────────────────────────────────────────────

  test('路径4：全新安装（SP 和 SQLite 均为空）→ 直接置位标志', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqlitePromptTemplateRepository(database);

    await migrateLegacyPromptTemplates(
      preferences: preferences,
      repository: repository,
    );

    expect(repository.loadAll(), isEmpty);
    expect(
      preferences.getBool(promptTemplatesSqliteMigrationFlagKey),
      isTrue,
    );
  });
}
