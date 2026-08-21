import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'favorites_controller.dart';
import 'ports/collections_repository.dart';
import '../domain/models/collection.dart';
import '../domain/models/favorite_collection_summary.dart';

/// 收藏夹卡片投影列表（query reader）。
///
/// watch revision：任何成功 mutation 后重读 repository；系统"未分类"
/// 恒置顶，普通夹按名称稳定排序。
final collectionsSummariesProvider =
    NotifierProvider<
      CollectionsSummariesController,
      List<FavoriteCollectionSummary>
    >(CollectionsSummariesController.new);

/// summaries 的只读投影控制器；state 完全由 repository 派生。
class CollectionsSummariesController
    extends Notifier<List<FavoriteCollectionSummary>> {
  @override
  List<FavoriteCollectionSummary> build() {
    ref.watch(favoritesLibraryProvider);
    return ref.watch(collectionsRepositoryProvider).loadSummaries();
  }
}

/// 选择器用的收藏夹列表（query reader）：排序同 [collectionsSummariesProvider]，
/// 并过滤历史残留的名为"未分类"的普通行——系统行已承担该语义，
/// 保证"未分类"对 UI 只出现一次（Task 9 以收藏夹网格替换旧 UI）。
final collectionsProvider = Provider<List<FavoriteCollection>>((ref) {
  ref.watch(favoritesLibraryProvider);
  final all = ref.watch(collectionsRepositoryProvider).loadAll();
  return all
      .where(
        (c) =>
            c.isSystem ||
            c.name.trim() !=
                AppReservedEntities.uncategorizedFavoriteCollectionName,
      )
      .toList(growable: false);
});
