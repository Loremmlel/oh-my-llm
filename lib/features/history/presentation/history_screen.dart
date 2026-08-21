import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';
import 'package:oh_my_llm/core/widgets/dialogs/rename_conversation_dialog.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_paginated_list_shell.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/history/history_pagination_controller.dart';
import 'package:oh_my_llm/features/chat/domain/chat_conversation_groups.dart';
import 'package:oh_my_llm/features/chat/domain/history_pagination_state.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/sidebar/grouped_conversation_list.dart';
import 'widgets/empty_history_view.dart';
import 'widgets/history_conversation_tile.dart';
import 'widgets/history_toolbar.dart';

/// History 页 route query 的解析结果。
///
/// 只做原始 query 参数到可空数值的提取；数值校验与页码夹取统一由
/// controller 的 [HistoryPaginationController.loadRoute] 处理。
/// route 是 page/pageSize/keyword 的可序列化唯一 owner。
class HistoryBrowseRouteQuery extends Equatable {
  const HistoryBrowseRouteQuery({this.page, this.pageSize, this.keyword = ''});

  factory HistoryBrowseRouteQuery.fromQueryParameters(
    Map<String, String> params,
  ) {
    return HistoryBrowseRouteQuery(
      page: int.tryParse(params[AppRouteParameter.page] ?? ''),
      pageSize: int.tryParse(params[AppRouteParameter.pageSize] ?? ''),
      keyword: params[AppRouteParameter.q] ?? '',
    );
  }

  /// URL 显式提供的页码；缺失表示回退第 1 页（由运行时处理）。
  final int? page;

  /// URL 显式提供的容量；缺失或非法时运行时回退持久化偏好。
  final int? pageSize;

  /// 搜索关键词；URL 编码由 Uri 层负责解码。
  final String keyword;

  /// 以解析后的实际窗口构建可序列化 query 参数；空关键词省略 q。
  Map<String, String> toQueryParameters({
    required int resolvedPage,
    required int resolvedPageSize,
  }) {
    return {
      AppRouteParameter.page: '$resolvedPage',
      AppRouteParameter.pageSize: '$resolvedPageSize',
      if (keyword.trim().isNotEmpty) AppRouteParameter.q: keyword,
    };
  }

  @override
  List<Object?> get props => [page, pageSize, keyword];
}

/// Chat read model 的历史对话页入口，支持搜索、批量选择、删除和重命名。
///
/// History 允许依赖 Chat 的 query、pagination 和 selection application API；详细
/// ownership 见同目录 README，不应将其误拆为独立数据域。
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({
    super.key,
    this.routeQuery = const HistoryBrowseRouteQuery(),
  });

  /// 当前 location 解析出的浏览窗口；route 是窗口参数的唯一 writer。
  final HistoryBrowseRouteQuery routeQuery;

  /// 搜索输入防抖时长，避免每次按键都触发分页重置。
  static const searchDebounce = Duration(milliseconds: 300);

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

