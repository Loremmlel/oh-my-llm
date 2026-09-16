import 'package:flutter/material.dart';

import '../../../domain/chat_conversation_groups.dart';
import 'grouped_conversation_list.dart';

/// 聊天页侧边历史面板，用于快速切换会话。
class ConversationHistoryPanel extends StatelessWidget {
  const ConversationHistoryPanel({
    required this.groups,
    required this.activeConversationId,
    required this.onCreateConversation,
    required this.onConversationSelected,
    super.key,
  });

  final List<ChatConversationSummaryGroup> groups;
  final String activeConversationId;
  final VoidCallback? onCreateConversation;
  final ValueChanged<String> onConversationSelected;

  @override
  /// 构建按时间分组的会话列表与新建入口。
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: '新建对话',
            child: TextButton.icon(
              onPressed: onCreateConversation,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建对话'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: groups.isEmpty
                ? const Center(child: Text('还没有已保存的会话记录。'))
                : GroupedConversationList(
                    groups: groups,
                    itemBuilder: (context, conversation) {
                      final theme = Theme.of(context);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          tileColor: conversation.id == activeConversationId
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerLow,
                          title: Tooltip(
                            message: conversation.resolvedTitle,
                            child: Text(
                              conversation.resolvedTitle,
                              maxLines: conversation.hasCustomTitle ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          subtitle: conversation.hasCustomTitle
                              ? null
                              : Text(
                                  conversation.previewText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => onConversationSelected(conversation.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
