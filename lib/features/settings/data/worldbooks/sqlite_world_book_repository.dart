import 'dart:convert';

import 'package:oh_my_llm/core/persistence/sqlite_entity_repository.dart';

import '../../domain/models/worldbooks/world_book.dart';

final worldBookRepository = SqliteEntityRepository<WorldBook>(
  tableName: 'world_books',
  selectColumns: 'id, name, entries_json, updated_at',
  insertColumns: 'id, name, entries_json, updated_at',
  insertPlaceholders: '?, ?, ?, ?',
  rowToEntity: (row) => WorldBook.fromJson({
    'id': row['id'],
    'name': row['name'],
    'entries': jsonDecode(row['entries_json'] as String),
    'updatedAt': row['updated_at'],
  }),
  entityToValues: (book) => [
    book.id,
    book.name,
    jsonEncode(book.entries.map((entry) => entry.toJson()).toList()),
    book.updatedAt.toIso8601String(),
  ],
);
