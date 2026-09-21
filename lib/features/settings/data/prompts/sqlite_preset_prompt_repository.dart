import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/sqlite_entity_repository.dart';

import '../../domain/models/prompts/preset_prompt.dart';

final presetPromptRepository = SqliteEntityRepository<PresetPrompt>(
  tableName: 'preset_prompts',
  selectColumns: 'id, name, messages_json, updated_at, syntax',
  insertColumns: 'id, name, messages_json, updated_at, syntax',
  insertPlaceholders: '?, ?, ?, ?, ?',
  rowToEntity: (row) {
    final rawMessages = jsonDecode(row['messages_json'] as String) as List;
    final messages = rawMessages
        .map(
          (item) =>
              PromptMessage.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);

    return PresetPrompt(
      id: row['id'] as String,
      name: row['name'] as String,
      syntax: PresetPromptSyntax.fromJson(row['syntax']),
      messages: messages,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  },
  entityToValues: (t) => [
    t.id,
    t.name,
    jsonEncode(t.messages.map((m) => m.toJson()).toList()),
    t.updatedAt.toIso8601String(),
    t.syntax.name,
  ],
);

final presetPromptRepositoryProvider =
    Provider<SqliteEntityRepository<PresetPrompt>>(
      (ref) => presetPromptRepository,
    );
