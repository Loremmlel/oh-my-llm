import 'package:flutter/material.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';
import 'chat_message_bubble.dart';
import 'empty_conversation_view.dart';
import 'message_anchor_rail.dart';
import 'message_version_info.dart';
import 'thinking_toggle.dart';

class ChatWorkspace extends StatelessWidget {
  const ChatWorkspace({
    required this.conversation,
    required this.hasModels,
    required this.userMessages,
    required this.activeAnchorMessageId,
    required this.messageController,
    required this.messageScrollController,
    required this.messagesViewportKey,
    required this.messageKeys,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.isStreaming,
    required this.errorMessage,
    required this.showScrollToBottom,
    required this.onDismissError,
    required this.onEditMessage,
    required this.onRetryLatestAssistant,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onScrollToBottomPressed,
    required this.onSelectMessage,
    required this.onSelectMessageVersion,
    required this.onSendPressed,
    super.key,
  });

  final ChatConversation conversation;
  final bool hasModels;
  final List<ChatMessage> userMessages;
  final String? activeAnchorMessageId;
  final TextEditingController messageController;
  final ScrollController messageScrollController;
  final GlobalKey messagesViewportKey;
  final Map<String, GlobalKey> messageKeys;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final bool isStreaming;
  final String? errorMessage;
  final bool showScrollToBottom;
  final VoidCallback onDismissError;
  final ValueChanged<ChatMessage> onEditMessage;
  final Future<void> Function() onRetryLatestAssistant;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final VoidCallback onScrollToBottomPressed;
  final ValueChanged<String> onSelectMessage;
  final Future<void> Function(String parentId, String messageId)
  onSelectMessageVersion;
  final Future<void> Function()? onSendPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final messagesCard = _buildMessagesCard(theme);
        final composerCard = _buildComposerCard(theme);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (errorMessage != null) ...[
              _buildErrorBanner(theme),
              const SizedBox(height: 8),
            ],
            Expanded(child: messagesCard),
            const SizedBox(height: 12),
            composerCard,
          ],
        );
      },
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            leading: Icon(
              Icons.error_outline_rounded,
              color: theme.colorScheme.onErrorContainer,
            ),
            title: Text(
              errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            trailing: IconButton(
              onPressed: onDismissError,
              icon: Icon(
                Icons.close_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              tooltip: '关闭错误提示',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesCard(ThemeData theme) {
    final latestAssistantMessage =
        conversation.messages.lastOrNull?.role == ChatMessageRole.assistant
        ? conversation.messages.lastOrNull
        : null;
    final versionInfoByMessageId = _buildMessageVersionInfoMap();

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchorRightPadding = userMessages.isEmpty ? 14.0 : 52.0;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (conversation.messages.isEmpty)
                KeyedSubtree(
                  key: messagesViewportKey,
                  child: EmptyConversationView(hasModels: hasModels),
                )
              else
                SingleChildScrollView(
                  key: messagesViewportKey,
                  controller: messageScrollController,
                  padding: EdgeInsets.fromLTRB(14, 14, anchorRightPadding, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final message in conversation.messages) ...[
                        KeyedSubtree(
                          key: messageKeys.putIfAbsent(
                            message.id,
                            GlobalKey.new,
                          ),
                          child: ChatMessageBubble(
                            message: message,
                            canEdit:
                                !isStreaming &&
                                message.role == ChatMessageRole.user,
                            canRetry:
                                !isStreaming &&
                                latestAssistantMessage?.id == message.id,
                            onEditPressed: message.role == ChatMessageRole.user
                                ? () {
                                    onEditMessage(message);
                                  }
                                : null,
                            onRetryPressed:
                                latestAssistantMessage?.id == message.id
                                ? () {
                                    onRetryLatestAssistant();
                                  }
                                : null,
                            versionInfo: versionInfoByMessageId[message.id],
                            onSwitchVersion: (targetMessageId) async {
                              final versionInfo =
                                  versionInfoByMessageId[message.id];
                              if (versionInfo == null) {
                                return;
                              }
                              await onSelectMessageVersion(
                                versionInfo.parentId,
                                targetMessageId,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              if (userMessages.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: MessageAnchorRail(
                      userMessages: userMessages,
                      activeMessageId: activeAnchorMessageId,
                      maxHeight: constraints.maxHeight * 0.5,
                      onSelectMessage: onSelectMessage,
                    ),
                  ),
                ),
              if (showScrollToBottom)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    onPressed: onScrollToBottomPressed,
                    tooltip: '滚动到底部',
                    child: const Icon(Icons.arrow_downward_rounded),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Map<String, MessageVersionInfo> _buildMessageVersionInfoMap() {
    if (conversation.messageNodes.isEmpty) {
      return const {};
    }

    final siblingsByParent = <String, List<ChatMessage>>{};
    for (final node in conversation.messageNodes) {
      final parentId = node.parentId ?? rootConversationParentId;
      siblingsByParent.putIfAbsent(parentId, () => <ChatMessage>[]).add(node);
    }

    final result = <String, MessageVersionInfo>{};
    for (final message in conversation.messages) {
      final parentId = message.parentId ?? rootConversationParentId;
      final siblings = siblingsByParent[parentId] ?? const <ChatMessage>[];
      if (siblings.length <= 1) {
        continue;
      }
      final index = siblings.indexWhere((item) => item.id == message.id);
      if (index == -1) {
        continue;
      }
      result[message.id] = MessageVersionInfo(
        parentId: parentId,
        currentIndex: index,
        siblings: siblings,
      );
    }
    return result;
  }

  Widget _buildComposerCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: messageController,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: '输入消息',
                hintText: '输入你的问题、指令或待处理内容。',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ThinkingToggle(
                          enabled: supportsReasoning,
                          value: supportsReasoning && reasoningEnabled,
                          onChanged: onReasoningEnabledChanged,
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 132,
                          child: _buildReasoningEffortSelector(compact: true),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: !hasModels || isStreaming
                      ? null
                      : () {
                          onSendPressed?.call();
                        },
                  icon: Icon(
                    isStreaming
                        ? Icons.hourglass_top_rounded
                        : Icons.send_rounded,
                  ),
                  label: Text(isStreaming ? '生成中' : '发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasoningEffortSelector({bool compact = false}) {
    return DropdownButtonFormField<ReasoningEffort>(
      key: ValueKey(reasoningEffort),
      initialValue: reasoningEffort,
      isExpanded: true,
      items: ReasoningEffort.values
          .map((effort) {
            return DropdownMenuItem(
              value: effort,
              child: Text(_effortLabel(effort)),
            );
          })
          .toList(growable: false),
      onChanged: supportsReasoning && reasoningEnabled
          ? (value) {
              if (value != null) {
                onReasoningEffortChanged?.call(value);
              }
            }
          : null,
      decoration: InputDecoration(
        labelText: '思考负担',
        isDense: compact,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
            : null,
      ),
    );
  }

  String _effortLabel(ReasoningEffort effort) {
    return switch (effort) {
      ReasoningEffort.low => 'low',
      ReasoningEffort.medium => 'med',
      ReasoningEffort.high => 'high',
      ReasoningEffort.xhigh => 'xhigh',
    };
  }
}
