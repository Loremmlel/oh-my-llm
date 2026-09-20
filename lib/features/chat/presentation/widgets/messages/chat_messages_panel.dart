import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';

import '../../../application/workspace/chat_workspace_view_state.dart';
import '../workspace/chat_workspace_bindings.dart';
import '../../../domain/models/chat_conversation.dart';
import '../../../domain/chat_message_parent.dart';
import '../../../domain/models/chat_message.dart';
import 'bubble/cached_chat_message_bubble.dart';
import 'bubble/chat_message_bubble_state.dart';
import 'empty_conversation_view.dart';
import 'navigation/message_anchor_rail.dart';
import 'navigation/message_version_info.dart';

/// 聊天工作区中的消息展示面板。
///
/// 用 [StatefulWidget] 缓存消息版本信息与展示消息列表。版本关系以稳定的
/// canonical 消息树为输入，流式正文变化不会使该缓存失效。
class ChatMessagesPanel extends StatefulWidget {
  static const transientErrorMessageId = '__transient_error_message__';

  const ChatMessagesPanel({
    required this.state,
    required this.messageBindings,
    required this.scrollBindings,
    super.key,
  });

  final ChatWorkspaceMessagesState state;
  final ChatWorkspaceMessageBindings messageBindings;
  final ChatWorkspaceScrollBindings scrollBindings;

  @override
  State<ChatMessagesPanel> createState() => _ChatMessagesPanelState();
}

class _ChatMessagesPanelState extends State<ChatMessagesPanel> {
  // 固定像素缓存避免输入区高度动画逐帧改变虚拟列表的缓存边界。
  static const _messageListCacheExtent = 400.0;

  // ── 缓存：以输入指纹失效，避免流式高频 rebuild 时重复 O(n) 计算 ─────────
  // 使用不含流式正文覆盖的 canonical 会话作 key。
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
    final normalizedError = widget.state.errorMessage?.trim();

