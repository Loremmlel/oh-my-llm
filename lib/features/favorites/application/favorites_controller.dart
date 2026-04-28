import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/id_generator.dart';
import '../data/sqlite_favorites_repository.dart';
import '../domain/models/favorite.dart';

/// 收藏列表过滤条件 Notifier。
///
/// null = 全部，'' = 未分类，其他 = 指定收藏夹 ID。
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
final favoritesProvider =
    NotifierProvider<FavoritesController, List<Favorite>>(
      FavoritesController.new,
    );

/// 收藏列表管理控制器。
///
/// 维护当前过滤条件下的收藏列表，支持新增、删除和移动收藏夹。
class FavoritesController extends Notifier<List<Favorite>> {
  SqliteFavoritesRepository get _repo =>
      ref.read(favoritesRepositoryProvider);

  @override
  List<Favorite> build() {
    final filter = ref.watch(favoritesFilterProvider);
    return _repo.loadAll(collectionId: filter);
  }

  /// 收藏一条模型回复。
  ///
  /// 返回新创建的收藏 ID。
  String add({
    required String userMessageContent,
    required String assistantContent,
    String assistantReasoningContent = '',
    String? collectionId,
    String? sourceConversationId,
    String? sourceConversationTitle,
  }) {
    final favorite = Favorite(
      id: generateEntityId(),
      collectionId: collectionId,
      userMessageContent: userMessageContent,
      assistantContent: assistantContent,
      assistantReasoningContent: assistantReasoningContent,
      sourceConversationId: sourceConversationId,
      sourceConversationTitle: sourceConversationTitle,
      createdAt: DateTime.now(),
    );
    _repo.save(favorite);
    _refresh();
    return favorite.id;
  }

  /// 删除指定收藏记录。
  void remove(String favoriteId) {
    _repo.delete(favoriteId);
    _refresh();
  }

  /// 将指定收藏移动到另一个收藏夹（null 表示未分类）。
  void moveTo(String favoriteId, String? collectionId) {
    _repo.moveToCollection(favoriteId, collectionId);
    _refresh();
  }

  /// 检查指定助手消息内容是否已被收藏。
  bool isFavorited(String assistantContent) {
    return _repo.existsByAssistantContent(assistantContent);
  }

  void _refresh() {
    final filter = ref.read(favoritesFilterProvider);
    state = _repo.loadAll(collectionId: filter);
  }
}
