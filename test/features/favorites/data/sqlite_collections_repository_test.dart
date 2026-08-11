import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';

void main() {
  late AppDatabase database;
  late SqliteCollectionsRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = SqliteCollectionsRepository(database);
  });

  tearDown(() {
    database.close();
  });

  group('SqliteCollectionsRepository', () {
    test('save/delete 生命周期：保存、按 id 更新、删除', () {
      final original = FavoriteCollection(
        id: 'col-1',
        name: '旧名称',
        createdAt: DateTime(2026, 1, 1),
      );

      repository.save(original);
      expect(repository.loadAll().single, original);

      repository.save(original.copyWith(name: '新名称'));
      expect(repository.loadAll().single.name, '新名称');

      repository.delete(original.id);
      expect(repository.loadAll(), isEmpty);
    });

    test('loadAll 按 created_at 升序排列', () {
      repository.save(
        FavoriteCollection(
          id: 'col-c',
          name: 'C',
          createdAt: DateTime(2026, 3, 1),
        ),
      );
      repository.save(
        FavoriteCollection(
          id: 'col-a',
          name: 'A',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      repository.save(
        FavoriteCollection(
          id: 'col-b',
          name: 'B',
          createdAt: DateTime(2026, 5, 1),
        ),
      );

      final ids = repository.loadAll().map((c) => c.id).toList();
      // ID 顺序不按字母排列，确保按 created_at 而非 ID 排序
      expect(ids, ['col-a', 'col-c', 'col-b']);
    });
  });
}
