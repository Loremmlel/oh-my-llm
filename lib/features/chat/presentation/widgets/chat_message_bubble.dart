import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/widgets/notification_bubble_context_ext.dart';
import '../../domain/chat_word_counter.dart';
import '../../domain/models/chat_message.dart';
import 'message_version_info.dart';
import 'message_version_navigator.dart';
import 'chat_inline_empty_reply_card.dart';
import 'chat_inline_error_card.dart';
import 'reasoning_panel.dart';
import 'streaming_markdown_view.dart';
import 'user_message_collapse.dart';

/// 单条聊天消息气泡，负责正文、推理内容和消息操作。
class ChatMessageBubble extends StatefulWidget {
  const ChatMessageBubble({
    required this.message,
    this.canEdit = false,
    this.canRetry = false,
    this.onEditPressed,
    this.onRetryPressed,
    this.onDeletePressed,
    this.onToggleRequestExclusionPressed,
    this.isExcludedFromRequest = false,
    this.onFavoritePressed,
    this.isFavorited = false,
    this.inlineErrorMessage,
    this.versionInfo,
    this.onSwitchVersion,
    this.autoRetryCount = 0,
    this.isEmptyReply = false,
    super.key,
  });

  final ChatMessage message;
  final bool canEdit;
  final bool canRetry;
  final VoidCallback? onEditPressed;
  final VoidCallback? onRetryPressed;
  final VoidCallback? onDeletePressed;
  final VoidCallback? onToggleRequestExclusionPressed;
  final bool isExcludedFromRequest;

  /// 收藏按钮回调，仅在助手消息上提供；为 null 则不显示收藏按钮。
  final VoidCallback? onFavoritePressed;

  /// 当前消息是否已被收藏，影响收藏图标的高亮状态。
  final bool isFavorited;

  /// 需要在该消息中展示的错误提示。
  final String? inlineErrorMessage;

  /// 当前自动重试次数，大于 0 时在用户消息中展示重试提示。
  final int autoRetryCount;

  /// 是否为模型返回的空回复错误。
  final bool isEmptyReply;

  final MessageVersionInfo? versionInfo;
  final Future<void> Function(String targetMessageId)? onSwitchVersion;

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  final _reasoningCounter = StreamingChatWordCounter();
  final _contentCounter = StreamingChatWordCounter();
  bool _isUserMessageCollapsed = true;

