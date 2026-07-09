import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/chat_message_parent.dart';
import '../../domain/models/chat_message.dart';
import 'cached_chat_message_bubble.dart';
import 'empty_conversation_view.dart';
import 'message_anchor_rail.dart';
import 'message_version_info.dart';

/// 聊天工作区中的消息展示面板。
///
/// 用 [StatefulWidget] 缓存消息版本信息与展示消息列表，避免流式期间
/// 每 300ms 重建时重复 O(n) 计算。缓存以输入指纹（conversation 与 messages
/// 的引用相等性）失效，仅在真正变更时重算。
class ChatMessagesPanel extends StatefulWidget {
  static const transientErrorMessageId = '__transient_error_message__';

  const ChatMessagesPanel({
    required this.conversation,
    required this.messages,
    required this.userMessages,
    required this.hasModels,
    required this.activeAnchorMessageIdListenable,
    required this.messageItemScrollController,
    required this.messageItemPositionsListener,
    required this.isBusy,
    required this.errorMessage,
    required this.errorMessageAssistantId,
    this.emptyReplyAssistantId,
    required this.errorModelDisplayName,
    required this.showScrollToBottomListenable,
    this.autoRetryCount = 0,
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
  final ValueListenable<String?> activeAnchorMessageIdListenable;
  final ItemScrollController messageItemScrollController;
  final ItemPositionsListener messageItemPositionsListener;
  final bool isBusy;
  final String? errorMessage;
  final String? errorMessageAssistantId;
  final String? emptyReplyAssistantId;
  final String errorModelDisplayName;
  final ValueListenable<bool> showScrollToBottomListenable;
  final int autoRetryCount;
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
  State<ChatMessagesPanel> createState() => _ChatMessagesPanelState();
}

class _ChatMessagesPanelState extends State<ChatMessagesPanel> {
  // ── 缓存：以输入指纹失效，避免流式高频 rebuild 时重复 O(n) 计算 ─────────
  // 用 ChatConversation（Equatable 值比较）作 key，而非 messages getter
  // 返回的 List（identity 比较，跨 build 永不相等会导致缓存 100% miss）。
  ChatConversation? _versionInfoConversation;
  Map<String, MessageVersionInfo>? _versionInfoCache;

  ChatConversation? _displayMessagesConversation;
  String? _displayMessagesError;
  String? _displayMessagesErrorAssistantId;
  List<ChatMessage>? _displayMessagesCache;

  @override
  Widget build(BuildContext context) {
    final displayMessages = _resolveDisplayMessages();
    final latestAssistantMessage =
        displayMessages.lastOrNull?.role == ChatMessageRole.assistant
        ? displayMessages.lastOrNull
        : null;
    final lastUserMessageId = displayMessages.isEmpty
        ? null
        : displayMessages
              .lastWhere(
                (m) => m.role == ChatMessageRole.user,
                orElse: () => displayMessages.last,
              )
              .id;
    final versionInfoByMessageId = _resolveVersionInfoMap();
    final normalizedError = widget.errorMessage?.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        const anchorRightPadding = 14.0;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (widget.messages.isEmpty)
                EmptyConversationView(hasModels: widget.hasModels)
              else
                ScrollablePositionedList.separated(
                  itemScrollController: widget.messageItemScrollController,
                  itemPositionsListener: widget.messageItemPositionsListener,
                  padding: EdgeInsets.fromLTRB(14, 14, anchorRightPadding, 14),
                  itemCount: displayMessages.length,
                  separatorBuilder: (context, index) {
                    return const SizedBox(height: 12);
                  },
                  itemBuilder: (context, index) => _buildBubbleItem(
                    displayMessages[index],
                    normalizedError: normalizedError,
                    latestAssistantMessage: latestAssistantMessage,
                    lastUserMessageId: lastUserMessageId,
                    versionInfoByMessageId: versionInfoByMessageId,
                  ),
                ),
              if (widget.userMessages.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerRight,
                    // 锚点高亮随滚动局部刷新，不触发整页重建；
                    // ValueListenableBuilder 重建 MessageAnchorRail 时其
                    // didUpdateWidget 会折叠预览，保持滚动中紧凑体验。
                    child: ValueListenableBuilder<String?>(
                      valueListenable: widget.activeAnchorMessageIdListenable,
                      builder: (context, activeMessageId, _) {
                        return MessageAnchorRail(
                          userMessages: widget.userMessages,
                          activeMessageId: activeMessageId,
                          maxHeight: constraints.maxHeight * 0.5,
                          onSelectMessage: widget.onSelectMessage,
                        );
                      },
                    ),
                  ),
                ),
              ValueListenableBuilder<bool>(
                valueListenable: widget.showScrollToBottomListenable,
                builder: (context, showScrollToBottom, _) {
                  if (!showScrollToBottom) return const SizedBox.shrink();
                  return Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      onPressed: widget.onScrollToBottomPressed,
                      tooltip: '滚动到底部',
                      child: const Icon(Icons.arrow_downward_rounded),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 把临时错误拼接为一条助手样式消息，仅用于 UI 展示，不写入会话树。
  ///
  /// 仅当 conversation/error/errorAssistantId 变化时重算，否则复用缓存。
  /// 用 [widget.conversation]（Equatable 值比较）作 key，而非
  /// [widget.messages]--后者由 getter 每次返回全新 List，identity 比较
  /// 永不相等会导致缓存 100% miss。
  ///
  /// 流式期间即使 provider 每 300ms 重建一次，只要 conversation 的字段
  /// （含 messageNodes/selectedChildByParentId）未实际变化，值比较仍命中
  /// 缓存，避免无新 token 时的重复拷贝。
  List<ChatMessage> _resolveDisplayMessages() {
    final normalizedError = widget.errorMessage?.trim();
    final hasError = normalizedError != null && normalizedError.isNotEmpty;
    final errorAssistantId = widget.errorMessageAssistantId;

    if (_displayMessagesConversation == widget.conversation &&
        _displayMessagesError == normalizedError &&
        _displayMessagesErrorAssistantId == errorAssistantId &&
        _displayMessagesCache != null) {
      return _displayMessagesCache!;
    }

    final result = <ChatMessage>[];
    if (!hasError ||
        (errorAssistantId != null && errorAssistantId.trim().isNotEmpty)) {
      result.addAll(widget.messages);
    } else {
      result
        ..addAll(widget.messages)
        ..add(
          ChatMessage(
            id: ChatMessagesPanel.transientErrorMessageId,
            role: ChatMessageRole.assistant,
            content: normalizedError,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
            parentId:
                widget.messages.lastOrNull?.id ?? rootConversationParentId,
            assistantModelDisplayName: widget.errorModelDisplayName,
          ),
        );
    }
    _displayMessagesConversation = widget.conversation;
    _displayMessagesError = normalizedError;
    _displayMessagesErrorAssistantId = errorAssistantId;
    _displayMessagesCache = List.unmodifiable(result);
    return _displayMessagesCache!;
  }

  /// 为每条消息计算可切换的版本信息。
  ///
  /// 仅当 conversation 变化时重算。conversation 是 Equatable，值比较能
  /// 正确命中缓存；messages getter 每次返回新 List 不可作 key。
  Map<String, MessageVersionInfo> _resolveVersionInfoMap() {
    final conversation = widget.conversation;
    final messages = widget.messages;
    if (conversation.messageNodes.isEmpty) {
      _versionInfoCache = const {};
      _versionInfoConversation = conversation;
      return _versionInfoCache!;
    }

    if (_versionInfoConversation == conversation && _versionInfoCache != null) {
      return _versionInfoCache!;
    }

    final siblingsByParent = <String, List<ChatMessage>>{};
    for (final node in conversation.messageNodes) {
      final parentId = node.effectiveParentId;
      siblingsByParent.putIfAbsent(parentId, () => <ChatMessage>[]).add(node);
    }

    final result = <String, MessageVersionInfo>{};
    for (final message in messages) {
      final parentId = message.effectiveParentId;
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
    _versionInfoConversation = conversation;
    _versionInfoCache = Map.unmodifiable(result);
    return _versionInfoCache!;
  }

  /// 构建单条消息气泡，封装 canEdit / canRetry 等权限判断与回调绑定。
  Widget _buildBubbleItem(
    ChatMessage message, {
    required String? normalizedError,
    required ChatMessage? latestAssistantMessage,
    required String? lastUserMessageId,
    required Map<String, MessageVersionInfo> versionInfoByMessageId,
  }) {
    final isTransientError =
        message.id == ChatMessagesPanel.transientErrorMessageId;
    final isUser = message.role == ChatMessageRole.user;
    final isAssistant = message.role == ChatMessageRole.assistant;
    final inlineErrorMessage =
        normalizedError != null &&
            normalizedError.isNotEmpty &&
            widget.errorMessageAssistantId == message.id
        ? normalizedError
        : null;

    return KeyedSubtree(
      key: ValueKey(message.id),
      child: CachedChatMessageBubble(
        message: message,
        inlineErrorMessage: inlineErrorMessage,
        isEmptyReply:
            widget.emptyReplyAssistantId != null &&
            widget.emptyReplyAssistantId == message.id,
        canEdit: !widget.isBusy && isUser,
        canRetry: !widget.isBusy && latestAssistantMessage?.id == message.id,
        onEditPressed: isUser ? () => widget.onEditMessage(message) : null,
        onRetryPressed: latestAssistantMessage?.id == message.id
            ? () => widget.onRetryLatestAssistant()
            : null,
        onDeletePressed: !widget.isBusy && !isTransientError
            ? () => widget.onDeleteMessage(message)
            : null,
        isExcludedFromRequest:
            !isTransientError &&
            widget.conversation.isMessageExcluded(message.id),
        onToggleRequestExclusionPressed:
            !widget.isBusy && !isTransientError && !message.isStreaming
            ? () => widget.onToggleRequestExclusion(message)
            : null,
        onFavoritePressed:
            !isTransientError && isAssistant && widget.onFavoritePressed != null
            ? () => widget.onFavoritePressed!(message)
            : null,
        isFavorited:
            !isTransientError &&
            isAssistant &&
            widget.favoritedAssistantContents.contains(message.content),
        autoRetryCount:
            lastUserMessageId != null && message.id == lastUserMessageId
            ? widget.autoRetryCount
            : 0,
        versionInfo: versionInfoByMessageId[message.id],
        onSwitchVersion: (targetMessageId) async {
          final versionInfo = versionInfoByMessageId[message.id];
          if (versionInfo == null) return;
          await widget.onSelectMessageVersion(
            versionInfo.parentId,
            targetMessageId,
          );
        },
      ),
    );
  }
}
