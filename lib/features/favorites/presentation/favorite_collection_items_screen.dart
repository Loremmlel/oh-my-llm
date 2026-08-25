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
import '../application/favorite_browser_controller.dart';
import '../application/favorites_controller.dart';
import '../domain/models/favorite.dart';
import 'widgets/dialogs/delete_collection_dialog.dart';
import 'widgets/dialogs/move_favorites_dialog.dart';
import 'widgets/favorite_list_item.dart';
import 'widgets/favorite_selection_toolbar.dart';

/// 收藏夹内容页：真实分页浏览单个收藏夹内的收藏，支持多选移动与删除。
///
/// route 是 collectionId/page/pageSize 的唯一 writer；本页把深链参数交给
/// [FavoriteBrowserController.loadRoute]，翻页与容量变化经 controller 生效后
/// 以 replace 回写 URL，保持深链可恢复。
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

  late final FocusNode _keyboardFocusNode = FocusNode(skipTraversal: true);

  @override
  void initState() {
    super.initState();
    // route 是初始化唯一入口；统一推迟到首帧后按 location 恢复窗口。
    _scheduleSyncFromRoute();
  }

  @override
  void didUpdateWidget(FavoriteCollectionItemsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.routeCollectionId != oldWidget.routeCollectionId ||
        widget.routePage != oldWidget.routePage ||
        widget.routePageSize != oldWidget.routePageSize) {
      // 外部导航（前进/后退/新深链）改变 query 时重新加载；自身 replace 的
      // 回声与当前窗口一致时由 loadRoute 前的一致性检查跳过。provider 不允许
      // 在 rebuild 阶段同步修改，统一推迟到首帧后执行。
      _scheduleSyncFromRoute();
    }
  }

  void _scheduleSyncFromRoute() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final browser = ref.read(favoriteBrowserProvider);
      // 已初始化且窗口与 query 一致时视为自身 replace 的回声，
      // 不再重复查询（翻页/容量回调已先行清空选择）。
      final sameAsCurrent =
          browser.isInitialized &&
          (widget.routeCollectionId == null ||
              widget.routeCollectionId == browser.collectionId) &&
          (widget.routePage == null || widget.routePage == browser.page) &&
          (widget.routePageSize == null ||
              widget.routePageSize == browser.pageSize);
      if (sameAsCurrent) return;

      _prepareForWindowChange();
      ref
          .read(favoriteBrowserProvider.notifier)
          .loadRoute(
            collectionId: widget.routeCollectionId,
            page: widget.routePage ?? 1,
            pageSize: widget.routePageSize,
          );
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  FavoritesLibraryController get _library =>
      ref.read(favoritesLibraryProvider.notifier);

  /// mutation 后以 replace 更新 location，避免堆叠历史记录。
  void _replaceRouteLocation() {
    if (!mounted) return;
    final state = ref.read(favoriteBrowserProvider);
    context.replace(
      Uri(
        path:
            '${AppDestination.favorites.path}/collections/${state.collectionId}',
        queryParameters: {
          AppRouteParameter.page: '${state.page}',
          AppRouteParameter.pageSize: '${state.pageSize}',
        },
      ).toString(),
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
    final ids = ref
        .read(favoriteBrowserProvider)
        .items
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
    final ids = ref
        .read(favoriteBrowserProvider)
        .items
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
    String collectionName,
    int itemCount,
  ) async {
    await showDialog<bool>(
      context: context,
      builder: (context) => DeleteCollectionDialog(
        collectionId: widget.routeCollectionId ?? '',
        collectionName: collectionName,
        itemCount: itemCount,
      ),
    );
  }

  // ── 构建 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final browser = ref.watch(favoriteBrowserProvider);
    final summaries = ref.watch(collectionsSummariesProvider);
    final summaryById = {
      for (final summary in summaries) summary.collection.id: summary,
    };
    final currentSummary =
        summaryById[browser.collectionId] ?? summaries.firstOrNull;
    final collectionName = currentSummary?.collection.name ?? '收藏夹';
    final isSystemCollection =
        browser.collectionId ==
        AppReservedEntities.uncategorizedFavoriteCollectionId;

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
          if (!isSystemCollection)
            IconButton(
              tooltip: '删除收藏夹',
              icon: const Icon(Icons.folder_delete_outlined),
              onPressed: () => _openDeleteCollectionDialog(
                collectionName,
                currentSummary?.itemCount ?? 0,
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
                    currentPageIds: {
                      for (final favorite in browser.items) favorite.id,
                    },
                    onSelectCurrentPage: _selectCurrentPage,
                    onClearSelection: _clearSelection,
                    onMove: _moveSelected,
                    onDelete: _confirmDeleteSelected,
                    onExitSelection: _clearSelection,
                  ),
                )
              : null,
          paginationState: AppPaginationState(
            currentPage: browser.page,
            pageSize: browser.pageSize,
            totalItems: browser.totalItems,
            isBusy: browser.isBusy,
          ),
          pageIdentity:
              '${browser.collectionId} ${browser.page} ${browser.pageSize}',
          initialLoading: !browser.isInitialized,
          error: browser.errorMessage,
          onRetry: browser.errorMessage == null
              ? null
              : () => ref.read(favoriteBrowserProvider.notifier).retry(),
          onPageChanged: (page) {
            _prepareForWindowChange();
            ref.read(favoriteBrowserProvider.notifier).goToPage(page);
            _replaceRouteLocation();
          },
          onPageSizeChanged: (size) {
            _prepareForWindowChange();
            ref.read(favoriteBrowserProvider.notifier).setPageSize(size);
            _replaceRouteLocation();
          },
          bodyBuilder: (context, scrollController) {
            if (browser.items.isEmpty) {
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
              itemCount: browser.items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final favorite = browser.items[index];
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