  /// 将消息正文复制到剪贴板。
  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.message.content));
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

  Widget _exclusionButton() {
    return _iconButton(
      onPressed: widget.onToggleRequestExclusionPressed,
      tooltip: widget.isExcludedFromRequest
          ? '重新加入发送上下文'
          : '从发送上下文中排除',
      icon: widget.isExcludedFromRequest
          ? Icons.add_circle_outline_rounded
          : Icons.remove_circle_outline_rounded,
    );
  }

  Widget _favoriteButton() {
    return _iconButton(
      onPressed: widget.onFavoritePressed,
      tooltip: widget.isFavorited ? '已收藏' : '收藏回复',
      icon: widget.isFavorited
          ? Icons.bookmark_rounded
          : Icons.bookmark_border_rounded,
    );
  }

  Widget _iconButton({
    required VoidCallback? onPressed,
    required String tooltip,
    required IconData icon,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
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
      _reasoningCounter.reset();
      _contentCounter.reset();
      _syncUserMessageCollapse(widget.message, reset: true);
    } else if (oldWidget.message.content != widget.message.content ||
        oldWidget.message.role != widget.message.role) {
      _syncUserMessageCollapse(widget.message);
    }
    _syncCounters(widget.message);
  }

  void _syncCounters(ChatMessage message) {
    _reasoningCounter.update(message.reasoningContent);
    _contentCounter.update(message.content);
  }

  @override
  /// 构建按角色区分样式的消息气泡。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final isUser = message.role == ChatMessageRole.user;
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
        // 窄屏（手机）直接充满只留 margin，宽屏（桌面）用百分比宽度
        final isNarrow = constraints.maxWidth < 600;
        final bubbleWidth = isNarrow
            ? constraints.maxWidth - 16
            : min(constraints.maxWidth * (isUser ? 0.65 : 0.75), 900.0);
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: bubbleWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Tooltip(
                            message: isUser
                                ? '你'
                                : message.resolvedAssistantModelDisplayName,
                            child: Text(
                              isUser
                                  ? '你'
                                  : message.resolvedAssistantModelDisplayName,
                              style: theme.textTheme.labelLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.isExcludedFromRequest) ...[
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
                const SizedBox(height: 2),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _copyButton(context),
                      if (widget.onToggleRequestExclusionPressed != null)
                        _exclusionButton(),
                      if (widget.onFavoritePressed != null)
                        _favoriteButton(),
                      if (widget.canEdit)
                        _iconButton(
                          onPressed: widget.onEditPressed,
                          tooltip: '编辑消息',
                          icon: Icons.edit_outlined,
                        ),
                      if (widget.canRetry)
                        _iconButton(
                          onPressed: widget.onRetryPressed,
                          tooltip: '重试回复',
                          icon: Icons.refresh_rounded,
                        ),
                      if (widget.onDeletePressed != null)
                        _iconButton(
                          onPressed: widget.onDeletePressed,
                          tooltip: '删除消息',
                          icon: Icons.delete_outline_rounded,
                        ),
                    ],
                  ),
                ),
                if (!isUser &&
                    widget.inlineErrorMessage != null &&
                    widget.inlineErrorMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  if (widget.isEmptyReply)
                    ChatInlineEmptyReplyCard(
                      message: widget.inlineErrorMessage!.trim(),
                    )
                  else
                    ChatInlineErrorCard(
                      message: widget.inlineErrorMessage!.trim(),
                    ),
                ],
                if (!isUser && message.appliedCheckpointTitle.trim().isNotEmpty)
                  _buildCheckpointUsageRow(
                    theme,
                    message.appliedCheckpointTitle,
                  ),
                if (!isUser && _shouldShowWordCount(message))
                  _buildWordCountRow(theme, message),
                if (!isUser && message.reasoningContent.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ReasoningPanel(content: message.reasoningContent),
                  const SizedBox(height: 8),
                ] else
                  const SizedBox(height: 8),
                _buildMessageContent(
                  theme,
                  isUser: isUser,
                  content: isUser ? userContent : message.content,
                  segments: isUser ? displaySegments : const [],
                ),
                if (!isUser &&
                    message.finishReason != null &&
                    !message.isStreaming)
                  _buildFinishReasonChip(theme, message),
                if (isUser && widget.autoRetryCount > 0) ...[
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
                        '第 ${widget.autoRetryCount} 次重试中...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
                if (isUser && needsCollapse) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _isUserMessageCollapsed = !_isUserMessageCollapsed;
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
                if (widget.versionInfo != null) ...[
                  const SizedBox(height: 8),
                  MessageVersionNavigator(
                    currentIndex: widget.versionInfo!.currentIndex,
                    total: widget.versionInfo!.siblings.length,
                    onPrevious: widget.versionInfo!.currentIndex > 0
                        ? () {
                            widget.onSwitchVersion?.call(
                              widget
                                  .versionInfo!
                                  .siblings[widget.versionInfo!.currentIndex -
                                      1]
                                  .id,
                            );
                          }
                        : null,
                    onNext:
                        widget.versionInfo!.currentIndex <
                            widget.versionInfo!.siblings.length - 1
                        ? () {
                            widget.onSwitchVersion?.call(
                              widget
                                  .versionInfo!
                                  .siblings[widget.versionInfo!.currentIndex +
                                      1]
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

  static Color _finishReasonColor(String reason, ColorScheme colorScheme) {
    switch (reason) {
      case 'stop':
        return colorScheme.tertiaryContainer;
      case 'length':
        return const Color.fromRGBO(255, 167, 38, 0.15);
      case 'content_filter':
        return const Color.fromRGBO(244, 67, 54, 0.15);
      default:
        return colorScheme.surfaceContainerHighest;
    }
  }

  static Color _finishReasonTextColor(
    String reason,
    ColorScheme colorScheme,
  ) {
    switch (reason) {
      case 'stop':
        return colorScheme.onTertiaryContainer;
      case 'length':
        return const Color.fromRGBO(230, 120, 0, 1.0);
      case 'content_filter':
        return const Color.fromRGBO(200, 40, 30, 1.0);
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  Widget _buildFinishReasonChip(ThemeData theme, ChatMessage message) {
    final reason = message.finishReason!;
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: _finishReasonColor(reason, colorScheme),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          reason,
          style: theme.textTheme.labelSmall?.copyWith(
            color: _finishReasonTextColor(reason, colorScheme),
          ),
        ),
      ),
    );
  }

  /// 构建字数统计行，格式视 reasoning 是否存在而定。
  Widget _buildWordCountRow(ThemeData theme, ChatMessage message) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final hasReasoning = message.reasoningContent.trim().isNotEmpty;
    final label = hasReasoning
        ? '深度思考：${_reasoningCounter.count} 字，回复：${_contentCounter.count} 字'
        : '回复：${_contentCounter.count} 字';

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(label, style: style),
    );
  }

  /// 构建检查点使用提示行。
  Widget _buildCheckpointUsageRow(ThemeData theme, String checkpointTitle) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text('使用检查点：$checkpointTitle', style: style),
    );
  }

  Widget _buildRequestExclusionChip(ThemeData theme, String messageId) {
    return DecoratedBox(
      key: ValueKey('message-excluded-chip-$messageId'),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
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
      final bodyColor = theme.colorScheme.onPrimaryContainer;
      final bodyStyle = theme.textTheme.bodyMedium?.copyWith(color: bodyColor);
      final templateStyle = theme.textTheme.bodyMedium?.copyWith(
        color: bodyColor.withValues(alpha: 0.62),
      );

      if (segments.isNotEmpty) {
        return SelectableText.rich(
          TextSpan(
            style: bodyStyle,
            children: segments.map((segment) {
              return TextSpan(
                text: segment.text,
                style: segment.kind == UserMessageSegmentKind.body
                    ? bodyStyle
                    : templateStyle,
              );
            }).toList(growable: false),
          ),
        );
      }

      // 用户消息只需要按原文展示，不需要为 Markdown 解析支付额外成本。
      return SelectableText(content, style: bodyStyle);
    }

    return StreamingMarkdownView(
      content: content,
      isStreaming: widget.message.isStreaming,
    );
  }

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
