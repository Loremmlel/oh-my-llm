import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database_provider.dart';
import '../../../core/persistence/has_id_and_updated_at.dart';
import '../../../core/persistence/sqlite_entity_repository.dart';

/// "全量加载 + 全量写入"模式的设置实体控制器基类。
///
/// 子类只需提供 [repository]，即可获得完整的列表加载、增删改和排序能力。
abstract class SettingsEntityController<T extends HasIdAndUpdatedAt>
    extends Notifier<List<T>> {
  SqliteEntityRepository<T> get repository;

  @override
  List<T> build() {
    return repository.loadAll(ref.read(appDatabaseProvider));
  }

  Future<void> upsert(T item) async {
    final items = [...state];
    final id = item.id;
    final existingIndex = items.indexWhere((i) => i.id == id);
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
      final id = item.id;
      final i = updated.indexWhere((e) => e.id == id);
      if (i == -1) {
        updated.add(item);
      } else {
        updated[i] = item;
      }
    }
    _commit(updated);
  }

  Future<void> deleteById(String id) async {
    _commit(state.where((i) => i.id != id).toList(growable: false));
  }

  /// 按 updatedAt 降序排列（最新在前）。
  Future<void> _commit(List<T> items) async {
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = List.unmodifiable(items);
    await repository.saveAll(ref.read(appDatabaseProvider), state);
  }
}
