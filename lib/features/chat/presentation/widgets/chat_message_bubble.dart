import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/chat_message.dart';
import 'message_version_info.dart';
import 'message_version_navigator.dart';
import 'reasoning_panel.dart';
import 'streaming_markdown_view.dart';

/// 流式字数累计计数器。
///
/// 只处理 [update] 调用时新增的字符（O(Δ)），不重新扫描已处理内容，
/// 适合在每帧 streaming 回调中频繁调用。
///
/// 计字规则：
/// - 一个 CJK 汉字 = 1 字
/// - 一个连续英文字母序列（英文单词）= 1 字
/// - 标点、空格、数字、其他字符不计
class _StreamingWordCounter {
  int _count = 0;
  int _processedLength = 0;

  /// 上一个处理的字符是否属于英文字母（用于连续字母只计一次）。
  bool _inEnglishWord = false;

  /// 当前字数。
  int get count => _count;

  /// 更新计数：仅处理 [fullText] 中尚未处理的新增部分。
  void update(String fullText) {
    if (fullText.length < _processedLength) {
      reset();
    }
    for (var i = _processedLength; i < fullText.length; i++) {
      final c = fullText[i];
      if (_isCjk(c)) {
        _count++;
        _inEnglishWord = false;
      } else if (_isLetter(c)) {
        if (!_inEnglishWord) {
          _count++;
          _inEnglishWord = true;
        }
      } else {
        _inEnglishWord = false;
      }
    }
    _processedLength = fullText.length;
  }

  /// 重置所有状态（切换消息或重试时调用）。
  void reset() {
    _count = 0;
    _processedLength = 0;
    _inEnglishWord = false;
  }

  static bool _isCjk(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x4e00 && code <= 0x9fff) ||
        (code >= 0x3400 && code <= 0x4dbf) ||
        (code >= 0xf900 && code <= 0xfaff);
  }

  static bool _isLetter(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
  }
}

/// 单条聊天消息气泡，负责正文、推理内容和消息操作。
class ChatMessageBubble extends StatefulWidget {
  const ChatMessageBubble({
    required this.message,
    this.canEdit = false,
    this.canRetry = false,
    this.onEditPressed,
    this.onRetryPressed,
    this.onDeletePressed,
    this.onFavoritePressed,
    this.isFavorited = false,
    this.versionInfo,
    this.onSwitchVersion,
    super.key,
  });

  final ChatMessage message;
  final bool canEdit;
  final bool canRetry;
  final VoidCallback? onEditPressed;
  final VoidCallback? onRetryPressed;
  final VoidCallback? onDeletePressed;

  /// 收藏按钮回调，仅在助手消息上提供；为 null 则不显示收藏按钮。
  final VoidCallback? onFavoritePressed;

  /// 当前消息是否已被收藏，影响收藏图标的高亮状态。
  final bool isFavorited;

  final MessageVersionInfo? versionInfo;
  final Future<void> Function(String targetMessageId)? onSwitchVersion;

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  final _reasoningCounter = _StreamingWordCounter();
  final _contentCounter = _StreamingWordCounter();

  /// 将消息正文复制到剪贴板。
  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: widget.message.content),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制消息内容')));
  }

  @override
  void initState() {
    super.initState();
    _syncCounters(widget.message);
  }

  @override
  void didUpdateWidget(covariant ChatMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      // 消息 id 变更（重试或切换会话），重置计数器后重新扫描。
      _reasoningCounter.reset();
      _contentCounter.reset();
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
                      child: Tooltip(
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
                    ),
                    if (message.isStreaming) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                    IconButton(
                      onPressed: () {
                        _copyMessage(context);
                      },
                      tooltip: '复制消息',
                      icon: const Icon(Icons.content_copy_rounded),
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
                if (!isUser && _shouldShowWordCount(message))
                  _buildWordCountRow(theme, message),
                if (!isUser && message.reasoningContent.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ReasoningPanel(content: message.reasoningContent),
                  const SizedBox(height: 8),
                ] else
                  const SizedBox(height: 8),
                _buildMessageContent(theme, isUser: isUser),
                if (widget.versionInfo != null) ...[
                  const SizedBox(height: 8),
                  MessageVersionNavigator(
                    currentIndex: widget.versionInfo!.currentIndex,
                    total: widget.versionInfo!.siblings.length,
                    onPrevious: widget.versionInfo!.currentIndex > 0
                        ? () {
                            widget.onSwitchVersion?.call(
                              widget.versionInfo!
                                  .siblings[widget.versionInfo!.currentIndex - 1]
                                  .id,
                            );
                          }
                        : null,
                    onNext:
                        widget.versionInfo!.currentIndex <
                            widget.versionInfo!.siblings.length - 1
                        ? () {
                            widget.onSwitchVersion?.call(
                              widget.versionInfo!
                                  .siblings[widget.versionInfo!.currentIndex + 1]
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

  /// 判断当前助手消息是否需要显示字数统计。
  bool _shouldShowWordCount(ChatMessage message) {
    return message.content.trim().isNotEmpty ||
        message.reasoningContent.trim().isNotEmpty;
  }

  /// 根据消息角色选择更合适的正文渲染方式。
  Widget _buildMessageContent(ThemeData theme, {required bool isUser}) {
    if (isUser) {
      // 用户消息只需要按原文展示，不需要为 Markdown 解析支付额外成本。
      return SelectableText(
        widget.message.content,
        style: theme.textTheme.bodyLarge,
      );
    }

    return StreamingMarkdownView(
      content: widget.message.content,
      isStreaming: widget.message.isStreaming,
    );
  }
}
