import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';

import 'favorites_browse_preferences_controller.dart';
import 'favorites_clock_provider.dart';
import 'ports/collections_repository.dart';
import 'ports/favorites_repository.dart';
import '../domain/models/collection.dart';
import '../domain/models/collection_delete_request.dart';
import '../domain/models/favorite.dart';

/// 收藏库 mutation 控制器；state 是全局 revision。
///
/// 独占全部收藏库写操作（add/remove/rename/move/bulk/delete-collection/
/// create/rename-collection），每次成功 mutation 后递增 revision；
/// by-ID、summaries、分页窗口与 Chat adapter 都 watch 该 revision
/// 建立失效依赖。操作失败（repository 抛出）时 revision 不变。
class FavoritesLibraryController extends Notifier<int> {
  @override
  int build() => 0;

  FavoritesRepository get _repo => ref.read(favoritesRepositoryProvider);
  CollectionsRepository get _collectionsRepo =>
      ref.read(collectionsRepositoryProvider);

  DateTime get _now => ref.read(favoritesClockProvider)();

  /// 收藏一条模型回复到 [collectionId]（必填非空）。
  ///
  /// 返回新创建的收藏 ID；成功后记录最近归类目标。
  String add({
    required String userMessageContent,
    required String assistantContent,
    String assistantReasoningContent = '',
    String assistantModelDisplayName = '匿名模型',
    required String collectionId,
    String? sourceConversationId,
    String? sourceConversationTitle,
    String? sourceAssistantMessageId,
  }) {
    final now = _now;
    final favorite = Favorite(
      id: generateEntityId(),
      collectionId: collectionId,
      collectionAssignedAt: now,
      userMessageContent: userMessageContent,
      assistantContent: assistantContent,
      assistantReasoningContent: assistantReasoningContent,
      assistantModelDisplayName: assistantModelDisplayName,
      sourceConversationId: sourceConversationId,
      sourceConversationTitle: sourceConversationTitle,
      sourceAssistantMessageId: sourceAssistantMessageId,
      createdAt: now,
    );
    _repo.save(favorite);
    ref.read(favoritesLastCollectionProvider.notifier).update(collectionId);
    state++;
    return favorite.id;
  }

  /// 删除单条收藏。
  void remove(String favoriteId) => deleteMany({favoriteId});

  /// 批量删除收藏。
  void deleteMany(Set<String> favoriteIds) {
    if (favoriteIds.isEmpty) return;
    _repo.deleteMany(favoriteIds);
    state++;
  }

  /// 批量移动收藏到目标收藏夹；成功后记录最近归类目标。
  void moveMany(Set<String> favoriteIds, {required String targetCollectionId}) {
    if (favoriteIds.isEmpty) return;
    _repo.moveMany(
      favoriteIds,
      targetCollectionId: targetCollectionId,
      assignedAt: _now,
    );
    ref
        .read(favoritesLastCollectionProvider.notifier)
        .update(targetCollectionId);
    state++;
  }

  /// 重命名指定收藏的标题（null 或空字符串表示清除自定义标题）。
  void rename(String favoriteId, String? title) {
    final normalized = (title == null || title.trim().isEmpty)
        ? null
        : title.trim();
    _repo.updateTitle(favoriteId, normalized);
    state++;
  }

  /// 新建收藏夹并返回其 ID；保留名"未分类"被拒绝并归位系统夹。
  String createCollection(String name) {
    final trimmed = name.trim();
    if (_isReservedName(trimmed)) {
      return AppReservedEntities.uncategorizedFavoriteCollectionId;
    }
    final collection = FavoriteCollection(
      id: generateEntityId(),
      name: trimmed,
      createdAt: _now,
    );
    _collectionsRepo.save(collection);
    state++;
    return collection.id;
  }

  /// 重命名指定收藏夹；系统夹与保留名不生效。
  void renameCollection(String collectionId, String newName) {
    if (collectionId == AppReservedEntities.uncategorizedFavoriteCollectionId ||
        _isReservedName(newName.trim())) {
      return;
    }
    final existing = _collectionsRepo
        .loadAll()
        .where((c) => c.id == collectionId)
        .firstOrNull;
    if (existing == null) return;
    _collectionsRepo.save(existing.copyWith(name: newName.trim()));
    state++;
  }

  /// 删除普通收藏夹；未指定去向时把内容移入系统"未分类"。
  ///
  /// [disposition] 决定夹内收藏的去向：移动到指定收藏夹，或随收藏夹一并
  /// 删除。成功后若最近归类指向被删夹则回退系统夹。
  void deleteCollection(
    String collectionId, {
    CollectionDeleteRequest? disposition,
  }) {
    if (collectionId == AppReservedEntities.uncategorizedFavoriteCollectionId) {
      return;
    }
    _collectionsRepo.delete(
      collectionId,
      disposition:
          disposition ??
          CollectionDeleteRequest.moveItemsTo(
            targetCollectionId:
                AppReservedEntities.uncategorizedFavoriteCollectionId,
            assignedAt: _now,
          ),
    );
    final lastCollection = ref.read(favoritesLastCollectionProvider);
    if (lastCollection == collectionId) {
      ref
          .read(favoritesLastCollectionProvider.notifier)
          .update(AppReservedEntities.uncategorizedFavoriteCollectionId);
    }
    state++;
  }

  bool _isReservedName(String trimmedName) {
    return trimmedName ==
        AppReservedEntities.uncategorizedFavoriteCollectionName;
  }
}

/// 收藏库全局 revision provider：query readers 的失效信号。
final favoritesLibraryProvider =
    NotifierProvider<FavoritesLibraryController, int>(
      FavoritesLibraryController.new,
    );

/// 按 ID 读取单条收藏。
///
/// watch revision 失效：任何成功 mutation 后重读 repository 精确查询，
/// 与 filtered 列表解耦——详情页不依赖当前筛选是否包含该 ID。
final favoriteByIdProvider = Provider.family<Favorite?, String>((ref, id) {
  ref.watch(favoritesLibraryProvider);
  return ref.watch(favoritesRepositoryProvider).loadById(id);
});
