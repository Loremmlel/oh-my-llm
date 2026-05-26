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
    test('save 后 loadAll 返回该收藏夹', () {
      final collection = FavoriteCollection(
        id: 'col-1',
        name: '技术笔记',
        createdAt: DateTime(2026, 1, 1),
      );
      repository.save(collection);

      final result = repository.loadAll();
      expect(result, hasLength(1));
      expect(result.first.id, 'col-1');
      expect(result.first.name, '技术笔记');
      expect(result.first.createdAt, DateTime(2026, 1, 1));
    });

    test('save 重复 id 执行 REPLACE（更新名称）', () {
      final original = FavoriteCollection(
        id: 'col-1',
        name: '旧名称',
        createdAt: DateTime(2026, 1, 1),
      );
      repository.save(original);

      final updated = original.copyWith(name: '新名称');
      repository.save(updated);

      final result = repository.loadAll();
      expect(result, hasLength(1));
      expect(result.first.name, '新名称');
    });

    test('loadAll 按 created_at 升序排列', () {
      repository.save(
        FavoriteCollection(
          id: 'col-b',
          name: 'B',
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
          id: 'col-c',
          name: 'C',
          createdAt: DateTime(2026, 5, 1),
        ),
      );

      final ids = repository.loadAll().map((c) => c.id).toList();
      expect(ids, ['col-a', 'col-b', 'col-c']);
    });

    test('delete 后收藏夹不再出现', () {
      repository.save(
        FavoriteCollection(
          id: 'col-1',
          name: '测试',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      repository.delete('col-1');

      expect(repository.loadAll(), isEmpty);
    });

  });
}
