import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';
import 'cached_chat_message_bubble.dart';
import 'empty_conversation_view.dart';
import 'message_anchor_rail.dart';
import 'message_version_info.dart';
import 'thinking_toggle.dart';

/// 聊天页主工作区，组合消息列表、锚点条和消息输入区。
class ChatWorkspace extends StatelessWidget {
  static const _transientErrorMessageId = '__transient_error_message__';

  const ChatWorkspace({
    required this.conversation,
    required this.messages,
    required this.hasModels,
    required this.userMessages,
    required this.activeAnchorMessageId,
    required this.messageController,
    required this.messageItemScrollController,
    required this.messageItemPositionsListener,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.isStreaming,
    required this.errorMessage,
    required this.errorModelDisplayName,
    required this.showScrollToBottom,
    required this.onEditMessage,
    required this.onRetryLatestAssistant,
    required this.onDeleteMessage,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onOpenFixedPromptSequenceRunner,
    required this.onScrollToBottomPressed,
    required this.onSelectMessage,
    required this.onSelectMessageVersion,
    required this.onSendPressed,
    required this.onStopStreaming,
    this.onFavoritePressed,
    this.favoritedAssistantContents = const {},
    super.key,
  });

  final ChatConversation conversation;
  final List<ChatMessage> messages;
  final bool hasModels;
  final List<ChatMessage> userMessages;
  final String? activeAnchorMessageId;
  final TextEditingController messageController;
  final ItemScrollController messageItemScrollController;
  final ItemPositionsListener messageItemPositionsListener;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final bool isStreaming;
  final String? errorMessage;
  final String errorModelDisplayName;
  final bool showScrollToBottom;
  final ValueChanged<ChatMessage> onEditMessage;
  final Future<void> Function() onRetryLatestAssistant;
  final ValueChanged<ChatMessage> onDeleteMessage;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final Future<void> Function() onOpenFixedPromptSequenceRunner;
  final VoidCallback onScrollToBottomPressed;
  final ValueChanged<String> onSelectMessage;
  final Future<void> Function(String parentId, String messageId)
  onSelectMessageVersion;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  /// 点击收藏按钮时的回调（仅助手消息），为 null 则不显示收藏按钮。
  final ValueChanged<ChatMessage>? onFavoritePressed;

  /// 已收藏的助手消息内容集合，用于显示收藏高亮状态。
  final Set<String> favoritedAssistantContents;

