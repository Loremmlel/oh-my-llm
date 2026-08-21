import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'ports/favorites_repository.dart';
import '../domain/models/favorite.dart';

/// 收藏列表过滤条件。
///
/// null = 全部，'' = 未分类（临时兼容，repository 内映射到系统收藏夹），
/// 其他 = 指定收藏夹 ID。
final favoritesFilterProvider =
    NotifierProvider<FavoritesFilterNotifier, String?>(
      FavoritesFilterNotifier.new,
    );

/// 过滤条件状态管理。
class FavoritesFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// 切换过滤条件。
  void setFilter(String? filter) => state = filter;
}

/// 收藏列表 Provider（随过滤条件变化而重建）。
final favoritesProvider = NotifierProvider<FavoritesController, List<Favorite>>(
  FavoritesController.new,
);

/// 收藏列表管理控制器。
///
/// 维护当前过滤条件下的收藏列表，支持新增、删除和移动收藏夹。
class FavoritesController extends Notifier<List<Favorite>> {
  FavoritesRepository get _repo => ref.read(favoritesRepositoryProvider);

  @override
  List<Favorite> build() {
    final filter = ref.watch(favoritesFilterProvider);
    return _repo.loadAll(collectionId: filter);
  }

  /// 收藏一条模型回复。
  ///
  /// 返回新创建的收藏 ID。[collectionId] 为 null/空串时归入系统"未分类"
  /// 收藏夹（旧调用方尚未携带非空归属的临时兼容，Task 8 收紧 Chat
  /// interface 后删除该归一参数）。
  String add({
    required String userMessageContent,
    required String assistantContent,
    String assistantReasoningContent = '',
    String assistantModelDisplayName = '匿名模型',
    String? collectionId,
    String? sourceConversationId,
    String? sourceConversationTitle,
    String? sourceAssistantMessageId,
  }) {
    final createdAt = DateTime.now();
    final favorite = Favorite(
      id: generateEntityId(),
      collectionId: _resolveCollectionId(collectionId),
      // 新收藏的归属时间与收藏时间同刻落定。
      collectionAssignedAt: createdAt,
      userMessageContent: userMessageContent,
      assistantContent: assistantContent,
      assistantReasoningContent: assistantReasoningContent,
      assistantModelDisplayName: assistantModelDisplayName,
      sourceConversationId: sourceConversationId,
      sourceConversationTitle: sourceConversationTitle,
      sourceAssistantMessageId: sourceAssistantMessageId,
      createdAt: createdAt,
    );
    _repo.save(favorite);
    _refresh();
    return favorite.id;
  }

  /// 删除指定收藏记录。
  void remove(String favoriteId) {
    _repo.deleteMany({favoriteId});
    _refresh();
  }

  /// 将指定收藏移动到另一个收藏夹；null/空串归入系统"未分类"收藏夹，
  /// 归属时间更新为移动时刻（与 add 同样的临时兼容，Task 8 删除）。
  void moveTo(String favoriteId, String? collectionId) {
    _repo.moveMany(
      {favoriteId},
      targetCollectionId: _resolveCollectionId(collectionId),
      assignedAt: DateTime.now(),
    );
    _refresh();
  }

  /// 重命名指定收藏的标题（null 或空字符串表示清除自定义标题）。
  void rename(String favoriteId, String? title) {
    final normalized = (title == null || title.trim().isEmpty)
        ? null
        : title.trim();
    _repo.updateTitle(favoriteId, normalized);
    _refresh();
  }

  /// 检查指定助手消息内容是否已被收藏。
  bool isFavorited(String assistantContent) {
    return _repo.findByAssistantContent(assistantContent) != null;
  }

  /// 把旧调用方的 null/空串归属归一为系统"未分类"收藏夹 ID。
  String _resolveCollectionId(String? collectionId) {
    if (collectionId == null || collectionId.isEmpty) {
      return AppReservedEntities.uncategorizedFavoriteCollectionId;
    }
    return collectionId;
  }

  void _refresh() {
    final filter = ref.read(favoritesFilterProvider);
    state = _repo.loadAll(collectionId: filter);
  }
}

/// 按 ID 读取单条收藏。
///
/// 与 filtered 列表解耦：详情页不依赖当前筛选是否包含该 ID。
/// [favoritesProvider] 仅作为 add/remove/move/rename 的失效信号，
/// 真实数据始终来自 repository 精确查询。
final favoriteByIdProvider = Provider.family<Favorite?, String>((ref, id) {
  ref.watch(favoritesProvider);
  return ref.watch(favoritesRepositoryProvider).loadById(id);
});
