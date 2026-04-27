import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../chat/application/chat_sessions_controller.dart';
import '../../chat/domain/chat_conversation_groups.dart';
import '../../chat/domain/models/chat_conversation.dart';
import 'widgets/history_widgets.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final TextEditingController _searchController;

  final Set<String> _selectedConversationIds = <String>{};

  bool get _selectionMode => _selectedConversationIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatSessionsProvider);
    final conversations = chatState.conversations
        .where((conversation) {
          return conversation.hasMessages;
        })
        .toList(growable: false);
    final filteredConversations = _filterConversations(
      conversations,
      _searchController.text,
    );
    final groups = groupConversationsByUpdatedAt(filteredConversations);

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
                  hasConversations: conversations.isNotEmpty,
                  onSearchChanged: (_) => setState(() {}),
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
                          hasConversations: conversations.isNotEmpty,
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

  List<ChatConversation> _filterConversations(
    List<ChatConversation> conversations,
    String keyword,
  ) {
    final normalizedKeyword = keyword.trim().toLowerCase();
    if (normalizedKeyword.isEmpty) {
      return conversations;
    }

    return conversations
        .where((conversation) {
          final titleMatched = conversation.resolvedTitle
              .toLowerCase()
              .contains(normalizedKeyword);
          if (titleMatched) {
            return true;
          }

          final searchableMessages = conversation.messageNodes.isNotEmpty
              ? conversation.messageNodes
              : conversation.messages;
          return searchableMessages.any((message) {
            return message.role.name == 'user' &&
                message.content.toLowerCase().contains(normalizedKeyword);
          });
        })
        .toList(growable: false);
  }

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
    setState(() {
      _selectedConversationIds.clear();
    });
  }

  Future<void> _showRenameDialog(
    BuildContext context, {
    required ChatConversation conversation,
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
