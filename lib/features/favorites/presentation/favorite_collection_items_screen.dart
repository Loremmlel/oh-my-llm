import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/widgets/app_empty_state.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_paginated_list_shell.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';

import '../application/collections_controller.dart';
import '../application/favorite_page_window_provider.dart';
import '../application/favorites_browse_preferences_controller.dart';
import '../application/favorites_controller.dart';
import '../domain/models/favorite.dart';
import 'widgets/dialogs/delete_collection_dialog.dart';
import 'widgets/dialogs/move_favorites_dialog.dart';
import 'widgets/favorite_list_item.dart';
import 'widgets/favorite_selection_toolbar.dart';

/// 收藏夹内容页：真实分页浏览单个收藏夹内的收藏，支持多选移动与删除。
///
/// route 是 collectionId/page/pageSize 的唯一 writer；页面直接用 route tuple
/// 查询当前窗口，翻页与容量变化只 replace URL，保持深链可恢复。
class FavoriteCollectionItemsScreen extends ConsumerStatefulWidget {
  const FavoriteCollectionItemsScreen({
    required this.routeCollectionId,
    this.routePage,
    this.routePageSize,
    super.key,
  });

  /// 路径中的收藏夹 ID。
  final String? routeCollectionId;

  /// query 中的页码；缺省回退第 1 页。
  final int? routePage;

  /// query 中的容量；非法或缺省回退持久化偏好。
  final int? routePageSize;

  @override
  ConsumerState<FavoriteCollectionItemsScreen> createState() =>
      _FavoriteCollectionItemsScreenState();
}

