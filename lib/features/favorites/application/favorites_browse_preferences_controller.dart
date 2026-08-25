import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';
import 'ports/collections_repository.dart';

/// 收藏浏览的每页容量偏好 key；与 History 的偏好互不共用。
const favoritesPageSizeStorageKey = 'app.feature.favorites.page_size';

/// 最近归类收藏夹 ID 偏好 key。
const favoritesLastCollectionStorageKey =
    'app.feature.favorites.last_collection_id';

/// 每页容量偏好控制器；仅接受 [appPageSizeOptions]，非法值回退默认。
class FavoritesBrowsePageSizeController extends Notifier<int> {
  @override
  int build() {
    final stored = ref
        .read(sharedPreferencesProvider)
        .getString(favoritesPageSizeStorageKey);
    final parsed = stored == null ? null : int.tryParse(stored);
    // 非法持久化值回退默认容量，不静默保留。
    return parsed != null && appPageSizeOptions.contains(parsed)
        ? parsed
        : appDefaultPageSize;
  }

  /// 保存每页容量；非法值直接忽略，写失败仅保留内存选择不阻塞浏览。
  void save(int pageSize) {
    if (!appPageSizeOptions.contains(pageSize)) return;
    state = pageSize;
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(favoritesPageSizeStorageKey, '$pageSize'),
    );
  }
}

final favoritesBrowsePageSizeProvider =
    NotifierProvider<FavoritesBrowsePageSizeController, int>(
      FavoritesBrowsePageSizeController.new,
    );

/// 最近归类收藏夹 ID 控制器。
///
/// 读取时校验持久化值对应的收藏夹仍然存在，失效回退系统"未分类"并
/// 修正持久化值；成功归类/删除收藏夹由 mutation controller 调用 [update]。
class FavoritesLastCollectionController extends Notifier<String> {
  @override
  String build() {
    final stored = ref
        .read(sharedPreferencesProvider)
        .getString(favoritesLastCollectionStorageKey);
    final exists = stored != null && _collectionExists(stored);
    if (stored != null && !exists) {
      // 失效值立即修正为系统夹，避免下次读取重复走失效路径。
      unawaited(
        ref
            .read(sharedPreferencesProvider)
            .setString(
              favoritesLastCollectionStorageKey,
              AppReservedEntities.uncategorizedFavoriteCollectionId,
            ),
      );
    }
    return exists
        ? stored
        : AppReservedEntities.uncategorizedFavoriteCollectionId;
  }

  /// 记录最近归类目标；系统收藏夹也是合法目标。
  void update(String collectionId) {
    state = collectionId;
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(favoritesLastCollectionStorageKey, collectionId),
    );
  }

  bool _collectionExists(String collectionId) {
    return ref
        .read(collectionsRepositoryProvider)
        .loadAll()
        .any((c) => c.id == collectionId);
  }
}

final favoritesLastCollectionProvider =
    NotifierProvider<FavoritesLastCollectionController, String>(
      FavoritesLastCollectionController.new,
    );
