import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/theme/app_ui_colors.dart';
import 'package:oh_my_llm/core/widgets/llm_usage_widgets.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_context_ext.dart';

import '../../../../domain/chat_word_counter.dart';
import '../../../../domain/models/chat_message.dart';
import '../../images/chat_image_strip.dart';
import 'chat_message_bubble_state.dart';
import '../navigation/message_version_navigator.dart';
import 'chat_inline_empty_reply_card.dart';
import 'chat_inline_error_card.dart';
import 'reasoning_panel.dart';
import 'streaming_markdown_view.dart';
import 'user_message_collapse.dart';

/// 单条聊天消息气泡，负责正文、推理内容和消息操作。
class ChatMessageBubble extends StatefulWidget {
  const ChatMessageBubble({
    required this.message,
    this.state = const ChatMessageBubbleState(),
    this.actions = const ChatMessageBubbleActions(),
    super.key,
  });

  final ChatMessage message;
  final ChatMessageBubbleState state;
  final ChatMessageBubbleActions actions;

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  final _contentCounter = StreamingChatWordCounter();
  bool _isUserMessageCollapsed = true;

  /// 将消息正文复制到剪贴板。
  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(
        text: widget.message.content.isEmpty
            ? widget.state.inlineErrorMessage ?? ''
            : widget.message.content,
      ),
    );
    if (!context.mounted) return;
    context.showBubble('已复制消息内容');
  }

  Widget _copyButton(BuildContext context) {
    return _iconButton(
      onPressed: () => _copyMessage(context),
      tooltip: '复制消息',
      icon: Icons.content_copy_rounded,
    );
  }

  Widget _moreButton() {
    return PopupMenuButton<String>(
      tooltip: '消息操作',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) {
        if (value == 'exclude') {
          widget.actions.onToggleRequestExclusionPressed?.call();
        }
        if (value == 'delete') widget.actions.onDeletePressed?.call();
      },
      itemBuilder: (context) => [
        if (widget.actions.onToggleRequestExclusionPressed != null)
          PopupMenuItem(
            value: 'exclude',
            child: Text(
              widget.state.isExcludedFromRequest ? '重新加入发送上下文' : '从发送上下文中排除',
            ),
          ),
        if (widget.actions.onDeletePressed != null)
          PopupMenuItem(
            value: 'delete',
            child: Text(
              '删除消息',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _favoriteButton() {
    return _iconButton(
      onPressed: widget.actions.onFavoritePressed,
      tooltip: widget.state.isFavorited ? '已收藏' : '收藏回复',
      icon: widget.state.isFavorited
          ? Icons.bookmark_rounded
          : Icons.bookmark_border_rounded,
    );
  }

  Widget _iconButton({
    required VoidCallback? onPressed,
    required String tooltip,
    required IconData icon,
  }) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          textStyle: Theme.of(context).textTheme.bodySmall,
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        icon: Icon(icon, size: 16),
        label: Text(switch (tooltip) {
          '复制消息' => '复制',
          '收藏回复' => '收藏',
          '编辑消息' => '编辑',
          '重试回复' => '重试',
          _ => tooltip,
        }),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _syncCounters(widget.message);
    _syncUserMessageCollapse(widget.message, reset: true);
  }

  @override
  void didUpdateWidget(covariant ChatMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      // 消息 id 变更（重试或切换会话），重置计数器后重新扫描。
      _contentCounter.reset();
      _syncUserMessageCollapse(widget.message, reset: true);
    } else if (oldWidget.message.content != widget.message.content ||
        oldWidget.message.role != widget.message.role) {
      _syncUserMessageCollapse(widget.message);
    }
    _syncCounters(widget.message);
  }

  void _syncCounters(ChatMessage message) {
    _contentCounter.update(message.content);
  }

  @override
  /// 构建按角色区分样式的消息气泡。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final viewState = widget.state;
    final versionInfo = viewState.versionInfo;
    final isUser = message.role == ChatMessageRole.user;
    final usage = message.tokenUsage;
    final hasDisplayableUsage =
        usage != null &&
        (usage.inputTokens != null ||
            usage.cachedInputTokens != null ||
            usage.cacheWriteInputTokens != null ||
            usage.outputTokens != null);
    final needsCollapse = shouldCollapseUserMessage(message);
    final isUserCollapsed = needsCollapse && _isUserMessageCollapsed;
    final userContent = isUserCollapsed
        ? truncateContentToLines(message.content, maxUserMessageLines)
        : message.content;
    final userSegments = message.userMessageSegments;
    final displaySegments = userSegments.isNotEmpty
        ? (isUserCollapsed
              ? truncateUserMessageSegments(userSegments, userContent.length)
              : userSegments)
        : const <UserMessageSegment>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        // 统一左右阅读边界，宽窗口限制行长，短消息也沿同一画布对齐。
        final isNarrow = AppBreakpoints.useFullWidthMessageBubble(
          constraints.maxWidth,
        );
        final bubbleWidth = isNarrow
            ? constraints.maxWidth - 16
            : min(constraints.maxWidth - 32, AppContentWidths.chatReading);
        return Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: bubbleWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser)
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Tooltip(
                                  message:
                                      message.resolvedAssistantModelDisplayName,
                                  child: Text(
                                    message.resolvedAssistantModelDisplayName,
                                    style: theme.textTheme.labelLarge,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (viewState.isExcludedFromRequest) ...[
                                  const SizedBox(height: 4),
                                  _buildRequestExclusionChip(theme, message.id),
                                ],
                              ],
                            ),
                          ),
                          if (message.isStreaming) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                    if (!isUser &&
                        viewState.inlineErrorMessage != null &&
                        viewState.inlineErrorMessage!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      if (viewState.isEmptyReply)
                        ChatInlineEmptyReplyCard(
                          message: viewState.inlineErrorMessage!.trim(),
                        )
                      else
                        ChatInlineErrorCard(
                          message: viewState.inlineErrorMessage!.trim(),
                        ),
                    ],
                    if (!isUser &&
                        message.reasoningContent.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ReasoningPanel(
                        content: message.reasoningContent,
                        isStreaming: message.isStreaming,
                      ),
                      const SizedBox(height: 8),
                    ] else
                      const SizedBox(height: 8),
                    if (message.images.isNotEmpty) ...[
                      ChatImageStrip(images: message.images),
                      const SizedBox(height: 8),
                    ],
                    if (!isUser || message.content.isNotEmpty)
                      _buildMessageContent(
                        theme,
                        isUser: isUser,
                        content: isUser ? userContent : message.content,
                        segments: isUser ? displaySegments : const [],
                      ),
                    if (isUser && needsCollapse) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _isUserMessageCollapsed =
                                  !_isUserMessageCollapsed;
                            });
                          },
                          icon: Icon(
                            isUserCollapsed
                                ? Icons.unfold_more_rounded
                                : Icons.unfold_less_rounded,
                            size: 18,
                          ),
                          label: Text(isUserCollapsed ? '展开全文' : '收起内容'),
                        ),
                      ),
                    ],
                    if (isUser && viewState.isExcludedFromRequest)
                      _buildRequestExclusionChip(theme, message.id),
                    if (!isUser) ...[
                      const SizedBox(height: AppSpacing.xs),
                      DefaultTextStyle(
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xxs,
                          children: [
                            if (_shouldShowWordCount(message))
                              _buildWordCountRow(theme),
                            if (message.appliedCheckpointTitle
                                .trim()
                                .isNotEmpty)
                              _buildCheckpointUsageRow(
                                theme,
                                message.appliedCheckpointTitle,
                              ),
                            if (!message.isStreaming && hasDisplayableUsage)
                              _buildTokenUsageRow(theme, message),
                            if (!message.isStreaming &&
                                message.finishReason != null &&
                                message.finishReason != 'stop')
                              _buildFinishReasonChip(theme, message),
                          ],
                        ),
                      ),
                    ],
                    Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Wrap(
                        alignment: isUser
                            ? WrapAlignment.end
                            : WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.xxs,
                        children: [
                          _copyButton(context),
                          if (widget.actions.onFavoritePressed != null)
                            _favoriteButton(),
                          if (viewState.canEdit)
                            _iconButton(
                              onPressed: widget.actions.onEditPressed,
                              tooltip: '编辑消息',
                              icon: Icons.edit_outlined,
                            ),
                          if (viewState.canRetry)
                            _iconButton(
                              onPressed: widget.actions.onRetryPressed,
                              tooltip: '重试回复',
                              icon: Icons.refresh_rounded,
                            ),
                          if (widget.actions.onDeletePressed != null ||
                              widget.actions.onToggleRequestExclusionPressed !=
                                  null)
                            _moreButton(),
                        ],
                      ),
                    ),
                    if (isUser && viewState.autoRetryCount > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '第 ${viewState.autoRetryCount} 次重试中...',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (versionInfo != null) ...[
                      const SizedBox(height: 8),
                      MessageVersionNavigator(
                        currentIndex: versionInfo.currentIndex,
                        total: versionInfo.siblings.length,
                        onPrevious: versionInfo.currentIndex > 0
                            ? () {
                                widget.actions.onSwitchVersion?.call(
                                  versionInfo
                                      .siblings[versionInfo.currentIndex - 1]
                                      .id,
                                );
                              }
                            : null,
                        onNext:
                            versionInfo.currentIndex <
                                versionInfo.siblings.length - 1
                            ? () {
                                widget.actions.onSwitchVersion?.call(
                                  versionInfo
                                      .siblings[versionInfo.currentIndex + 1]
                                      .id,
                                );
                              }
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFinishReasonChip(ThemeData theme, ChatMessage message) {
    final reason = message.finishReason!;
    final color = reason == 'content_filter'
        ? theme.colorScheme.error
        : theme.uiColors.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline, size: 14, color: color),
        const SizedBox(width: 4),
        Text(reason, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }

  Widget _buildTokenUsageRow(ThemeData theme, ChatMessage message) {
    return LlmReplyUsage(usage: message.tokenUsage!);
  }

  /// 推理字数在折叠标题显示，底部只记录回复字数。
  Widget _buildWordCountRow(ThemeData theme) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final label = '回复：${_contentCounter.count} 字';

    return Padding(
      padding: EdgeInsets.zero,
      child: Text(label, style: style),
    );
  }

  /// 构建检查点使用提示行。
  Widget _buildCheckpointUsageRow(ThemeData theme, String checkpointTitle) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: EdgeInsets.zero,
      child: Text('使用检查点：$checkpointTitle', style: style),
    );
  }

  Widget _buildRequestExclusionChip(ThemeData theme, String messageId) {
    return DecoratedBox(
      key: ValueKey('message-excluded-chip-$messageId'),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadii.tag),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          '不发送',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }

  /// 判断当前助手消息是否需要显示字数统计。
  bool _shouldShowWordCount(ChatMessage message) {
    return message.content.trim().isNotEmpty ||
        message.reasoningContent.trim().isNotEmpty;
  }

  /// 根据消息角色选择更合适的正文渲染方式。
  Widget _buildMessageContent(
    ThemeData theme, {
    required bool isUser,
    required String content,
    required List<UserMessageSegment> segments,
  }) {
    if (isUser) {
      final bodyColor = theme.colorScheme.onSurface;
      final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
        color: bodyColor,
        fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) + 2,
        height: 1.6,
      );
      final templateStyle = theme.textTheme.bodyMedium?.copyWith(
        color: bodyColor.withValues(alpha: 0.62),
      );

      if (segments.isNotEmpty) {
        return _userInputBlock(
          theme,
          SelectableText.rich(
            TextSpan(
              style: bodyStyle,
              children: segments
                  .map((segment) {
                    return TextSpan(
                      text: segment.text,
                      style: segment.kind == UserMessageSegmentKind.body
                          ? bodyStyle
                          : templateStyle,
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        );
      }

      // 用户消息只需要按原文展示，不需要为 Markdown 解析支付额外成本。
      return _userInputBlock(theme, SelectableText(content, style: bodyStyle));
    }

    return StreamingMarkdownView(
      content: content,
      isStreaming: widget.message.isStreaming,
    );
  }

  Widget _userInputBlock(ThemeData theme, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: theme.uiColors.userInput,
      borderRadius: BorderRadius.circular(AppRadii.md),
    ),
    child: child,
  );

  void _syncUserMessageCollapse(ChatMessage message, {bool reset = false}) {
    if (!shouldCollapseUserMessage(message)) {
      _isUserMessageCollapsed = false;
      return;
    }
    if (reset) {
      _isUserMessageCollapsed = true;
    }
  }
}
