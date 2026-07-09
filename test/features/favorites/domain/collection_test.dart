import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';

void main() {
  group('FavoriteCollection', () {
    test('copyWith 覆盖指定字段', () {
      final original = FavoriteCollection(
        id: 'c1',
        name: '旧名',
        createdAt: DateTime(2026),
      );
      final copied = original.copyWith(name: '新名');
      expect(copied.id, 'c1');
      expect(copied.name, '新名');
      expect(copied.createdAt, DateTime(2026));
    });

    test('Equatable 相等性', () {
      final a = FavoriteCollection(
        id: 'c1',
        name: '笔记',
        createdAt: DateTime(2026, 1, 1),
      );
      final b = FavoriteCollection(
        id: 'c1',
        name: '笔记',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('Equatable 不等性', () {
      final a = FavoriteCollection(
        id: 'c1',
        name: '笔记',
        createdAt: DateTime(2026, 1, 1),
      );
      final b = FavoriteCollection(
        id: 'c1',
        name: '其他',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
