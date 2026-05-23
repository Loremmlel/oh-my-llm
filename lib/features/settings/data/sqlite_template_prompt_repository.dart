import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/sqlite_entity_repository.dart';
import '../domain/models/template_prompt.dart';

final templatePromptRepository = SqliteEntityRepository<TemplatePrompt>(
  tableName: 'template_prompts',
  selectColumns: 'id, title, content, variables_json, updated_at',
  insertColumns: 'id, title, content, variables_json, updated_at',
  insertPlaceholders: '?, ?, ?, ?, ?',
  rowToEntity: (row) {
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
  },
  entityToValues: (tp) => [
    tp.id,
    tp.title,
    tp.content,
    jsonEncode(tp.variables.map((v) => v.toJson()).toList()),
    tp.updatedAt.toIso8601String(),
  ],
);

final templatePromptRepositoryProvider =
    Provider<SqliteEntityRepository<TemplatePrompt>>(
      (ref) => templatePromptRepository,
    );