  @override
  /// 构建消息区、错误提示和输入区的整体布局。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final messagesCard = _buildMessagesCard(theme);
        final composerCard = _buildComposerCard(context, theme);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: messagesCard),
            const SizedBox(height: 12),
            composerCard,
          ],
        );
      },
    );
  }

  /// 构建消息列表卡片，并把版本信息和锚点条组装进去。
  Widget _buildMessagesCard(ThemeData theme) {
    final displayMessages = _buildDisplayMessages();
    final latestAssistantMessage =
        displayMessages.lastOrNull?.role == ChatMessageRole.assistant
        ? displayMessages.lastOrNull
        : null;
    final versionInfoByMessageId = _buildMessageVersionInfoMap();

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchorRightPadding = userMessages.isEmpty ? 14.0 : 52.0;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (messages.isEmpty)
                EmptyConversationView(hasModels: hasModels)
              else
                ScrollablePositionedList.separated(
                  itemScrollController: messageItemScrollController,
                  itemPositionsListener: messageItemPositionsListener,
                  padding: EdgeInsets.fromLTRB(14, 14, anchorRightPadding, 14),
                  itemCount: displayMessages.length,
                  separatorBuilder: (context, index) {
                    return const SizedBox(height: 12);
                  },
                  itemBuilder: (context, index) {
                    final message = displayMessages[index];
                    final isTransientError =
                        message.id == _transientErrorMessageId;

                    return KeyedSubtree(
                      key: ValueKey(message.id),
                      child: CachedChatMessageBubble(
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
                        onRetryPressed: latestAssistantMessage?.id == message.id
                            ? () {
                                onRetryLatestAssistant();
                              }
                            : null,
                        onDeletePressed: !isStreaming && !isTransientError
                            ? () {
                                onDeleteMessage(message);
                              }
                            : null,
                        onFavoritePressed:
                            !isTransientError &&
                                message.role == ChatMessageRole.assistant &&
                                onFavoritePressed != null
                            ? () => onFavoritePressed!(message)
                            : null,
                        isFavorited:
                            !isTransientError &&
                            message.role == ChatMessageRole.assistant &&
                            favoritedAssistantContents.contains(
                              message.content,
                            ),
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
                    );
                  },
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

  /// 把临时错误拼接为一条助手样式消息，仅用于 UI 展示，不写入会话树。
  List<ChatMessage> _buildDisplayMessages() {
    final normalizedError = errorMessage?.trim();
    if (normalizedError == null || normalizedError.isEmpty) {
      return messages;
    }
    return [
      ...messages,
      ChatMessage(
        id: _transientErrorMessageId,
        role: ChatMessageRole.assistant,
        content: normalizedError,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        parentId: messages.lastOrNull?.id ?? rootConversationParentId,
        assistantModelDisplayName: errorModelDisplayName,
      ),
    ];
  }

  /// 为每条消息计算可切换的版本信息。
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
    for (final message in messages) {
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

  /// 构建消息输入区、思考控件和发送按钮。
  ///
  /// 所有控件压缩到单行，从左到右依次为：
  ///   深度思考 pill | 思考强度 pill | [Spacer] | 固定提示词图标 | 发送按钮
  ///
  /// 两个 pill 均为可点击的圆角矩形，高度约 28px，避免 [Switch] 撑开行高。
  Widget _buildComposerCard(BuildContext context, ThemeData theme) {
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
                ThinkingToggle(
                  enabled: supportsReasoning,
                  value: supportsReasoning && reasoningEnabled,
                  onChanged: onReasoningEnabledChanged,
                ),
                const SizedBox(width: 8),
                _buildEffortPill(context, theme),
                const Spacer(),
                ..._buildActionButtons(theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建思考强度 pill 选择器。
  ///
  /// 样式与 [ThinkingToggle] 一致，使用 [PopupMenuButton] 包裹，
  /// 点击后展示 low / med / high / xhigh 四个选项。
  /// 当深度思考未启用时，pill 变灰且不可交互。
  Widget _buildEffortPill(BuildContext context, ThemeData theme) {
    final isActive = supportsReasoning && reasoningEnabled;
    final backgroundColor = !supportsReasoning
        ? theme.colorScheme.surfaceContainerLow
        : isActive
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final borderColor = isActive
        ? theme.colorScheme.primary.withValues(alpha: 0.28)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.75);
    final labelColor = isActive
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    // PopupMenuButton 作为父容器，点击 pill 即可展开菜单
    return PopupMenuButton<ReasoningEffort>(
      enabled: isActive,
      initialValue: reasoningEffort,
      tooltip: '思考强度',
      onSelected: (value) => onReasoningEffortChanged?.call(value),
      itemBuilder: (context) => ReasoningEffort.values
          .map(
            (effort) =>
                PopupMenuItem(value: effort, child: Text(_effortLabel(effort))),
          )
          .toList(growable: false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 167),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _effortLabel(reasoningEffort),
              style: theme.textTheme.bodySmall?.copyWith(color: labelColor),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 14, color: labelColor),
          ],
        ),
      ),
    );
  }

  /// 构建固定顺序提示词按钮和发送按钮。
  List<Widget> _buildActionButtons(ThemeData theme) {
    return [
      IconButton.outlined(
        onPressed: onOpenFixedPromptSequenceRunner,
        tooltip: '固定顺序提示词',
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.playlist_play_rounded),
      ),
      const SizedBox(width: 8),
      FilledButton.icon(
        onPressed: isStreaming
            ? () {
                onStopStreaming?.call();
              }
            : !hasModels
            ? null
            : () {
                onSendPressed?.call();
              },
        style: FilledButton.styleFrom(
          minimumSize: const Size(60, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: isStreaming ? theme.colorScheme.error : null,
          foregroundColor: isStreaming ? theme.colorScheme.onError : null,
        ),
        icon: Icon(isStreaming ? Icons.stop_rounded : Icons.send_rounded),
        label: Text(isStreaming ? '终止回答' : '发送'),
      ),
    ];
  }

  /// 把枚举值转换为更短的显示文本。
  String _effortLabel(ReasoningEffort effort) {
    return switch (effort) {
      ReasoningEffort.low => 'low',
      ReasoningEffort.medium => 'med',
      ReasoningEffort.high => 'high',
      ReasoningEffort.xhigh => 'xhigh',
    };
  }
}
