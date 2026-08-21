import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/favorite.dart';
import '../../domain/models/favorite_page.dart';

/// 必须由 app composition 或测试显式绑定的收藏记录仓库。
final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  throw StateError('FavoritesRepository 尚未由应用组合层绑定');
});

/// 收藏记录的读写仓库接口。
abstract interface class FavoritesRepository {
  /// 按收藏时间降序返回全部收藏记录。
  List<Favorite> loadAll();

  /// 加载指定收藏夹的一页收藏，按 created_at DESC, id DESC 稳定排序。
  ///
  /// count 与 page 由本方法一次返回；[limit] 必须 > 0、[offset] 必须 >= 0、
  /// [collectionId] 必须非空，非法输入抛 ArgumentError。
  FavoritePage loadPage({
    required String collectionId,
    required int limit,
    required int offset,
  });

  /// 按 ID 读取单条收藏；记录不存在时返回 null。
  Favorite? loadById(String favoriteId);

  /// 按 assistant 内容精确查找收藏；不存在返回 null。
  Favorite? findByAssistantContent(String assistantContent);

  /// 批量查询输入集合中哪些 assistant 内容已被收藏。
  ///
  /// 只返回请求集合的子集；空输入直接返回空集合，不生成 IN ()。
  Set<String> loadFavoritedAssistantContents(
    Iterable<String> assistantContents,
  );

  /// 保存单条收藏（INSERT OR REPLACE）。
  void save(Favorite favorite);

  /// 批量删除收藏，返回受影响数量；空集合 no-op 返回 0。
  int deleteMany(Set<String> favoriteIds);

  /// 批量移动收藏到目标收藏夹并统一更新归属时间，返回受影响数量。
  ///
  /// [assignedAt] 由调用方提供，repository 不读取系统时钟；
  /// 空集合 no-op 返回 0；目标不存在时被外键拒绝。
  int moveMany(
    Set<String> favoriteIds, {
    required String targetCollectionId,
    required DateTime assignedAt,
  });

  /// 更新指定收藏的自定义标题（null 表示清除自定义标题）。
  void updateTitle(String favoriteId, String? title);
}
