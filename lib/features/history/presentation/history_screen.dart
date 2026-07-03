import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../chat/application/chat_sessions_controller.dart';
import '../../chat/application/history_pagination_controller.dart';
import '../../chat/domain/chat_conversation_groups.dart';
import '../../chat/domain/history_pagination_state.dart';
import '../../chat/domain/models/chat_conversation_summary.dart';
import '../../chat/presentation/widgets/grouped_conversation_list.dart';
import 'widgets/history_widgets.dart';

/// 历史对话页入口，支持搜索、批量选择、删除和重命名。
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

/// 历史页 UI 层：负责搜索输入、选择模式、滚动监听。
///
/// 分页数据由 [HistoryPaginationController] 持有，本层纯 view。
class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// 搜索输入防抖时长，避免每次按键都触发分页重置。
  static const _searchDebounce = Duration(milliseconds: 300);

  late final TextEditingController _searchController;
  Timer? _searchDebounceTimer;

  final Set<String> _selectedConversationIds = <String>{};
  late final ScrollController _scrollController;

  bool get _selectionMode => _selectedConversationIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scrollController = ScrollController()..addListener(_onScroll);
    // 首帧后触发首次分页加载，并在布局完成后检查是否需要自动填满视口
    // （避免内容不足一屏时底部 loading 永远转，见 _autoFillIfNeeded）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(historyPaginationProvider.notifier).loadInitial();
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoFillIfNeeded());
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── 滚动监听 ──────────────────────────────────────────────────────────────

  /// 距底部 200px 以内时触发预加载。
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(historyPaginationProvider.notifier).loadMore();
    }
  }

  /// 数据不足以填满视口时自动追加加载，避免底部 loading 永远转。
  ///
  /// 与 [_onScroll] 互补：像素阈值只对"能滚得动"的情况有效；当内容不足
  /// 一屏时，[_onScroll] 永远达不到触发条件， spinner 就会 fixed 在底部的
  /// Column 上不停转，必须由本方法显式打破死锁。
  void _autoFillIfNeeded() {
    if (!mounted) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final state = ref.read(historyPaginationProvider);
    if (position.maxScrollExtent <= position.viewportDimension &&
        state.hasMore &&
        !state.isLoading) {
      ref.read(historyPaginationProvider.notifier).loadMore();
    }
  }

  // ── 构建 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 每次写操作（create/rename/delete）后重建；分页 controller 内部
    // 已通过 afterRename/afterDelete 做本地修正，revision 变化不会
    // 丢弃已加载的分页数据。
    ref.watch(chatHistoryRevisionProvider);

    final paginationState = ref.watch(historyPaginationProvider);
    final conversations = paginationState.conversations;

    return AppShellScaffold(
      currentDestination: AppDestination.history,
      title: '历史对话页',
      actions: [
        if (_selectionMode)
          IconButton(
            onPressed: _clearSelection,
            tooltip: '取消选择',
            icon: const Icon(Icons.close_rounded),
          ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('历史对话', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '支持按标题和用户消息搜索、批量删除、重命名，并可跳回主页中的目标会话。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                HistoryToolbar(
                  searchController: _searchController,
                  selectedCount: _selectedConversationIds.length,
                  hasConversations: paginationState.hasAnyConversations,
                  onSearchChanged: _handleSearchChanged,
                  onSelectAllPressed: conversations.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _selectedConversationIds
                              ..clear()
                              ..addAll(conversations.map((c) => c.id));
                          });
                        },
                  onDeletePressed: _selectedConversationIds.isEmpty
                      ? null
                      : _confirmDeleteSelected,
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: _buildConversationList(context, paginationState),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList(
    BuildContext context,
    HistoryPaginationState paginationState,
  ) {
    final groups = groupConversationSummariesByUpdatedAt(
      paginationState.conversations,
    );

    if (groups.isEmpty && !paginationState.isLoading) {
      return EmptyHistoryView(
        hasConversations: paginationState.hasAnyConversations,
        searchKeyword: _searchController.text,
      );
    }

    // 每次列表重建（分页追加后）都检查是否需要继续追加，以填满视口。
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoFillIfNeeded());

    return Column(
      children: [
        Expanded(
          child: GroupedConversationList(
            groups: groups,
            scrollController: _scrollController,
            itemBuilder: (context, conversation) {
              final isSelected = _selectedConversationIds.contains(
                conversation.id,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: HistoryConversationTile(
                  conversation: conversation,
                  selected: isSelected,
                  onTap: () {
                    if (_selectionMode) {
                      _toggleSelection(conversation.id);
                      return;
                    }
                    ref
                        .read(chatSessionsProvider.notifier)
                        .selectConversation(conversation.id);
                    context.go(AppDestination.chat.path);
                  },
                  onLongPress: () => _toggleSelection(conversation.id),
                  onRenamePressed: () => _showRenameDialog(
                    context,
                    conversation: conversation,
                  ),
                  onSelectionChanged: (_) => _toggleSelection(
                    conversation.id,
                  ),
                ),
              );
            },
          ),
        ),
        // 底部加载指示器（hasMore 时显示）。
        // 仅当数据量已足以让用户主动滚近底部、或已加载完（hasMore=false）
        // 时才会消失；不满一屏的中间状态由 _autoFillIfNeeded 自动追加填满。
        if (paginationState.hasMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  // ── 选择 ─────────────────────────────────────────────────────────────────

  void _toggleSelection(String conversationId) {
    setState(() {
      if (_selectedConversationIds.contains(conversationId)) {
        _selectedConversationIds.remove(conversationId);
      } else {
        _selectedConversationIds.add(conversationId);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedConversationIds.clear());
  }

  // ── 搜索 ─────────────────────────────────────────────────────────────────

  void _handleSearchChanged(String value) {
    _searchDebounceTimer?.cancel();
    final nextKeyword = value.trim();

    if (nextKeyword.isEmpty && _currentKeyword().isEmpty) return;

    _searchDebounceTimer = Timer(_searchDebounce, () {
      if (!mounted || _currentKeyword() == nextKeyword) return;
      ref.read(historyPaginationProvider.notifier).setKeyword(nextKeyword);
    });
  }

  String _currentKeyword() =>
      ref.read(historyPaginationProvider).keyword;

  // ── 重命名 ───────────────────────────────────────────────────────────────

  Future<void> _showRenameDialog(
    BuildContext context, {
    required ChatConversationSummary conversation,
  }) async {
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (context) => RenameConversationDialog(
        initialTitle: conversation.resolvedTitle,
      ),
    );

    if (!mounted || nextTitle == null || nextTitle.trim().isEmpty) return;

    await ref
        .read(chatSessionsProvider.notifier)
        .renameConversation(
          conversationId: conversation.id,
          title: nextTitle,
        );

    // 等 DB 落盘后本地刷新标题（controller 已处理 revision 递增触发 watch，
    // 但此处提前本地更新可避免 80ms debounce 窗口期的 UI 闪烁）。
    ref.read(historyPaginationProvider.notifier).afterRename(
      conversation.id,
      nextTitle,
    );
  }

  // ── 删除 ─────────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final count = _selectedConversationIds.length;
        if (count == 0) {
          return const AppConfirmDialog(
            title: '删除选中的对话',
            message: '没有选中任何会话。',
            confirmLabel: '确认',
          );
        }
        return AppConfirmDialog(
          title: '删除选中的对话',
          message: '将删除 $count 个会话，此操作不可撤销。',
          confirmLabel: '确认删除',
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final deletedIds = _selectedConversationIds.toSet();

    await ref
        .read(chatSessionsProvider.notifier)
        .deleteConversations(deletedIds);

    if (!mounted) return;
    _clearSelection();

    // 本地移除已删除项，避免全量刷新丢失滚动位置。
    ref.read(historyPaginationProvider.notifier).afterDelete(deletedIds);
  }
}
