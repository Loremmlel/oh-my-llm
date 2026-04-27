import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/persistence/app_database_provider.dart';
import '../domain/models/fixed_prompt_sequence.dart';

/// 固定顺序提示词序列的 SQLite 仓库 Provider。
final fixedPromptSequenceRepositoryProvider =
    Provider<SqliteFixedPromptSequenceRepository>(
      (ref) =>
          SqliteFixedPromptSequenceRepository(ref.watch(appDatabaseProvider)),
    );

/// 固定顺序提示词序列的 SQLite 读写仓库。
///
/// 每条序列以一行记录存储；嵌套的 [FixedPromptSequenceStep] 列表序列化为 JSON 字符串列。
/// 数据始终整体读写，无需按步骤单独查询，因此 JSON 列比规范化表更简单高效。
class SqliteFixedPromptSequenceRepository {
  const SqliteFixedPromptSequenceRepository(this._database);

  final AppDatabase _database;

  /// 按更新时间降序返回全部固定顺序提示词序列。
  List<FixedPromptSequence> loadAll() {
    final rows = _database.connection.select(
      'SELECT id, name, steps_json, updated_at '
      'FROM fixed_prompt_sequences '
      'ORDER BY updated_at DESC;',
    );

    return rows.map(_rowToSequence).toList(growable: false);
  }

  /// 以事务方式将 [sequences] 全量写入数据库（先清空再插入）。
  ///
  /// 采用 DELETE + INSERT 而非 UPSERT，保证磁盘上的顺序与传入列表一致，
  /// 同时避免遗留已删除条目。
  Future<void> saveAll(List<FixedPromptSequence> sequences) async {
    _database.connection.execute('BEGIN;');
    try {
      _database.connection.execute('DELETE FROM fixed_prompt_sequences;');
      final stmt = _database.connection.prepare(
        'INSERT INTO fixed_prompt_sequences (id, name, steps_json, updated_at) '
        'VALUES (?, ?, ?, ?);',
      );
      for (final sequence in sequences) {
        stmt.execute([
          sequence.id,
          sequence.name,
          jsonEncode(sequence.steps.map((s) => s.toJson()).toList()),
          sequence.updatedAt.toIso8601String(),
        ]);
      }
      stmt.dispose();
      _database.connection.execute('COMMIT;');
    } catch (_) {
      _database.connection.execute('ROLLBACK;');
      rethrow;
    }
  }

  FixedPromptSequence _rowToSequence(Map<String, dynamic> row) {
    final rawSteps = jsonDecode(row['steps_json'] as String) as List;
    return FixedPromptSequence(
      id: row['id'] as String,
      name: row['name'] as String,
      steps: rawSteps
          .map(
            (item) => FixedPromptSequenceStep.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
