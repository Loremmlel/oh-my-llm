import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';

import '../domain/models/collection.dart';
import '../domain/models/favorite_page.dart';
import 'favorites_controller.dart';
import 'ports/collections_repository.dart';
import 'ports/favorites_repository.dart';

/// 路由拥有的收藏分页查询参数。
typedef FavoritePageQuery = ({String collectionId, int page, int pageSize});

/// 一次成功查询的有效收藏夹与规范化分页窗口。
typedef FavoritePageWindow = ({
  FavoriteCollection effectiveCollection,
  int canonicalPage,
  int pageSize,
  FavoritePage page,
});

/// 查询失败时供页面展示的固定安全文案。
const favoriteLoadErrorMessage = '加载收藏失败';

/// 从 route query 和收藏库 revision 同步派生当前分页窗口。
final favoritePageWindowProvider =
    Provider.family<AsyncValue<FavoritePageWindow>, FavoritePageQuery>((
      ref,
      query,
    ) {
      ref.watch(favoritesLibraryProvider);
      try {
        final collections = ref.watch(collectionsRepositoryProvider).loadAll();
        final fallback = collections.firstWhere(
          (collection) =>
              collection.id ==
              AppReservedEntities.uncategorizedFavoriteCollectionId,
        );
        final effectiveCollection =
            collections
                .where((collection) => collection.id == query.collectionId)
                .firstOrNull ??
            fallback;
        final pageSize = appPageSizeOptions.contains(query.pageSize)
            ? query.pageSize
            : appDefaultPageSize;
        final requestedPage = effectiveCollection.id == query.collectionId
            ? (query.page < 1 ? 1 : query.page)
            : 1;
        final repository = ref.watch(favoritesRepositoryProvider);
        var page = repository.loadPage(
          collectionId: effectiveCollection.id,
          limit: pageSize,
          offset: (requestedPage - 1) * pageSize,
        );
        final canonicalPage = clampPageToValidRange(
          requestedPage,
          totalPagesForItems(page.totalItems, pageSize),
        );
        if (canonicalPage != requestedPage) {
          page = repository.loadPage(
            collectionId: effectiveCollection.id,
            limit: pageSize,
            offset: (canonicalPage - 1) * pageSize,
          );
        }

        return AsyncValue.data((
          effectiveCollection: effectiveCollection,
          canonicalPage: canonicalPage,
          pageSize: pageSize,
          page: page,
        ));
      } catch (_) {
        return AsyncValue.error(favoriteLoadErrorMessage, StackTrace.current);
      }
    });
