import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/persistence/app_database_provider.dart';
import '../../../core/persistence/sqlite_replace_all.dart';
import '../domain/models/template_prompt.dart';

/// 模板提示词的 SQLite 仓库 Provider。
final templatePromptRepositoryProvider =
    Provider<SqliteTemplatePromptRepository>(
      (ref) => SqliteTemplatePromptRepository(ref.watch(appDatabaseProvider)),
    );

/// 模板提示词的 SQLite 读写仓库。
class SqliteTemplatePromptRepository {
  const SqliteTemplatePromptRepository(this._database);

  final AppDatabase _database;

  /// 按更新时间降序返回全部模板提示词。
  List<TemplatePrompt> loadAll() {
    final rows = _database.connection.select(
      'SELECT id, title, content, variables_json, updated_at '
      'FROM template_prompts '
      'ORDER BY updated_at DESC;',
    );

    return rows.map(_rowToTemplatePrompt).toList(growable: false);
  }

  /// 以事务方式将 [templatePrompts] 全量写入数据库（先清空再插入）。
  Future<void> saveAll(List<TemplatePrompt> templatePrompts) async {
    replaceAllRowsInTable(
      connection: _database.connection,
      deleteSql: 'DELETE FROM template_prompts;',
      insertSql:
          'INSERT INTO template_prompts (id, title, content, variables_json, updated_at) '
          'VALUES (?, ?, ?, ?, ?);',
      items: templatePrompts,
      buildValues: (templatePrompt) => [
        templatePrompt.id,
        templatePrompt.title,
        templatePrompt.content,
        jsonEncode(
          templatePrompt.variables
              .map((variable) => variable.toJson())
              .toList(),
        ),
        templatePrompt.updatedAt.toIso8601String(),
      ],
    );
  }

  TemplatePrompt _rowToTemplatePrompt(Map<String, dynamic> row) {
    final rawVariables = jsonDecode(row['variables_json'] as String) as List;
    return TemplatePrompt(
      id: row['id'] as String,
      title: row['title'] as String,
      content: row['content'] as String,
      variables: rawVariables
          .map(
            (item) => TemplatePromptVariable.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
