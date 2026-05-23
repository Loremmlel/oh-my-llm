import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/sqlite_entity_repository.dart';
import '../domain/models/memory_prompt.dart';

final memoryPromptRepository = SqliteEntityRepository<MemoryPrompt>(
  tableName: 'memory_prompts',
  selectColumns: 'id, name, content, updated_at',
  insertColumns: 'id, name, content, updated_at',
  insertPlaceholders: '?, ?, ?, ?',
  rowToEntity: (row) => MemoryPrompt(
    id: row['id'] as String,
    name: row['name'] as String,
    content: row['content'] as String,
    updatedAt: DateTime.parse(row['updated_at'] as String),
  ),
  entityToValues: (mp) => [
    mp.id,
    mp.name,
    mp.content,
    mp.updatedAt.toIso8601String(),
  ],
);

final memoryPromptRepositoryProvider =
    Provider<SqliteEntityRepository<MemoryPrompt>>(
      (ref) => memoryPromptRepository,
    );
