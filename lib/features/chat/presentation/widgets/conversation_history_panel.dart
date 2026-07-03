import 'package:flutter/material.dart';

import '../../domain/chat_conversation_groups.dart';
import 'grouped_conversation_list.dart';

/// 聊天页侧边历史面板，用于快速切换会话。
class ConversationHistoryPanel extends StatelessWidget {
  const ConversationHistoryPanel({
    required this.groups,
    required this.activeConversationId,
    required this.hasDraftConversation,
    required this.onCreateConversation,
    required this.onConversationSelected,
    super.key,
  });

  final List<ChatConversationSummaryGroup> groups;
  final String activeConversationId;
  final bool hasDraftConversation;
  final VoidCallback? onCreateConversation;
  final ValueChanged<String> onConversationSelected;

  @override
  /// 构建按时间分组的会话列表与新建入口。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('历史会话面板', style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: onCreateConversation,
                  tooltip: '新建对话',
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasDraftConversation ? '当前包含未发送的新对话草稿。' : '按更新时间分组展示对话。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
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
                            tileColor:
                                conversation.id == activeConversationId
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerLow,
                            title: Tooltip(
                              message: conversation.resolvedTitle,
                              child: Text(
                                conversation.resolvedTitle,
                                maxLines:
                                    conversation.hasCustomTitle ? 2 : 1,
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
                            onTap: () => onConversationSelected(
                              conversation.id,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
