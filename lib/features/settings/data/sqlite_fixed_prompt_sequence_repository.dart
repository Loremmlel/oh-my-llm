import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/sqlite_entity_repository.dart';
import '../domain/models/fixed_prompt_sequence.dart';

final fixedPromptSequenceRepository = SqliteEntityRepository<FixedPromptSequence>(
  tableName: 'fixed_prompt_sequences',
  selectColumns: 'id, name, steps_json, updated_at',
  insertColumns: 'id, name, steps_json, updated_at',
  insertPlaceholders: '?, ?, ?, ?',
  rowToEntity: (row) {
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
  },
  entityToValues: (seq) => [
    seq.id,
    seq.name,
    jsonEncode(seq.steps.map((s) => s.toJson()).toList()),
    seq.updatedAt.toIso8601String(),
  ],
);

final fixedPromptSequenceRepositoryProvider =
    Provider<SqliteEntityRepository<FixedPromptSequence>>(
      (ref) => fixedPromptSequenceRepository,
    );
