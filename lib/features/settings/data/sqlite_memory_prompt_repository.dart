import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/persistence/app_database_provider.dart';
import '../../../core/persistence/sqlite_replace_all.dart';
import '../domain/models/memory_prompt.dart';

/// 记忆总结提示词的 SQLite 仓库 Provider。
final memoryPromptRepositoryProvider = Provider<SqliteMemoryPromptRepository>(
  (ref) => SqliteMemoryPromptRepository(ref.watch(appDatabaseProvider)),
);

/// 记忆总结提示词的 SQLite 读写仓库。
class SqliteMemoryPromptRepository {
  const SqliteMemoryPromptRepository(this._database);

  final AppDatabase _database;

  List<MemoryPrompt> loadAll() {
    final rows = _database.connection.select(
      'SELECT id, name, content, updated_at '
      'FROM memory_prompts '
      'ORDER BY updated_at DESC;',
    );
    return rows.map(_rowToMemoryPrompt).toList(growable: false);
  }

  Future<void> saveAll(List<MemoryPrompt> memoryPrompts) async {
    replaceAllRowsInTable(
      connection: _database.connection,
      deleteSql: 'DELETE FROM memory_prompts;',
      insertSql:
          'INSERT INTO memory_prompts (id, name, content, updated_at) '
          'VALUES (?, ?, ?, ?);',
      items: memoryPrompts,
      buildValues: (memoryPrompt) => [
        memoryPrompt.id,
        memoryPrompt.name,
        memoryPrompt.content,
        memoryPrompt.updatedAt.toIso8601String(),
      ],
    );
  }

  MemoryPrompt _rowToMemoryPrompt(Map<String, dynamic> row) {
    return MemoryPrompt(
      id: row['id'] as String,
      name: row['name'] as String,
      content: row['content'] as String,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
