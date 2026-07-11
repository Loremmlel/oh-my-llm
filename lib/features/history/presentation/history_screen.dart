import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/rename_conversation_dialog.dart';
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

  /// 搜索输入防抖时长，避免每次按键都触发分页重置。
  static const searchDebounce = Duration(milliseconds: 300);

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

/// 历史页 UI 层：负责搜索输入、选择模式；分页数据由
/// [HistoryPaginationController] 持有，翻页由 [HistoryPaginationBar] 提供。
class _HistoryScreenState extends ConsumerState<HistoryScreen> {

  late final TextEditingController _searchController;
  Timer? _searchDebounceTimer;

  final Set<String> _selectedConversationIds = <String>{};

  bool get _selectionMode => _selectedConversationIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    // 首帧后触发首次分页加载。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(historyPaginationProvider.notifier).loadInitial();
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
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
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 8),
                const HistoryPaginationBar(),
                if (paginationState.isLoading)
                  const LinearProgressIndicator(),
                const SizedBox(height: 8),
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

    return GroupedConversationList(
      groups: groups,
      itemBuilder: (context, conversation) {
        final isSelected = _selectedConversationIds.contains(
          conversation.id,
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
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

    _searchDebounceTimer = Timer(HistoryScreen.searchDebounce, () {
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
    final count = _selectedConversationIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: '删除选中的对话',
        message: '将删除 $count 个会话，此操作不可撤销。',
        confirmLabel: '确认删除',
      ),
    );

    if (confirmed != true || !mounted) return;

    final deletedIds = _selectedConversationIds.toSet();

    await ref
        .read(chatSessionsProvider.notifier)
        .deleteConversations(deletedIds);

    if (!mounted) return;
    _clearSelection();

    // 本地移除已删除项；controller 内部处理可能的越界回退。
    ref.read(historyPaginationProvider.notifier).afterDelete(deletedIds);
  }
}
