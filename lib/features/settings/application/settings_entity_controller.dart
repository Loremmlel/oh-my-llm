import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database_provider.dart';
import '../../../core/persistence/sqlite_entity_repository.dart';

/// "全量加载 + 全量写入"模式的设置实体控制器基类。
///
/// 子类只需提供 [repository]，即可获得完整的列表加载、增删改和排序能力。
abstract class SettingsEntityController<T extends Object>
    extends Notifier<List<T>> {
  SqliteEntityRepository<T> get repository;

  @override
  List<T> build() {
    return repository.loadAll(ref.read(appDatabaseProvider));
  }

  Future<void> upsert(T item) async {
    final items = [...state];
    final id = _idOf(item);
    final existingIndex = items.indexWhere((i) => _idOf(i) == id);
    if (existingIndex == -1) {
      items.add(item);
    } else {
      items[existingIndex] = item;
    }
    _commit(items);
  }

  Future<void> upsertAll(List<T> items) async {
    final updated = [...state];
    for (final item in items) {
      final id = _idOf(item);
      final i = updated.indexWhere((e) => _idOf(e) == id);
      if (i == -1) {
        updated.add(item);
      } else {
        updated[i] = item;
      }
    }
    _commit(updated);
  }

  Future<void> deleteById(String id) async {
    _commit(state.where((i) => _idOf(i) != id).toList(growable: false));
  }

  Future<void> _commit(List<T> items) async {
    items.sort((a, b) {
      final aTime = _updatedAtOf(b);
      final bTime = _updatedAtOf(a);
      return aTime.compareTo(bTime);
    });
    state = List.unmodifiable(items);
    await repository.saveAll(ref.read(appDatabaseProvider), state);
  }
}

/// 从实体上读取 id 字段，假定实体有 `String id` 属性。
String _idOf<T>(T entity) => (entity as dynamic).id as String;

/// 从实体上读取 updatedAt 字段，假定实体有 `DateTime updatedAt` 属性。
DateTime _updatedAtOf<T>(T entity) => (entity as dynamic).updatedAt as DateTime;