/// 历史页 UI 层：负责搜索输入与当前页选择；分页窗口由
/// [HistoryPaginationController] 持有，布局交给共享的
/// [AppPaginatedListShell]（固定底部分页栏 + 独立滚动列表）。
class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final TextEditingController _searchController;
  late final FocusNode _keyboardFocusNode;
  Timer? _searchDebounceTimer;

  /// 当前页选择集合；翻页、容量变化、搜索生效前清空。
  final Set<String> _selectedConversationIds = <String>{};

  /// Shift 区间选择的锚点；只在当前页内有效。
  String? _selectionAnchorId;

  bool get _selectionMode => _selectedConversationIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _keyboardFocusNode = FocusNode(skipTraversal: true);
    // route 是初始化的唯一入口；provider 不允许在 widget 生命周期内同步
    // 修改，统一推迟到首帧后按 location 恢复浏览窗口。
    _scheduleSyncFromRoute(widget.routeQuery);
  }

  @override
  void didUpdateWidget(HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部导航（前进/后退/新深链）改变 query 时重新加载；
    // 自身 mutation 触发的 replace 回声与当前窗口一致，直接跳过。
    if (widget.routeQuery != oldWidget.routeQuery) {
      _scheduleSyncFromRoute(widget.routeQuery);
    }
  }

  void _scheduleSyncFromRoute(HistoryBrowseRouteQuery query) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncFromRoute(query);
    });
  }

  /// 把 route query 应用到分页 controller。
  ///
  /// 已初始化且窗口与 query 一致时视为自身 replace 的回声，不再重复查询。
  void _syncFromRoute(HistoryBrowseRouteQuery query) {
    final state = ref.read(historyPaginationProvider);
    final sameAsCurrent =
        state.isInitialized &&
        (query.page == null || query.page == state.currentPage) &&
        (query.pageSize == null || query.pageSize == state.pageSize) &&
        query.keyword.trim() == state.keyword;
    if (sameAsCurrent) return;

    ref
        .read(historyPaginationProvider.notifier)
        .loadRoute(
          page: query.page ?? 1,
          pageSize: query.pageSize,
          keyword: query.keyword,
        );
  }

  /// mutation 后以 replace 更新当前 location，避免堆叠历史记录。
  ///
  /// 关键词与窗口数值一律取 controller 当前状态；replace 后 builder 以
  /// 新 location 重建本页，回声经 [_syncFromRoute] 的一致性检查跳过。
  void _replaceRouteLocation() {
    if (!mounted) return;
    final state = ref.read(historyPaginationProvider);
    final uri = Uri(
      path: AppDestination.history.path,
      queryParameters: HistoryBrowseRouteQuery(keyword: state.keyword)
          .toQueryParameters(
            resolvedPage: state.currentPage,
            resolvedPageSize: state.pageSize,
          ),
    );
    context.replace(uri.toString());
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  // ── 构建 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 每次写操作（create/rename/delete）后重建；分页 controller 内部
    // 已按数据库真实结果修正窗口，revision 变化不会丢弃已加载数据。
    ref.watch(chatHistoryRevisionProvider);

    final paginationState = ref.watch(historyPaginationProvider);

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: AppShellScaffold(
        currentDestination: AppDestination.history,
        title: '历史对话页',
        // 选择态是页面本地返回目标：系统返回优先清选择，而不是直接退回对话页。
        hasLocalBackTarget: _selectionMode,
        onLocalBack: _clearSelection,
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            child: AppPaginatedListShell(
              header: Padding(
                padding: const EdgeInsets.all(12),
                child: HistoryToolbar(
                  mode: _selectionMode
                      ? HistoryToolbarMode.selection
                      : HistoryToolbarMode.search,
                  searchController: _searchController,
                  selectedCount: _selectedConversationIds.length,
                  hasConversations: paginationState.hasAnyConversations,
                  onSearchChanged: _handleSearchChanged,
                  onSearchCleared: _handleSearchCleared,
                  onSelectCurrentPage: _selectCurrentPage,
                  onClearSelection: _clearSelection,
                  onDeletePressed: _selectedConversationIds.isEmpty
                      ? null
                      : _confirmDeleteSelected,
                  onExitSelection: _clearSelection,
                ),
              ),
              paginationState: AppPaginationState(
                currentPage: paginationState.currentPage,
                pageSize: paginationState.pageSize,
                totalItems: paginationState.totalItems,
                isBusy: paginationState.isLoading,
              ),
              pageIdentity:
                  '${paginationState.keyword} '
                  '${paginationState.currentPage} '
                  '${paginationState.pageSize}',
              initialLoading: !paginationState.isInitialized,
              error: paginationState.errorMessage,
              onRetry: paginationState.errorMessage == null
                  ? null
                  : () => ref
                        .read(historyPaginationProvider.notifier)
                        .loadRoute(
                          page: paginationState.currentPage,
                          pageSize: paginationState.pageSize,
                          keyword: paginationState.keyword,
                        ),
              onPageChanged: (page) {
                _prepareForWindowChange();
                ref.read(historyPaginationProvider.notifier).goToPage(page);
                _replaceRouteLocation();
              },
              onPageSizeChanged: (size) {
                _prepareForWindowChange();
                ref.read(historyPaginationProvider.notifier).setPageSize(size);
                _replaceRouteLocation();
              },
              bodyBuilder: (context, scrollController) =>
                  _buildConversationList(
                    context,
                    paginationState,
                    scrollController,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList(
    BuildContext context,
    HistoryPaginationState paginationState,
    ScrollController scrollController,
  ) {
    if (paginationState.conversations.isEmpty &&
        !paginationState.isLoading &&
        paginationState.isInitialized) {
      return EmptyHistoryView(
        hasConversations: paginationState.hasAnyConversations,
        searchKeyword: _searchController.text,
        onClearSearch: _handleSearchCleared,
      );
    }

    final groups = groupConversationSummariesByUpdatedAt(
      paginationState.conversations,
    );

    return GroupedConversationList(
      groups: groups,
      scrollController: scrollController,
      itemBuilder: (context, conversation) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: HistoryConversationTile(
            conversation: conversation,
            selected: _selectedConversationIds.contains(conversation.id),
            selectionMode: _selectionMode,
            contextMenuKey: GlobalObjectKey('history-tile-${conversation.id}'),
            onTap: () => _handleRowTap(conversation),
            onLongPress: () => _toggleSelectionWithAnchor(conversation.id),
            onSelectRequested: () =>
                _toggleSelectionWithAnchor(conversation.id),
            onRenameRequested: () =>
                _showRenameDialog(conversation: conversation),
            onDeleteRequested: () => _confirmDeleteSingle(conversation.id),
          ),
        );
      },
    );
  }

  // ── 选择 ─────────────────────────────────────────────────────────────────

  void _handleRowTap(ChatConversationSummary conversation) {
    final keyboard = HardwareKeyboard.instance;
    if (_selectionMode ||
        keyboard.isControlPressed ||
        keyboard.isShiftPressed) {
      if (keyboard.isShiftPressed && _selectionAnchorId != null) {
        _selectRangeTo(conversation.id);
        return;
      }
      _toggleSelectionWithAnchor(conversation.id);
      return;
    }

    ref.read(chatSessionsProvider.notifier).selectConversation(conversation.id);
    // push 打开会话：pop 后历史页连同 location 与滚动一起恢复。
    context.push(
      Uri(
        path: AppDestination.chat.path,
        queryParameters: {AppRouteParameter.conversationId: conversation.id},
      ).toString(),
    );
  }

  /// 切换单项选择并更新区间锚点。
  void _toggleSelectionWithAnchor(String conversationId) {
    setState(() {
      if (_selectedConversationIds.contains(conversationId)) {
        _selectedConversationIds.remove(conversationId);
      } else {
        _selectedConversationIds.add(conversationId);
      }
      _selectionAnchorId = conversationId;
    });
  }

  /// Shift 区间选择：从锚点到目标在当前页顺序上取闭区间全部选中。
  void _selectRangeTo(String targetId) {
    final ids = ref
        .read(historyPaginationProvider)
        .conversations
        .map((c) => c.id)
        .toList(growable: false);
    final anchorIndex = ids.indexOf(_selectionAnchorId!);
    final targetIndex = ids.indexOf(targetId);
    setState(() {
      if (anchorIndex < 0 || targetIndex < 0) {
        _selectedConversationIds.add(targetId);
      } else {
        final start = anchorIndex <= targetIndex ? anchorIndex : targetIndex;
        final end = anchorIndex <= targetIndex ? targetIndex : anchorIndex;
        for (var i = start; i <= end; i++) {
          _selectedConversationIds.add(ids[i]);
        }
      }
    });
  }

  /// Ctrl+A 等价：选择当前页全部会话。
  void _selectCurrentPage() {
    final ids = ref
        .read(historyPaginationProvider)
        .conversations
        .map((c) => c.id)
        .toSet();
    if (ids.isEmpty) return;
    setState(() {
      _selectedConversationIds.addAll(ids);
      _selectionAnchorId = null;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedConversationIds.clear();
      _selectionAnchorId = null;
    });
  }

  /// 翻页 / 容量变化 / 搜索生效前的窗口变更准备：清空选择与锚点。
  void _prepareForWindowChange() {
    if (!_selectionMode && _selectionAnchorId == null) return;
    setState(() {
      _selectedConversationIds.clear();
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
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.contextMenu) {
      final anchor =
          _selectionAnchorId ??
          (_selectedConversationIds.isEmpty
              ? null
              : _selectedConversationIds.first);
      if (anchor != null) {
        _openContextMenuFor(anchor);
      }
    }
  }

  /// 菜单键：在锚点（或首个选中项）所在行打开上下文菜单。
  void _openContextMenuFor(String conversationId) {
    final key = GlobalObjectKey('history-tile-$conversationId');
    final context = key.currentContext;
    if (context == null) return;
    final box = context.findRenderObject()! as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        center.dx,
        center.dy,
        overlay.size.width - center.dx,
        overlay.size.height - center.dy,
      ),
      items: [
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ).then((action) {
      if (!mounted || action == null) return;
      switch (action) {
        case 'rename':
          final matches = ref
              .read(historyPaginationProvider)
              .conversations
              .where((c) => c.id == conversationId)
              .toList();
          if (matches.isEmpty) return;
          _showRenameDialog(conversation: matches.first);
        case 'delete':
          _confirmDeleteSingle(conversationId);
      }
    });
  }

  // ── 搜索 ─────────────────────────────────────────────────────────────────

  void _handleSearchChanged(String value) {
    _searchDebounceTimer?.cancel();
    final nextKeyword = value.trim();

    if (nextKeyword.isEmpty && _currentKeyword().isEmpty) return;

    _searchDebounceTimer = Timer(HistoryScreen.searchDebounce, () {
      if (!mounted || _currentKeyword() == nextKeyword) return;
      // 搜索生效改变结果集，先清空选择再查询并同步 location。
      _prepareForWindowChange();
      ref.read(historyPaginationProvider.notifier).setKeyword(nextKeyword);
      _replaceRouteLocation();
    });
  }

  void _handleSearchCleared() {
    _searchDebounceTimer?.cancel();
    if (_currentKeyword().isEmpty) return;
    _prepareForWindowChange();
    ref.read(historyPaginationProvider.notifier).setKeyword('');
    _replaceRouteLocation();
  }

  String _currentKeyword() => ref.read(historyPaginationProvider).keyword;

  // ── 重命名 ───────────────────────────────────────────────────────────────

  Future<void> _showRenameDialog({
    required ChatConversationSummary conversation,
  }) async {
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          RenameConversationDialog(initialTitle: conversation.resolvedTitle),
    );

    if (!mounted || nextTitle == null || nextTitle.trim().isEmpty) return;

    await ref
        .read(chatSessionsProvider.notifier)
        .renameConversation(conversationId: conversation.id, title: nextTitle);

    if (!mounted) return;
    if (ref.read(historyPaginationProvider).keyword.isNotEmpty) {
      // 搜索态下 rename 改变匹配集合，controller 会重新查询；
      // 非搜索态才做本地标题更新以保留滚动位置。
      return;
    }
    ref
        .read(historyPaginationProvider.notifier)
        .afterRename(conversation.id, nextTitle);
  }

  // ── 删除 ─────────────────────────────────────────────────────────────────

  /// 单项删除入口（overflow / 右键菜单）。
  Future<void> _confirmDeleteSingle(String conversationId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: '删除选中的对话',
        message: '将删除 1 个会话，此操作不可撤销。',
        confirmLabel: '确认删除',
      ),
    );

    if (confirmed != true || !mounted) return;
    await _deleteConversations({conversationId});
  }

  /// 批量删除入口（工具栏 / Delete 键）。
  Future<void> _confirmDeleteSelected() async {
    final count = _selectedConversationIds.length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: '删除选中的对话',
        message: '将删除 $count 个会话，此操作不可撤销。',
        confirmLabel: '确认删除',
      ),
    );

    if (confirmed != true || !mounted) return;
    await _deleteConversations(_selectedConversationIds.toSet());
  }

  Future<void> _deleteConversations(Set<String> deletedIds) async {
    await ref
        .read(chatSessionsProvider.notifier)
        .deleteConversations(deletedIds);

    if (!mounted) return;
    _clearSelection();

    // controller 按数据库真实结果重拉当前窗口并处理页码回退。
    ref.read(historyPaginationProvider.notifier).afterDelete(deletedIds);
  }
}
