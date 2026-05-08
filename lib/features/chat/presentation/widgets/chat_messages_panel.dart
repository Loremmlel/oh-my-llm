import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';
import 'cached_chat_message_bubble.dart';
import 'empty_conversation_view.dart';
import 'message_anchor_rail.dart';
import 'message_version_info.dart';

/// 聊天工作区中的消息展示面板。
class ChatMessagesPanel extends StatelessWidget {
  static const transientErrorMessageId = '__transient_error_message__';

  const ChatMessagesPanel({
    required this.conversation,
    required this.messages,
    required this.userMessages,
    required this.hasModels,
    required this.activeAnchorMessageId,
    required this.messageItemScrollController,
    required this.messageItemPositionsListener,
    required this.isBusy,
    required this.errorMessage,
    required this.errorModelDisplayName,
    required this.showScrollToBottom,
    required this.onEditMessage,
    required this.onRetryLatestAssistant,
    required this.onDeleteMessage,
    required this.onToggleRequestExclusion,
    required this.onScrollToBottomPressed,
    required this.onSelectMessage,
    required this.onSelectMessageVersion,
    this.onFavoritePressed,
    this.favoritedAssistantContents = const {},
    super.key,
  });

  final ChatConversation conversation;
  final List<ChatMessage> messages;
  final List<ChatMessage> userMessages;
  final bool hasModels;
  final String? activeAnchorMessageId;
  final ItemScrollController messageItemScrollController;
  final ItemPositionsListener messageItemPositionsListener;
  final bool isBusy;
  final String? errorMessage;
  final String errorModelDisplayName;
  final bool showScrollToBottom;
  final ValueChanged<ChatMessage> onEditMessage;
  final Future<void> Function() onRetryLatestAssistant;
  final ValueChanged<ChatMessage> onDeleteMessage;
  final ValueChanged<ChatMessage> onToggleRequestExclusion;
  final VoidCallback onScrollToBottomPressed;
  final ValueChanged<String> onSelectMessage;
  final Future<void> Function(String parentId, String messageId)
  onSelectMessageVersion;
  final ValueChanged<ChatMessage>? onFavoritePressed;
  final Set<String> favoritedAssistantContents;

  @override
  Widget build(BuildContext context) {
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
                        message.id == transientErrorMessageId;

                    return KeyedSubtree(
                      key: ValueKey(message.id),
                      child: CachedChatMessageBubble(
                        message: message,
                        canEdit:
                            !isBusy && message.role == ChatMessageRole.user,
                        canRetry:
                            !isBusy && latestAssistantMessage?.id == message.id,
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
                        onDeletePressed: !isBusy && !isTransientError
                            ? () {
                                onDeleteMessage(message);
                              }
                            : null,
                        isExcludedFromRequest:
                            !isTransientError &&
                            conversation.isMessageExcluded(message.id),
                        onToggleRequestExclusionPressed:
                            !isBusy && !isTransientError && !message.isStreaming
                            ? () {
                                onToggleRequestExclusion(message);
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
        id: transientErrorMessageId,
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
}
