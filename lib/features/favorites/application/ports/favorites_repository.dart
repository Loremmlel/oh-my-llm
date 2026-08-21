import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/favorite.dart';

/// 必须由 app composition 或测试显式绑定的收藏记录仓库。
final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  throw StateError('FavoritesRepository 尚未由应用组合层绑定');
});

/// 收藏记录的读写仓库接口。
abstract interface class FavoritesRepository {
  /// 按收藏时间降序返回全部收藏记录，可选按收藏夹筛选。
  ///
  /// [collectionId] 为 null 时返回全部；为空串时查询系统"未分类"收藏夹
  /// （旧扁平筛选契约的临时兼容，Task 10 随 FilterChip 路径一起删除）。
  List<Favorite> loadAll({String? collectionId});

  /// 按 ID 读取单条收藏；记录不存在时返回 null。
  Favorite? loadById(String favoriteId);

  /// 保存单条收藏（INSERT OR REPLACE）。
  void save(Favorite favorite);

  /// 删除指定收藏记录。
  void delete(String favoriteId);

  /// 将指定收藏移动到另一个收藏夹，并把归属时间更新为 [assignedAt]。
  ///
  /// 时间由调用方提供，repository 不读取系统时钟。
  void moveToCollection(
    String favoriteId,
    String collectionId, {
    required DateTime assignedAt,
  });

  /// 更新指定收藏的自定义标题（null 表示清除自定义标题）。
  void updateTitle(String favoriteId, String? title);

  /// 检查指定助手消息内容是否已存在收藏。
  bool existsByAssistantContent(String assistantContent);
}
