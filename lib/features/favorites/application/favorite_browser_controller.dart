import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';

import 'favorites_browse_preferences_controller.dart';
import 'favorites_controller.dart';
import 'ports/collections_repository.dart';
import 'ports/favorites_repository.dart';
import '../domain/models/favorite.dart';

/// 收藏夹分页浏览窗口状态。
///
/// route 是 collectionId/page/pageSize 的唯一 writer；本状态只缓存
/// 当前 route query 的加载结果，不提供独立的页码/收藏夹切换状态机。
class FavoriteBrowserState extends Equatable {
  const FavoriteBrowserState({
    this.collectionId = AppReservedEntities.uncategorizedFavoriteCollectionId,
    this.page = 1,
    this.pageSize = appDefaultPageSize,
    this.items = const [],
    this.totalItems = 0,
    this.isBusy = false,
    this.isInitialized = false,
    this.errorMessage,
  });

  /// 当前浏览的收藏夹 ID。
  final String collectionId;

  /// 当前页码（从 1 开始，按真实总数夹取）。
  final int page;

  /// 当前每页容量。
  final int pageSize;

  /// 当前页条目。
  final List<Favorite> items;

  /// 过滤条件下的总条数。
  final int totalItems;

  /// 查询进行中。
  final bool isBusy;

  /// 是否完成过首次 route 加载。
  final bool isInitialized;

  /// 查询失败文案；非 null 时保留旧内容供 UI 呈现。
  final String? errorMessage;

  FavoriteBrowserState copyWith({
    String? collectionId,
    int? page,
    int? pageSize,
    List<Favorite>? items,
    int? totalItems,
    bool? isBusy,
    bool? isInitialized,
    Object? errorMessage = _unset,
  }) {
    return FavoriteBrowserState(
      collectionId: collectionId ?? this.collectionId,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      items: items ?? this.items,
      totalItems: totalItems ?? this.totalItems,
      isBusy: isBusy ?? this.isBusy,
      isInitialized: isInitialized ?? this.isInitialized,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    collectionId,
    page,
    pageSize,
    items,
    totalItems,
    isBusy,
    isInitialized,
    errorMessage,
  ];
}

const Object _unset = Object();

/// 收藏夹分页浏览器：加载传入的不可变 route query 并跟随 revision 刷新。
///
/// - [FavoriteBrowserController.loadRoute] 是窗口参数的唯一入口；
/// - mutation 成功（revision 变化）后按当前 query 重查并补齐当前页，
///   浏览中的收藏夹被删除时回退系统"未分类"；
/// - 查询失败保留旧窗口内容并把错误写入 state。
class FavoriteBrowserController extends Notifier<FavoriteBrowserState> {
  @override
  FavoriteBrowserState build() {
    ref.listen(favoritesLibraryProvider, (_, _) => _refresh());
    return const FavoriteBrowserState();
  }

  FavoritesRepository get _repo => ref.read(favoritesRepositoryProvider);

  /// 按 route 参数加载收藏夹窗口。
  ///
  /// [pageSize] 仅接受 [appPageSizeOptions]；合法显式值回写偏好，
  /// 非法或缺省使用持久化偏好。[page] 缺省视为 1。
  void loadRoute({String? collectionId, int? page, int? pageSize}) {
    final resolvedCollectionId = collectionId ?? state.collectionId;
    int resolvedPageSize;
    if (pageSize != null && appPageSizeOptions.contains(pageSize)) {
      resolvedPageSize = pageSize;
      ref.read(favoritesBrowsePageSizeProvider.notifier).save(pageSize);
    } else {
      resolvedPageSize = ref.read(favoritesBrowsePageSizeProvider);
    }
    state = state.copyWith(collectionId: resolvedCollectionId, isBusy: true);
    _load(
      resolvedCollectionId,
      requestedPage: page ?? 1,
      pageSize: resolvedPageSize,
    );
  }

  /// 翻到指定页；页码乐观写入 state，查询失败时保留目标页码与旧内容，
  /// 由 UI 呈现错误并通过 [retry] 重查同一窗口。越界由 [_load] 归一。
  void goToPage(int page) {
    if (page == state.page && state.isInitialized) return;
    state = state.copyWith(page: page, isBusy: true);
    _load(state.collectionId, requestedPage: page, pageSize: state.pageSize);
  }

  /// 切换每页容量并回到第 1 页；合法容量同步持久化偏好。
  void setPageSize(int pageSize) {
    if (!appPageSizeOptions.contains(pageSize)) return;
    if (pageSize == state.pageSize && state.isInitialized) return;
    ref.read(favoritesBrowsePageSizeProvider.notifier).save(pageSize);
    state = state.copyWith(pageSize: pageSize, page: 1, isBusy: true);
    _load(state.collectionId, requestedPage: 1, pageSize: pageSize);
  }

  /// 按当前窗口参数重试上次失败的查询。
  void retry() {
    state = state.copyWith(isBusy: true);
    _load(
      state.collectionId,
      requestedPage: state.page,
      pageSize: state.pageSize,
    );
  }

  /// revision 变化后的刷新：按当前窗口重查，修正归属失效与页码越界。
  void _refresh() {
    if (!state.isInitialized || state.isBusy) return;

    var targetCollectionId = state.collectionId;
    var targetPage = state.page;
    try {
      // 浏览中的收藏夹可能已被删除：application 层不留孤儿 ID，回退系统夹。
      final collectionExists = ref
          .read(collectionsRepositoryProvider)
          .loadAll()
          .any((c) => c.id == targetCollectionId);
      if (!collectionExists) {
        targetCollectionId =
            AppReservedEntities.uncategorizedFavoriteCollectionId;
        targetPage = 1;
        state = state.copyWith(collectionId: targetCollectionId, isBusy: true);
      }
    } catch (_) {
      // 存在性检查自身失败（如存储不可用）：仍按旧窗口尝试加载，
      // 失败结果由 _load 的 catch 落定为 stale 内容 + 错误信息。
    }

    _load(
      targetCollectionId,
      requestedPage: targetPage,
      pageSize: state.pageSize,
    );
  }

  void _load(
    String collectionId, {
    required int requestedPage,
    required int pageSize,
  }) {
    try {
      var result = _repo.loadPage(
        collectionId: collectionId,
        limit: pageSize,
        offset: (requestedPage - 1) * pageSize,
      );
      var targetPage = requestedPage;
      // 页码越界（数据被删导致末页消失）时回退最后一页补齐内容。
      final totalPages = totalPagesForItems(result.totalItems, pageSize);
      if (result.items.isEmpty &&
          result.totalItems > 0 &&
          requestedPage > totalPages) {
        targetPage = totalPages;
        result = _repo.loadPage(
          collectionId: collectionId,
          limit: pageSize,
          offset: (targetPage - 1) * pageSize,
        );
      }

      state = state.copyWith(
        page: targetPage,
        pageSize: pageSize,
        items: result.items,
        totalItems: result.totalItems,
        isBusy: false,
        isInitialized: true,
        errorMessage: null,
      );
    } catch (_) {
      // 查询失败：保留旧窗口内容（stale content），错误进入状态由 UI 呈现。
      state = state.copyWith(
        isBusy: false,
        isInitialized: true,
        errorMessage: favoriteLoadErrorMessage,
      );
    }
  }
}

/// 查询失败时的通用错误文案。
const favoriteLoadErrorMessage = '加载收藏失败';

/// 收藏夹分页浏览 provider。
final favoriteBrowserProvider =
    NotifierProvider<FavoriteBrowserController, FavoriteBrowserState>(
      FavoriteBrowserController.new,
    );