class _FavoriteCollectionItemsScreenState
    extends ConsumerState<FavoriteCollectionItemsScreen> {
  /// 当前页选择集合；窗口变化前清空，不允许跨页残留。
  final Set<String> _selectedIds = <String>{};

  /// Shift 区间选择锚点；只在当前页内有效。
  String? _selectionAnchorId;

  /// 查询失败时仅用于继续显示上一个成功窗口，不参与查询或 URL 推导。
  FavoritePageWindow? _lastSuccessfulWindow;

  String? _scheduledRouteLocation;
  int? _scheduledPreferencePageSize;

  late final FocusNode _keyboardFocusNode = FocusNode(skipTraversal: true);

  @override
  void didUpdateWidget(FavoriteCollectionItemsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.routeCollectionId != oldWidget.routeCollectionId ||
        widget.routePage != oldWidget.routePage ||
        widget.routePageSize != oldWidget.routePageSize) {
      _selectedIds.clear();
      _selectionAnchorId = null;
      _scheduledRouteLocation = null;
    }
  }

  void _schedulePreferenceSave(int pageSize) {
    if (_scheduledPreferencePageSize == pageSize) return;
    _scheduledPreferencePageSize = pageSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scheduledPreferencePageSize != pageSize) return;
      ref.read(favoritesBrowsePageSizeProvider.notifier).save(pageSize);
      _scheduledPreferencePageSize = null;
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  FavoritesLibraryController get _library =>
      ref.read(favoritesLibraryProvider.notifier);

  void _scheduleRouteCanonicalization(FavoritePageWindow window) {
    final collectionChanged =
        widget.routeCollectionId != window.effectiveCollection.id;
    final pageChanged =
        widget.routePage != null && widget.routePage != window.canonicalPage;
    final pageSizeChanged =
        widget.routePageSize != null && widget.routePageSize != window.pageSize;
    if (!collectionChanged && !pageChanged && !pageSizeChanged) return;

    final location = _routeLocation(
      collectionId: window.effectiveCollection.id,
      page: window.canonicalPage,
      pageSize: window.pageSize,
    );
    if (_scheduledRouteLocation == location) return;
    _scheduledRouteLocation = location;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scheduledRouteLocation != location) return;
      context.replace(location);
    });
  }

  String _routeLocation({
    required String collectionId,
    required int page,
    required int pageSize,
  }) => Uri(
    path: '${AppDestination.favorites.path}/collections/$collectionId',
    queryParameters: {
      AppRouteParameter.page: '$page',
      AppRouteParameter.pageSize: '$pageSize',
    },
  ).toString();

  /// 以 replace 更新 location，避免页码操作堆叠历史记录。
  void _replaceRouteLocation({
    required String collectionId,
    required int page,
    required int pageSize,
  }) {
    if (!mounted) return;
    context.replace(
      _routeLocation(
        collectionId: collectionId,
        page: page,
        pageSize: pageSize,
      ),
    );
  }

  // ── 选择 ─────────────────────────────────────────────────────────────────

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _prepareForWindowChange() {
    if (!_selectionMode && _selectionAnchorId == null) return;
    setState(() {
      _selectedIds.clear();
      _selectionAnchorId = null;
    });
  }

  void _handleRowTap(Favorite favorite) {
    final keyboard = HardwareKeyboard.instance;
    if (_selectionMode ||
        keyboard.isControlPressed ||
        keyboard.isShiftPressed) {
      _toggleWithAnchor(favorite.id);
      return;
    }
    context.pushNamed(
      AppRouteName.favoriteItemDetail,
      pathParameters: {AppRouteParameter.favoriteId: favorite.id},
    );
  }

  void _toggleWithAnchor(String favoriteId) {
    final keyboard = HardwareKeyboard.instance;
    setState(() {
      if (keyboard.isShiftPressed &&
          _selectionAnchorId != null &&
          !_selectedIds.contains(favoriteId)) {
        _selectRangeTo(favoriteId);
        return;
      }
      if (_selectedIds.contains(favoriteId)) {
        _selectedIds.remove(favoriteId);
      } else {
        _selectedIds.add(favoriteId);
      }
      _selectionAnchorId = favoriteId;
    });
  }

  /// Shift 区间选择：从锚点到目标在当前页顺序上取闭区间全部选中。
  void _selectRangeTo(String targetId) {
    final ids = (_lastSuccessfulWindow?.page.items ?? const <Favorite>[])
        .map((favorite) => favorite.id)
        .toList(growable: false);
    final anchorIndex = ids.indexOf(_selectionAnchorId!);
    final targetIndex = ids.indexOf(targetId);
    if (anchorIndex < 0 || targetIndex < 0) {
      _selectedIds.add(targetId);
      return;
    }
    final start = anchorIndex <= targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex <= targetIndex ? targetIndex : anchorIndex;
    for (var i = start; i <= end; i++) {
      _selectedIds.add(ids[i]);
    }
  }

  void _selectCurrentPage() {
    final ids = (_lastSuccessfulWindow?.page.items ?? const <Favorite>[])
        .map((favorite) => favorite.id)
        .toSet();
    if (ids.isEmpty) return;
    setState(() {
      _selectedIds.addAll(ids);
      _selectionAnchorId = null;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectionAnchorId = null;
    });
  }

  // ── 键盘 ─────────────────────────────────────────────────────────────────

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final keyboard = HardwareKeyboard.instance;

    if (keyboard.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
      _selectCurrentPage();
      return;
    }
    if (_selectionMode && event.logicalKey == LogicalKeyboardKey.escape) {
      _clearSelection();
      return;
    }
    if (_selectionMode && event.logicalKey == LogicalKeyboardKey.delete) {
      _confirmDeleteSelected();
    }
  }

  // ── 移动 / 删除 ───────────────────────────────────────────────────────────

  Future<void> _moveSelected() async {
    final targets = _selectedIds.toSet();
    if (targets.isEmpty) return;
    final targetCollectionId = await showDialog<String>(
      context: context,
      builder: (context) => const MoveFavoritesDialog(),
    );
    if (targetCollectionId == null || !mounted) return;

    _library.moveMany(targets, targetCollectionId: targetCollectionId);
    _clearSelection();
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: '删除选中的收藏',
        message: '将删除 $count 个收藏，此操作不可撤销。',
        confirmLabel: '删除',
      ),
    );
    if (confirmed != true || !mounted) return;

    _library.deleteMany(_selectedIds.toSet());
    _clearSelection();
  }

  Future<void> _confirmDeleteSingle(Favorite favorite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: '删除收藏',
        message: '将删除 1 个收藏，此操作不可撤销。',
        confirmLabel: '删除',
      ),
    );
    if (confirmed != true || !mounted) return;

    _library.deleteMany({favorite.id});
  }

  Future<void> _openDeleteCollectionDialog(
    String collectionId,
    String collectionName,
    int itemCount,
  ) async {
    await showDialog<bool>(
      context: context,
      builder: (context) => DeleteCollectionDialog(
        collectionId: collectionId,
        collectionName: collectionName,
        itemCount: itemCount,
      ),
    );
  }

  // ── 构建 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final preferredPageSize = ref.watch(favoritesBrowsePageSizeProvider);
    final explicitPageSize = widget.routePageSize;
    final pageSize =
        explicitPageSize != null &&
            appPageSizeOptions.contains(explicitPageSize)
        ? explicitPageSize
        : preferredPageSize;
    if (explicitPageSize != null &&
        appPageSizeOptions.contains(explicitPageSize) &&
        explicitPageSize != preferredPageSize) {
      _schedulePreferenceSave(explicitPageSize);
    }

    final query = (
      collectionId:
          widget.routeCollectionId ??
          AppReservedEntities.uncategorizedFavoriteCollectionId,
      page: widget.routePage ?? 1,
      pageSize: pageSize,
    );
    final result = ref.watch(favoritePageWindowProvider(query));
    final freshWindow = result.asData?.value;
    if (freshWindow != null) {
      _lastSuccessfulWindow = freshWindow;
      _scheduleRouteCanonicalization(freshWindow);
    }
    final window = freshWindow ?? _lastSuccessfulWindow;
    final items = window?.page.items ?? const <Favorite>[];

    final summaries = ref.watch(collectionsSummariesProvider);
    final summaryById = {
      for (final summary in summaries) summary.collection.id: summary,
    };
    final effectiveCollectionId =
        freshWindow?.effectiveCollection.id ?? query.collectionId;
    final currentSummary = summaryById[effectiveCollectionId];
    final collectionName =
        currentSummary?.collection.name ??
        freshWindow?.effectiveCollection.name ??
        '收藏夹';
    final isSystemCollection =
        currentSummary?.collection.isSystem ??
        freshWindow?.effectiveCollection.isSystem ??
        true;
    final currentPage =
        freshWindow?.canonicalPage ?? (query.page < 1 ? 1 : query.page);
    final effectivePageSize = freshWindow?.pageSize ?? query.pageSize;
    final totalItems = window?.page.totalItems ?? 0;
    final error = result.hasError ? favoriteLoadErrorMessage : null;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: AppShellScaffold(
        currentDestination: AppDestination.favorites,
        title: collectionName,
        hasLocalBackTarget: _selectionMode,
        onLocalBack: _clearSelection,
        actions: [
          // 系统未分类不可删除；普通收藏夹提供带去向选择的删除入口。
          if (currentSummary != null && !isSystemCollection)
            IconButton(
              tooltip: '删除收藏夹',
              icon: const Icon(Icons.folder_delete_outlined),
              onPressed: () => _openDeleteCollectionDialog(
                currentSummary.collection.id,
                collectionName,
                currentSummary.itemCount,
              ),
            ),
        ],
        body: AppPaginatedListShell(
          header: _selectionMode
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: FavoriteSelectionToolbar(
                    selectedCount: _selectedIds.length,
                    currentPageIds: {for (final favorite in items) favorite.id},
                    onSelectCurrentPage: _selectCurrentPage,
                    onClearSelection: _clearSelection,
                    onMove: _moveSelected,
                    onDelete: _confirmDeleteSelected,
                    onExitSelection: _clearSelection,
                  ),
                )
              : null,
          paginationState: AppPaginationState(
            currentPage: currentPage,
            pageSize: effectivePageSize,
            totalItems: totalItems,
            isBusy: result.isLoading,
          ),
          pageIdentity: query,
          initialLoading: result.isLoading && window == null,
          error: error,
          onRetry: error == null
              ? null
              : () => ref.invalidate(favoritePageWindowProvider(query)),
          onPageChanged: (page) {
            _prepareForWindowChange();
            _replaceRouteLocation(
              collectionId: query.collectionId,
              page: page,
              pageSize: query.pageSize,
            );
          },
          onPageSizeChanged: (size) {
            _prepareForWindowChange();
            ref.read(favoritesBrowsePageSizeProvider.notifier).save(size);
            _replaceRouteLocation(
              collectionId: query.collectionId,
              page: 1,
              pageSize: size,
            );
          },
          bodyBuilder: (context, scrollController) {
            if (items.isEmpty) {
              return Center(
                child: AppEmptyState(
                  icon: Icons.folder_open_rounded,
                  title: '暂无收藏',
                  description: '"$collectionName" 中暂时没有收藏。',
                ),
              );
            }

            return ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final favorite = items[index];
                return FavoriteListItem(
                  favorite: favorite,
                  selectionMode: _selectionMode,
                  selected: _selectedIds.contains(favorite.id),
                  onTap: () => _handleRowTap(favorite),
                  onSelectToggle: () => _toggleWithAnchor(favorite.id),
                  onMoveRequested: () => _moveSingle(favorite),
                  onDeleteRequested: () => _confirmDeleteSingle(favorite),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// 行内溢出菜单的单条移动入口：只把该条作为目标集合。
  Future<void> _moveSingle(Favorite favorite) async {
    final targetCollectionId = await showDialog<String>(
      context: context,
      builder: (context) => const MoveFavoritesDialog(),
    );
    if (targetCollectionId == null || !mounted) return;

    _library.moveMany({favorite.id}, targetCollectionId: targetCollectionId);
  }
}
