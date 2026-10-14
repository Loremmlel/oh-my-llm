import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/persistence/sqlite_entity_repository.dart';

import '../../domain/models/worldbooks/world_book.dart';
import '../prompts/settings_entity_controller.dart';

final worldBooksProvider =
    NotifierProvider<WorldBooksController, List<WorldBook>>(
      WorldBooksController.new,
    );

final worldBookRepositoryProvider = Provider<SqliteEntityRepository<WorldBook>>(
  (_) => throw StateError('世界书仓库尚未由应用组合层绑定'),
);

class WorldBooksController extends SettingsEntityController<WorldBook> {
  @override
  SqliteEntityRepository<WorldBook> get repository =>
      ref.read(worldBookRepositoryProvider);
}

/// 删除的世界书不再注入；保留会话中的引用，便于明确显示缺失状态。
WorldBook? resolveWorldBook(List<WorldBook> books, String? id) =>
    books.where((book) => book.id == id).firstOrNull;
