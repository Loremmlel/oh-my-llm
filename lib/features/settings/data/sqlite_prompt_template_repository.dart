import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/persistence/app_database_provider.dart';
import '../domain/models/prompt_template.dart';

/// Prompt 模板的 SQLite 仓库 Provider。
final promptTemplateRepositoryProvider = Provider<SqlitePromptTemplateRepository>(
  (ref) => SqlitePromptTemplateRepository(ref.watch(appDatabaseProvider)),
);

/// Prompt 模板的 SQLite 读写仓库。
///
/// 每条模板以一行记录存储；嵌套的 [PromptMessage] 列表序列化为 JSON 字符串列。
/// 数据始终整体读写，无需按子消息单独查询，因此 JSON 列比规范化表更简单高效。
class SqlitePromptTemplateRepository {
  const SqlitePromptTemplateRepository(this._database);

  final AppDatabase _database;

  /// 按更新时间降序返回全部 Prompt 模板。
  List<PromptTemplate> loadAll() {
    final rows = _database.connection.select(
      'SELECT id, name, system_prompt, messages_json, updated_at '
      'FROM prompt_templates '
      'ORDER BY updated_at DESC;',
    );

    return rows.map(_rowToTemplate).toList(growable: false);
  }

  /// 以事务方式将 [templates] 全量写入数据库（先清空再插入）。
  ///
  /// 采用 DELETE + INSERT 而非 UPSERT，保证磁盘上的顺序与传入列表一致，
  /// 同时避免遗留已删除条目。
  Future<void> saveAll(List<PromptTemplate> templates) async {
    _database.connection.execute('BEGIN;');
    try {
      _database.connection.execute('DELETE FROM prompt_templates;');
      final stmt = _database.connection.prepare(
        'INSERT INTO prompt_templates (id, name, system_prompt, messages_json, updated_at) '
        'VALUES (?, ?, ?, ?, ?);',
      );
      for (final template in templates) {
        stmt.execute([
          template.id,
          template.name,
          template.systemPrompt,
          jsonEncode(template.messages.map((m) => m.toJson()).toList()),
          template.updatedAt.toIso8601String(),
        ]);
      }
      stmt.dispose();
      _database.connection.execute('COMMIT;');
    } catch (_) {
      _database.connection.execute('ROLLBACK;');
      rethrow;
    }
  }

  PromptTemplate _rowToTemplate(Map<String, dynamic> row) {
    final rawMessages = jsonDecode(row['messages_json'] as String) as List;
    return PromptTemplate(
      id: row['id'] as String,
      name: row['name'] as String,
      systemPrompt: row['system_prompt'] as String,
      messages: rawMessages
          .map(
            (item) =>
                PromptMessage.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
