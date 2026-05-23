import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/chat_word_counter.dart';
import '../../domain/models/chat_message.dart';
import 'message_version_info.dart';
import 'message_version_navigator.dart';
import 'reasoning_panel.dart';
import 'streaming_markdown_view.dart';

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

  final MessageVersionInfo? versionInfo;
  final Future<void> Function(String targetMessageId)? onSwitchVersion;

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  final _reasoningCounter = StreamingChatWordCounter();
  final _contentCounter = StreamingChatWordCounter();
  static const _maxUserMessageLines = 20;
  bool _isUserMessageCollapsed = true;

  /// 将消息正文复制到剪贴板。
  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.message.content));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制消息内容')));
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
    final shouldCollapseUserMessage = _shouldCollapseUserMessage(message);
    final isUserCollapsed = shouldCollapseUserMessage && _isUserMessageCollapsed;
    final userContent = isUserCollapsed
        ? _truncateContentToLines(message.content, _maxUserMessageLines)
        : message.content;
    final userSegments = message.userMessageSegments;
    final displaySegments = userSegments.isNotEmpty
        ? (isUserCollapsed
            ? _truncateUserMessageSegments(userSegments, userContent.length)
            : userSegments)
        : const <UserMessageSegment>[];

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
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
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () {
                        _copyMessage(context);
                      },
                      tooltip: '复制消息',
                      icon: const Icon(Icons.content_copy_rounded),
                    ),
                    if (widget.onToggleRequestExclusionPressed != null)
                      IconButton(
                        onPressed: widget.onToggleRequestExclusionPressed,
                        tooltip: widget.isExcludedFromRequest
                            ? '重新加入发送上下文'
                            : '从发送上下文中排除',
                        icon: Icon(
                          widget.isExcludedFromRequest
                              ? Icons.add_circle_outline_rounded
                              : Icons.remove_circle_outline_rounded,
                        ),
                      ),
                    if (widget.onFavoritePressed != null)
                      IconButton(
                        onPressed: widget.onFavoritePressed,
                        tooltip: widget.isFavorited ? '已收藏' : '收藏回复',
                        icon: Icon(
                          widget.isFavorited
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                        ),
                      ),
                    if (widget.canEdit)
                      IconButton(
                        onPressed: widget.onEditPressed,
                        tooltip: '编辑消息',
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (widget.canRetry)
                      IconButton(
                        onPressed: widget.onRetryPressed,
                        tooltip: '重试回复',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    if (widget.onDeletePressed != null)
                      IconButton(
                        onPressed: widget.onDeletePressed,
                        tooltip: '删除消息',
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                  ],
                ),
                if (!isUser &&
                    widget.inlineErrorMessage != null &&
                    widget.inlineErrorMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildInlineErrorCard(
                    theme,
                    widget.inlineErrorMessage!.trim(),
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
                if (isUser && shouldCollapseUserMessage) ...[
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

  Widget _buildInlineErrorCard(ThemeData theme, String message) {
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.72),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
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

  bool _shouldCollapseUserMessage(ChatMessage message) {
    if (message.role != ChatMessageRole.user) {
      return false;
    }
    return _countExplicitLines(message.content) > _maxUserMessageLines;
  }

  void _syncUserMessageCollapse(ChatMessage message, {bool reset = false}) {
    if (!_shouldCollapseUserMessage(message)) {
      _isUserMessageCollapsed = false;
      return;
    }
    if (reset) {
      _isUserMessageCollapsed = true;
    }
  }

  int _countExplicitLines(String content) {
    if (content.isEmpty) {
      return 1;
    }
    return '\n'.allMatches(content).length + 1;
  }

  String _truncateContentToLines(String content, int maxLines) {
    final lines = content.split('\n');
    if (lines.length <= maxLines) {
      return content;
    }
    return lines.take(maxLines).join('\n');
  }

  List<UserMessageSegment> _truncateUserMessageSegments(
    List<UserMessageSegment> segments,
    int maxLength,
  ) {
    var remaining = maxLength;
    final result = <UserMessageSegment>[];
    for (final segment in segments) {
      if (remaining <= 0) {
        break;
      }
      if (segment.text.length <= remaining) {
        result.add(segment);
        remaining -= segment.text.length;
        continue;
      }
      result.add(
        UserMessageSegment(
          text: segment.text.substring(0, remaining),
          kind: segment.kind,
        ),
      );
      break;
    }
    return result;
  }
}
