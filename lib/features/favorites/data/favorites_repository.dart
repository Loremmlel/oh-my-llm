import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database_provider.dart';
import '../domain/models/favorite.dart';
import 'sqlite_favorites_repository.dart';

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => SqliteFavoritesRepository(ref.watch(appDatabaseProvider)),
);

/// 收藏记录的读写仓库接口。
abstract interface class FavoritesRepository {
  /// 按收藏时间降序返回全部收藏记录，可选按收藏夹筛选。
  List<Favorite> loadAll({String? collectionId});

  /// 保存单条收藏（INSERT OR REPLACE）。
  void save(Favorite favorite);

  /// 删除指定收藏记录。
  void delete(String favoriteId);

  /// 将指定收藏移动到另一个收藏夹（null 表示未分类）。
  void moveToCollection(String favoriteId, String? collectionId);

  /// 更新指定收藏的自定义标题（null 表示清除自定义标题）。
  void updateTitle(String favoriteId, String? title);

  /// 检查指定助手消息内容是否已存在收藏。
  bool existsByAssistantContent(String assistantContent);
}