    // 移动端紧凑布局下整体缩小内边距，让消息气泡更宽。
    final listPadding = AppBreakpoints.isCompactShell(context) ? 10.0 : 14.0;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          if (widget.state.messages.isEmpty)
            EmptyConversationView(hasModels: widget.state.hasModels)
          else
            ScrollablePositionedList.separated(
              itemScrollController:
                  widget.scrollBindings.messageItemScrollController,
              itemPositionsListener:
                  widget.scrollBindings.messageItemPositionsListener,
              cacheExtent: _messageListCacheExtent,
              padding: EdgeInsets.all(listPadding),
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
          if (widget.state.userMessages.isNotEmpty)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              // 仅锚点条依赖可用高度，输入区动画不会重建消息列表。
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Align(
                    alignment: Alignment.centerRight,
                    // 锚点高亮随滚动局部刷新，不触发整页重建；
                    // ValueListenableBuilder 重建 MessageAnchorRail 时其
                    // didUpdateWidget 会折叠预览，保持滚动中紧凑体验。
                    child: ValueListenableBuilder<String?>(
                      valueListenable:
                          widget.scrollBindings.activeAnchorMessageIdListenable,
                      builder: (context, activeMessageId, _) {
                        return MessageAnchorRail(
                          userMessages: widget.state.userMessages,
                          activeMessageId: activeMessageId,
                          maxHeight: constraints.maxHeight * 0.5,
                          onSelectMessage:
                              widget.scrollBindings.onSelectMessage,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ValueListenableBuilder<bool>(
            valueListenable: widget.scrollBindings.showScrollToBottomListenable,
            builder: (context, showScrollToBottom, _) {
              if (!showScrollToBottom) return const SizedBox.shrink();
              return Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.small(
                  onPressed: widget.scrollBindings.onScrollToBottomPressed,
                  tooltip: '滚动到底部',
                  child: const Icon(Icons.arrow_downward_rounded),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 把临时错误拼接为一条助手样式消息，仅用于 UI 展示，不写入会话树。
  ///
  /// 常态及绑定到现有 assistant 的 inline error 直接复用 [widget.state.messages]；
  /// 只有需要追加无归属临时错误时才构造列表，并按 conversation/error 缓存。
  ///
  /// 缓存命中分两层：
  /// - [identical] 快速路径：非流式 rebuild（如 setState）下 conversation
  ///   引用未变，O(1) 直接命中，跳过 Equatable 深度比较。
  /// - `==` 值比较路径：非流式来源产生等值实例时仍可复用缓存。
  List<ChatMessage> _resolveDisplayMessages() {
    final normalizedError = widget.state.errorMessage?.trim();
    final hasError = normalizedError != null && normalizedError.isNotEmpty;
    final errorAssistantId = widget.state.errorMessageAssistantId;
    if (!hasError || (errorAssistantId?.trim().isNotEmpty ?? false)) {
      return widget.state.messages;
    }

    final conversation = widget.state.conversation;
    if ((identical(_displayMessagesConversation, conversation) ||
            _displayMessagesConversation == conversation) &&
        _displayMessagesError == normalizedError &&
        _displayMessagesErrorAssistantId == errorAssistantId &&
        _displayMessagesCache != null) {
      return _displayMessagesCache!;
    }

    final result = <ChatMessage>[
      ...widget.state.messages,
      ChatMessage(
        id: ChatMessagesPanel.transientErrorMessageId,
        role: ChatMessageRole.assistant,
        content: normalizedError,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        parentId:
            widget.state.messages.lastOrNull?.id ?? rootConversationParentId,
        assistantModelDisplayName: widget.state.errorModelDisplayName,
      ),
    ];
    _displayMessagesConversation = conversation;
    _displayMessagesError = normalizedError;
    _displayMessagesErrorAssistantId = errorAssistantId;
    _displayMessagesCache = List.unmodifiable(result);
    return _displayMessagesCache!;
  }

  /// 为每条消息计算可切换的版本信息。
  ///
  /// 仅当 conversation 变化时重算。conversation 是 Equatable，值比较能
  /// 正确命中缓存；messages getter 每次返回新 List 不可作 key。
  /// 同 [_resolveDisplayMessages]，先 [identical] 快速路径再降级 `==`。
  Map<String, MessageVersionInfo> _resolveVersionInfoMap() {
    final conversation = widget.state.structureConversation;
    if (conversation.messageNodes.isEmpty) {
      _versionInfoCache = const {};
      _versionInfoConversation = conversation;
      return _versionInfoCache!;
    }

    if ((identical(_versionInfoConversation, conversation) ||
            _versionInfoConversation == conversation) &&
        _versionInfoCache != null) {
      return _versionInfoCache!;
    }

    final messages = conversation.messages;
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
            widget.state.errorMessageAssistantId == message.id
        ? normalizedError
        : null;

    return KeyedSubtree(
      key: ValueKey(message.id),
      child: CachedChatMessageBubble(
        message: message,
        state: ChatMessageBubbleState(
          inlineErrorMessage: inlineErrorMessage,
          isEmptyReply:
              widget.state.emptyReplyAssistantId != null &&
              widget.state.emptyReplyAssistantId == message.id,
          canEdit: !widget.state.isBusy && isUser,
          canRetry:
              !widget.state.isBusy && latestAssistantMessage?.id == message.id,
          isExcludedFromRequest:
              !isTransientError &&
              widget.state.conversation.isMessageExcluded(message.id),
          isFavorited:
              !isTransientError &&
              isAssistant &&
              widget.state.favoritedAssistantContents.contains(message.content),
          autoRetryCount:
              lastUserMessageId != null && message.id == lastUserMessageId
              ? widget.state.autoRetryCount
              : 0,
          versionInfo: versionInfoByMessageId[message.id],
        ),
        actions: ChatMessageBubbleActions(
          onEditPressed: isUser
              ? () => widget.messageBindings.onEditMessage(message)
              : null,
          onRetryPressed: latestAssistantMessage?.id == message.id
              ? () => widget.messageBindings.onRetryLatestAssistant()
              : null,
          onDeletePressed: !widget.state.isBusy && !isTransientError
              ? () => widget.messageBindings.onDeleteMessage(message)
              : null,
          onToggleRequestExclusionPressed:
              !widget.state.isBusy && !isTransientError && !message.isStreaming
              ? () => widget.messageBindings.onToggleRequestExclusion(message)
              : null,
          onFavoritePressed:
              !isTransientError &&
                  isAssistant &&
                  !message.isStreaming &&
                  widget.messageBindings.onFavoritePressed != null
              ? () => widget.messageBindings.onFavoritePressed!(message)
              : null,
          onSwitchVersion: (targetMessageId) async {
            final versionInfo = versionInfoByMessageId[message.id];
            if (versionInfo == null) return;
            await widget.messageBindings.onSelectMessageVersion(
              versionInfo.parentId,
              targetMessageId,
            );
          },
        ),
      ),
    );
  }
}
