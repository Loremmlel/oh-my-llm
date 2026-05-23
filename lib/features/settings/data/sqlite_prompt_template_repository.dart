import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/sqlite_entity_repository.dart';
import '../domain/models/prompt_template.dart';

final promptTemplateRepository = SqliteEntityRepository<PromptTemplate>(
  tableName: 'prompt_templates',
  selectColumns: 'id, name, system_prompt, messages_json, updated_at',
  insertColumns: 'id, name, system_prompt, messages_json, updated_at',
  insertPlaceholders: '?, ?, ?, ?, ?',
  rowToEntity: (row) {
    final rawMessages = jsonDecode(row['messages_json'] as String) as List;
    final messages = rawMessages
        .map(
          (item) =>
              PromptMessage.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
    final hasSystemMessages = messages.any(
      (message) => message.role == PromptMessageRole.system,
    );

    List<PromptMessage> effectiveMessages = messages;
    if (!hasSystemMessages) {
      final legacyPrompt = (row['system_prompt'] as String?)?.trim() ?? '';
      if (legacyPrompt.isNotEmpty) {
        effectiveMessages = [
          PromptMessage(
            id: '_legacy-system-message',
            role: PromptMessageRole.system,
            title: defaultSystemPromptTitle,
            content: legacyPrompt,
            placement: PromptMessagePlacement.before,
          ),
          ...messages,
        ];
      }
    }

    return PromptTemplate(
      id: row['id'] as String,
      name: row['name'] as String,
      messages: effectiveMessages,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  },
  entityToValues: (t) => [
    t.id,
    t.name,
    '',
    jsonEncode(t.messages.map((m) => m.toJson()).toList()),
    t.updatedAt.toIso8601String(),
  ],
);

final promptTemplateRepositoryProvider =
    Provider<SqliteEntityRepository<PromptTemplate>>(
      (ref) => promptTemplateRepository,
    );
