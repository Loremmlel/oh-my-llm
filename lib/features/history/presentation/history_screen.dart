import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../chat/application/chat_sessions_controller.dart';
import '../../chat/data/chat_conversation_repository.dart';
import '../../chat/domain/chat_conversation_groups.dart';
import '../../chat/domain/models/chat_conversation_summary.dart';
import 'widgets/history_widgets.dart';

/// 搜索输入防抖时长，避免每次按键都触发数据库查询。
const _historySearchDebounceDuration = Duration(milliseconds: 300);

/// 历史对话页入口，支持搜索、批量选择、删除和重命名。
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

/// 历史页状态层，负责搜索、选择和会话跳转。
class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final TextEditingController _searchController;
  Timer? _searchDebounceTimer;

  final Set<String> _selectedConversationIds = <String>{};
  String _debouncedSearchKeyword = '';

  bool get _selectionMode => _selectedConversationIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// 构建历史页的搜索区和分组列表。
  @override
  Widget build(BuildContext context) {
    ref.watch(chatHistoryRevisionProvider);
    final repository = ref.read(chatConversationRepositoryProvider);
    final allConversations = repository.loadHistorySummaries();
    final filteredConversations = _debouncedSearchKeyword.isEmpty
        ? allConversations
        : repository.loadHistorySummaries(keyword: _debouncedSearchKeyword);
    final groups = groupConversationSummariesByUpdatedAt(filteredConversations);

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
                  hasConversations: allConversations.isNotEmpty,
                  onSearchChanged: _handleSearchChanged,
                  onSelectAllPressed: filteredConversations.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _selectedConversationIds
                              ..clear()
                              ..addAll(
                                filteredConversations.map((conversation) {
                                  return conversation.id;
                                }),
                              );
                          });
                        },
                  onDeletePressed: _selectedConversationIds.isEmpty
                      ? null
                      : _confirmDeleteSelected,
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: groups.isEmpty
                      ? EmptyHistoryView(
                          hasConversations: allConversations.isNotEmpty,
                          searchKeyword: _searchController.text,
                        )
                      : ListView.separated(
                          itemCount: groups.length,
                          separatorBuilder: (context, index) {
                            return const SizedBox(height: 20);
                          },
                          itemBuilder: (context, index) {
                            final group = groups[index];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.bucket.label,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 10),
                                ...group.conversations.map((conversation) {
                                  final isSelected = _selectedConversationIds
                                      .contains(conversation.id);

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
                                            .selectConversation(
                                              conversation.id,
                                            );
                                        context.go(AppDestination.chat.path);
                                      },
                                      onLongPress: () {
                                        _toggleSelection(conversation.id);
                                      },
                                      onRenamePressed: () {
                                        _showRenameDialog(
                                          context,
                                          conversation: conversation,
                                        );
                                      },
                                      onSelectionChanged: (value) {
                                        _toggleSelection(conversation.id);
                                      },
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 切换某个会话的选中状态。
  void _toggleSelection(String conversationId) {
    setState(() {
      if (_selectedConversationIds.contains(conversationId)) {
        _selectedConversationIds.remove(conversationId);
      } else {
        _selectedConversationIds.add(conversationId);
      }
    });
  }

  /// 清空全部选中项。
  void _clearSelection() {
    setState(() {
      _selectedConversationIds.clear();
    });
  }

  /// 将搜索输入和真正执行查询的关键字解耦，避免每次按键都立即查库。
  void _handleSearchChanged(String value) {
    _searchDebounceTimer?.cancel();
    final nextKeyword = value.trim();

    if (nextKeyword.isEmpty) {
      if (_debouncedSearchKeyword.isEmpty) {
        return;
      }

      setState(() {
        _debouncedSearchKeyword = '';
      });
      return;
    }

    _searchDebounceTimer = Timer(_historySearchDebounceDuration, () {
      if (!mounted || _debouncedSearchKeyword == nextKeyword) {
        return;
      }

      setState(() {
        _debouncedSearchKeyword = nextKeyword;
      });
    });
  }

  /// 弹出重命名对话框，并把结果提交给控制器。
  Future<void> _showRenameDialog(
    BuildContext context, {
    required ChatConversationSummary conversation,
  }) async {
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (context) {
        return RenameConversationDialog(
          initialTitle: conversation.resolvedTitle,
        );
      },
    );

    if (!mounted || nextTitle == null || nextTitle.trim().isEmpty) {
      return;
    }

    await ref
        .read(chatSessionsProvider.notifier)
        .renameConversation(conversationId: conversation.id, title: nextTitle);
  }

  /// 确认并删除当前选中的历史会话。
  Future<void> _confirmDeleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除选中的对话'),
          content: Text('将删除 ${_selectedConversationIds.length} 个会话，此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await ref
        .read(chatSessionsProvider.notifier)
        .deleteConversations(_selectedConversationIds);
    _clearSelection();
  }
}
