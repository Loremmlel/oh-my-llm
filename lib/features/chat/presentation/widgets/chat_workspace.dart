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
    required this.showScrollToBottom,
    required this.onDismissError,
    required this.onEditMessage,
    required this.onRetryLatestAssistant,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onOpenFixedPromptSequenceRunner,
    required this.onScrollToBottomPressed,
    required this.onSelectMessage,
    required this.onSelectMessageVersion,
    required this.onSendPressed,
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
  final bool showScrollToBottom;
  final VoidCallback onDismissError;
  final ValueChanged<ChatMessage> onEditMessage;
  final Future<void> Function() onRetryLatestAssistant;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final Future<void> Function() onOpenFixedPromptSequenceRunner;
  final VoidCallback onScrollToBottomPressed;
  final ValueChanged<String> onSelectMessage;
  final Future<void> Function(String parentId, String messageId)
  onSelectMessageVersion;
  final Future<void> Function()? onSendPressed;

  @override
  /// 构建消息区、错误提示和输入区的整体布局。
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

  /// 构建当前对话的错误提示横幅。
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

  /// 构建消息列表卡片，并把版本信息和锚点条组装进去。
  Widget _buildMessagesCard(ThemeData theme) {
    final latestAssistantMessage =
        messages.lastOrNull?.role == ChatMessageRole.assistant
        ? messages.lastOrNull
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
                  itemCount: messages.length,
                  separatorBuilder: (context, index) {
                    return const SizedBox(height: 12);
                  },
                  itemBuilder: (context, index) {
                    final message = messages[index];

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

  /// 构建消息输入区、思考开关和发送按钮。
  ///
  /// 宽度 < 520 时改为双行布局：
  ///   - 第一行：思考开关 + 思考强度选择（各占 Expanded，无横向滚动）
  ///   - 第二行：固定顺序提示词按钮 + 发送按钮（右对齐）
  ///
  /// 宽度 >= 520 时保持单行布局，思考控件区横向可滚动。
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
            LayoutBuilder(
              builder: (context, constraints) {
                // 宽度不足以在单行内舒适展示所有控件时，切换为双行布局
                const twoRowThreshold = 520.0;
                final isCompact = constraints.maxWidth < twoRowThreshold;

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildThinkingControlsRow(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: _buildActionButtons(),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildThinkingControlsRow(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ..._buildActionButtons(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建思考开关和思考强度选择器组成的横向控件行。
  Widget _buildThinkingControlsRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
    );
  }

  /// 构建固定顺序提示词按钮和发送按钮。
  List<Widget> _buildActionButtons() {
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
        onPressed: !hasModels || isStreaming
            ? null
            : () {
                onSendPressed?.call();
              },
        style: FilledButton.styleFrom(
          minimumSize: const Size(60, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(
          isStreaming ? Icons.hourglass_top_rounded : Icons.send_rounded,
        ),
        label: Text(isStreaming ? '生成中' : '发送'),
      ),
    ];
  }

  /// 构建思考强度下拉框。
  ///
  /// compact 模式去掉浮动标签（避免标签占据约 16px 的额外行高），
  /// 改用外层 [Tooltip] 提供提示，同时收紧 contentPadding。
  Widget _buildReasoningEffortSelector({bool compact = false}) {
    final dropdown = DropdownButtonFormField<ReasoningEffort>(
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
        // compact 模式省去浮动标签以减小高度；标签语义由外层 Tooltip 承担
        labelText: compact ? null : '思考负担',
        isDense: compact,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
            : null,
      ),
    );

    if (compact) {
      return Tooltip(message: '思考强度', child: dropdown);
    }
    return dropdown;
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
